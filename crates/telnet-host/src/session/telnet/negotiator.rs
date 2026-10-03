// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! The per-connection telnet negotiator: policy, option state, and protocol handlers.
//!
//! The negotiator consumes [`TelnetEvent`]s and local requests and returns [`Action`]s for the
//! session to apply in order. It owns no socket and never blocks.
//!
//! When the policy enables no protocol at all the negotiator is passive: it does not refuse
//! options the peer offers and it marks no prompts, so the bytes on the wire are what they were
//! before this layer existed. Local requests (client echo) still work.

use std::collections::HashMap;

use bytes::{Bytes, BytesMut};
use moor_var::{Symbol, Var, v_binary, v_bool, v_int, v_map, v_str, v_sym};
use tracing::{trace, warn};

use super::{
    charset::{self, Charset, CharsetMessage},
    consts::*,
    event::{TelnetEvent, Verb, write_subneg},
    gmcp::{self, GmcpError, GmcpSupports},
    msdp, mssp, naws,
    options::{Allow, OptionTable, Outcome, Policy, QState, Side},
    ttype::{self, TtypeCycle},
};

/// Default cap on the size of one subnegotiation, in bytes.
pub const DEFAULT_MAX_SUBNEG: usize = 65536;

/// MXP "locked mode by default" line mode, sent when MXP is enabled.
const MXP_LOCKED_DEFAULT: &[u8] = b"\x1b[7z";

/// Which protocols the host implements on a connection, mirroring `TelnetProtocolConfig`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProtocolPolicy {
    pub offer_on_connect: bool,
    pub gmcp: bool,
    pub msdp: bool,
    pub mssp: bool,
    pub mxp: bool,
    pub naws: bool,
    pub ttype: bool,
    pub eor: bool,
    pub charset: bool,
    pub mccp2: bool,
    pub max_subneg: usize,
    /// Static MSSP variables, in the order they are sent.
    pub mssp_values: Vec<(String, String)>,
}

impl Default for ProtocolPolicy {
    fn default() -> Self {
        Self {
            offer_on_connect: false,
            gmcp: false,
            msdp: false,
            mssp: false,
            mxp: false,
            naws: false,
            ttype: false,
            eor: false,
            charset: false,
            mccp2: false,
            max_subneg: DEFAULT_MAX_SUBNEG,
            mssp_values: Vec::new(),
        }
    }
}

impl ProtocolPolicy {
    /// True when at least one protocol is enabled.
    pub fn any_enabled(&self) -> bool {
        self.gmcp
            || self.msdp
            || self.mssp
            || self.mxp
            || self.naws
            || self.ttype
            || self.eor
            || self.charset
            || self.mccp2
    }

    /// The option table policy this protocol policy implies.
    fn option_policy(&self) -> Policy {
        let mut p = Policy::default();
        // ECHO is only ever enabled by a local request (`client-echo`).
        p.set(OPT_ECHO, Side::Us, Allow::Request);
        if self.any_enabled() {
            p.set(OPT_SGA, Side::Us, Allow::Accept);
            p.set(OPT_SGA, Side::Him, Allow::Accept);
        }
        let mut accept = |enabled: bool, option: u8, sides: &[Side]| {
            if !enabled {
                return;
            }
            for side in sides {
                p.set(option, *side, Allow::Accept);
            }
        };
        accept(self.gmcp, OPT_GMCP, &[Side::Us, Side::Him]);
        accept(self.msdp, OPT_MSDP, &[Side::Us, Side::Him]);
        accept(self.mssp, OPT_MSSP, &[Side::Us]);
        accept(self.mxp, OPT_MXP, &[Side::Us]);
        accept(self.eor, OPT_EOR, &[Side::Us]);
        accept(self.mccp2, OPT_MCCP2, &[Side::Us]);
        accept(self.naws, OPT_NAWS, &[Side::Him]);
        accept(self.ttype, OPT_TTYPE, &[Side::Him]);
        accept(self.charset, OPT_CHARSET, &[Side::Us, Side::Him]);
        p
    }
}

/// What the host writes after a prompt.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum PromptMark {
    /// Nothing.
    #[default]
    None,
    /// `IAC GA`.
    Ga,
    /// `IAC EOR`.
    Eor,
}

/// A telnet protocol frame for the session to write.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OutFrame {
    /// `IAC <verb> <option>`.
    Negotiate { verb: Verb, option: u8 },
    /// `IAC SB <option> <payload, escaped> IAC SE`; `payload` is unescaped.
    Subneg { option: u8, payload: Bytes },
    /// Bytes written as they are.
    Raw(Bytes),
}

impl OutFrame {
    /// The wire bytes of the frame.
    pub fn to_bytes(&self) -> Bytes {
        match self {
            OutFrame::Negotiate { verb, option } => Bytes::copy_from_slice(&verb.frame(*option)),
            OutFrame::Subneg { option, payload } => {
                let mut out = BytesMut::new();
                write_subneg(*option, payload, &mut out);
                out.freeze()
            }
            OutFrame::Raw(b) => b.clone(),
        }
    }
}

/// One thing the session must do, in the order returned.
#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    /// Write a frame.
    Send(OutFrame),
    /// Record a connection attribute; `None` removes it.
    SetAttribute { key: Symbol, value: Option<Var> },
    /// Send `ClientData(namespace, kind, payload)` to the daemon.
    Deliver {
        namespace: Symbol,
        kind: Symbol,
        payload: Var,
    },
    /// Start MCCP2: write the start marker uncompressed, then compress everything after it.
    StartCompress,
    /// End the MCCP2 stream; later output is uncompressed.
    StopCompress,
    /// Switch the codec's text charset.
    SetCharset(Charset),
    /// Change what is written after a prompt.
    SetPromptMark(PromptMark),
    /// The peer asked for MSSP. Answer with [`TelnetNegotiator::mssp_response`].
    MsspRequest,
}

/// Why an outbound data event was not encoded.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DataDrop {
    /// The namespace is not one the telnet host writes.
    UnknownNamespace,
    /// The protocol is not enabled on this connection.
    NotNegotiated,
    /// The client declared `Core.Supports` without this package.
    NotSupported,
    /// The GMCP package name is invalid.
    InvalidName,
    /// The payload has no JSON form.
    Unconvertible(String),
}

/// Telnet option negotiation and protocol state for one connection.
pub struct TelnetNegotiator {
    policy: ProtocolPolicy,
    passive: bool,
    options: OptionTable,
    boolean_returns: bool,
    attributes: HashMap<Symbol, Var>,
    prompt_mark: PromptMark,
    supports: GmcpSupports,
    ttype: TtypeCycle,
    charset: Charset,
    charset_pending: bool,
    utf8_from_charset: bool,
    client_name_from_gmcp: bool,
}

impl TelnetNegotiator {
    pub fn new(policy: ProtocolPolicy) -> Self {
        let passive = !policy.any_enabled();
        let options = OptionTable::new(policy.option_policy());
        let mut n = Self {
            policy,
            passive,
            options,
            boolean_returns: false,
            attributes: HashMap::new(),
            prompt_mark: PromptMark::None,
            supports: GmcpSupports::default(),
            ttype: TtypeCycle::default(),
            charset: Charset::Utf8,
            charset_pending: false,
            utf8_from_charset: false,
            client_name_from_gmcp: false,
        };
        n.prompt_mark = n.compute_prompt_mark();
        n
    }

    /// The daemon's `use_boolean_returns`, for JSON `true`/`false` received from the client.
    pub fn set_boolean_returns(&mut self, on: bool) {
        self.boolean_returns = on;
    }

    pub fn policy(&self) -> &ProtocolPolicy {
        &self.policy
    }

    pub fn max_subneg(&self) -> usize {
        self.policy.max_subneg
    }

    /// True when no protocol is configured; see the module docs.
    pub fn is_passive(&self) -> bool {
        self.passive
    }

    /// True when either side of `option` is enabled.
    pub fn is_enabled(&self, option: u8) -> bool {
        self.options.is_enabled(option, Side::Us) || self.options.is_enabled(option, Side::Him)
    }

    pub fn state(&self, option: u8, side: Side) -> QState {
        self.options.state(option, side)
    }

    pub fn prompt_mark(&self) -> PromptMark {
        self.prompt_mark
    }

    pub fn charset(&self) -> Charset {
        self.charset
    }

    pub fn gmcp_supports(&self) -> &GmcpSupports {
        &self.supports
    }

    /// The attributes the negotiator has set, as last reported.
    pub fn attributes(&self) -> &HashMap<Symbol, Var> {
        &self.attributes
    }

    /// The offers to send when the connection opens.
    pub fn initial_offers(&mut self) -> Vec<Action> {
        let mut out = Vec::new();
        if !self.policy.offer_on_connect {
            return out;
        }
        let p = &self.policy;
        let offers = [
            (p.gmcp, OPT_GMCP, Side::Us),
            (p.msdp, OPT_MSDP, Side::Us),
            (p.mssp, OPT_MSSP, Side::Us),
            (p.mxp, OPT_MXP, Side::Us),
            (p.eor, OPT_EOR, Side::Us),
            (p.charset, OPT_CHARSET, Side::Us),
            (p.mccp2, OPT_MCCP2, Side::Us),
            (p.naws, OPT_NAWS, Side::Him),
            (p.ttype, OPT_TTYPE, Side::Him),
        ];
        for (enabled, option, side) in offers {
            if enabled {
                out.extend(self.request(option, side, true));
            }
        }
        out
    }

    /// Ask to enable or disable one side of an option, e.g. from `set_connection_option`.
    /// Sends a verb only when the state requires one.
    pub fn request(&mut self, option: u8, side: Side, enable: bool) -> Vec<Action> {
        let outcome = self.options.request(option, side, enable);
        let mut out = Vec::new();
        self.apply_outcome(option, side, outcome, &mut out);
        out
    }

    /// The side a MOO-level toggle of `option` acts on.
    pub fn primary_side(option: u8) -> Side {
        match option {
            OPT_NAWS | OPT_TTYPE => Side::Him,
            _ => Side::Us,
        }
    }

    /// Handle one event from the codec.
    pub fn on_event(&mut self, event: TelnetEvent) -> Vec<Action> {
        let mut out = Vec::new();
        match event {
            TelnetEvent::Command(_) => {}
            TelnetEvent::Negotiate { verb, option } => self.on_negotiate(verb, option, &mut out),
            TelnetEvent::Subneg { option, data } => self.on_subneg(option, data, &mut out),
        }
        out
    }

    /// Encode an outbound `Event::Data` for this connection.
    pub fn encode_data(
        &self,
        namespace: &str,
        kind: &str,
        payload: &Var,
    ) -> Result<OutFrame, DataDrop> {
        match namespace {
            "gmcp" => {
                if !self.is_enabled(OPT_GMCP) {
                    return Err(DataDrop::NotNegotiated);
                }
                if !gmcp::valid_package_name(kind) {
                    return Err(DataDrop::InvalidName);
                }
                if !self.supports.wants(kind) {
                    return Err(DataDrop::NotSupported);
                }
                let body = gmcp::encode(kind, payload).map_err(|e| match e {
                    GmcpError::InvalidPackageName(_) => DataDrop::InvalidName,
                    GmcpError::Json(j) => DataDrop::Unconvertible(j.0),
                })?;
                Ok(OutFrame::Subneg {
                    option: OPT_GMCP,
                    payload: Bytes::from(body),
                })
            }
            "msdp" => {
                if !self.is_enabled(OPT_MSDP) {
                    return Err(DataDrop::NotNegotiated);
                }
                Ok(OutFrame::Subneg {
                    option: OPT_MSDP,
                    payload: Bytes::from(msdp::encode(kind, payload)),
                })
            }
            _ => Err(DataDrop::UnknownNamespace),
        }
    }

    /// The MSSP reply, given the player count and the server start time (Unix seconds).
    pub fn mssp_response(&self, players: u64, uptime: u64) -> OutFrame {
        OutFrame::Subneg {
            option: OPT_MSSP,
            payload: Bytes::from(mssp::encode(&self.policy.mssp_values, players, uptime)),
        }
    }

    fn on_negotiate(&mut self, verb: Verb, option: u8, out: &mut Vec<Action>) {
        let side = match verb {
            Verb::Will | Verb::Wont => Side::Him,
            Verb::Do | Verb::Dont => Side::Us,
        };
        let mut outcome = self.options.receive(verb, option);
        let refusal = matches!(verb, Verb::Will | Verb::Do)
            && self.options.state(option, side) == QState::No
            && outcome.send.is_some();
        if refusal && self.passive {
            outcome.send = None;
        }
        self.apply_outcome(option, side, outcome, out);
        if self.options.policy().implements(option) {
            return;
        }
        out.push(Action::Deliver {
            namespace: Symbol::mk("telnet"),
            kind: Symbol::mk("negotiate"),
            payload: v_map(&[
                (v_str("option"), v_int(option as i64)),
                (v_str("verb"), v_sym(verb.name())),
            ]),
        });
    }

    fn apply_outcome(&mut self, option: u8, side: Side, outcome: Outcome, out: &mut Vec<Action>) {
        if let Some(verb) = outcome.send {
            out.push(Action::Send(OutFrame::Negotiate { verb, option }));
        }
        let Some(enabled) = outcome.changed else {
            return;
        };
        // For options either side may carry, act only when the combined state flips.
        let other = match side {
            Side::Us => Side::Him,
            Side::Him => Side::Us,
        };
        if !self.options.is_enabled(option, other) {
            if enabled {
                self.on_enabled(option, out);
            } else {
                self.on_disabled(option, out);
            }
        }
        // The prompt mark depends on one side only (our SGA and EOR).
        self.update_prompt_mark(out);
    }

    fn on_enabled(&mut self, option: u8, out: &mut Vec<Action>) {
        match option {
            OPT_GMCP => self.set_attr("gmcp", Some(v_bool(true)), out),
            OPT_MSDP => self.set_attr("msdp", Some(v_bool(true)), out),
            OPT_EOR => self.set_attr("eor", Some(v_bool(true)), out),
            OPT_MSSP => out.push(Action::MsspRequest),
            OPT_MXP => {
                self.set_attr("mxp", Some(v_bool(true)), out);
                out.push(Action::Send(OutFrame::Subneg {
                    option: OPT_MXP,
                    payload: Bytes::new(),
                }));
                out.push(Action::Send(OutFrame::Raw(Bytes::from_static(
                    MXP_LOCKED_DEFAULT,
                ))));
            }
            OPT_MCCP2 => {
                out.push(Action::StartCompress);
                self.set_attr("mccp2", Some(v_bool(true)), out);
            }
            OPT_TTYPE => {
                self.ttype.reset();
                out.push(Action::Send(OutFrame::Subneg {
                    option: OPT_TTYPE,
                    payload: Bytes::from_static(&ttype::SEND_BODY),
                }));
            }
            OPT_CHARSET => {
                self.charset_pending = true;
                out.push(Action::Send(OutFrame::Subneg {
                    option: OPT_CHARSET,
                    payload: Bytes::from(charset::request_body()),
                }));
            }
            _ => {}
        }
    }

    fn on_disabled(&mut self, option: u8, out: &mut Vec<Action>) {
        match option {
            OPT_GMCP => {
                self.set_attr("gmcp", Some(v_bool(false)), out);
                if self.supports != GmcpSupports::default() {
                    self.supports = GmcpSupports::default();
                    self.set_attr("gmcp_supports", None, out);
                }
            }
            OPT_MSDP => self.set_attr("msdp", Some(v_bool(false)), out),
            OPT_EOR => self.set_attr("eor", Some(v_bool(false)), out),
            OPT_MXP => self.set_attr("mxp", Some(v_bool(false)), out),
            OPT_MCCP2 => {
                out.push(Action::StopCompress);
                self.set_attr("mccp2", Some(v_bool(false)), out);
            }
            OPT_NAWS => {
                self.set_attr("columns", None, out);
                self.set_attr("rows", None, out);
            }
            OPT_TTYPE => {
                self.ttype.reset();
                self.set_attr("terminal_type", None, out);
                self.set_attr("mtts", None, out);
            }
            OPT_CHARSET => {
                self.charset_pending = false;
                self.set_attr("charset", None, out);
                if self.charset != Charset::Utf8 {
                    self.charset = Charset::Utf8;
                    out.push(Action::SetCharset(Charset::Utf8));
                }
                if self.utf8_from_charset {
                    self.utf8_from_charset = false;
                    self.set_attr("utf8", Some(v_bool(false)), out);
                }
            }
            _ => {}
        }
    }

    fn on_subneg(&mut self, option: u8, data: Bytes, out: &mut Vec<Action>) {
        if !self.options.policy().implements(option) {
            out.push(Action::Deliver {
                namespace: Symbol::mk("telnet"),
                kind: Symbol::mk("subneg"),
                payload: v_map(&[
                    (v_str("option"), v_int(option as i64)),
                    (v_str("data"), v_binary(data.to_vec())),
                ]),
            });
            return;
        }
        if !self.is_enabled(option) {
            trace!(option, "subnegotiation for an option that is not enabled");
            return;
        }
        match option {
            OPT_NAWS => self.on_naws(&data, out),
            OPT_TTYPE => self.on_ttype(&data, out),
            OPT_CHARSET => self.on_charset(&data, out),
            OPT_GMCP => self.on_gmcp(&data, out),
            OPT_MSDP => {
                for (name, value) in msdp::decode(&data) {
                    out.push(Action::Deliver {
                        namespace: Symbol::mk("msdp"),
                        kind: Symbol::mk(&name),
                        payload: value,
                    });
                }
            }
            _ => trace!(option, "ignored subnegotiation"),
        }
    }

    fn on_naws(&mut self, data: &[u8], out: &mut Vec<Action>) {
        let Some((cols, rows)) = naws::parse(data) else {
            warn!(len = data.len(), "malformed NAWS subnegotiation");
            return;
        };
        self.set_attr("columns", Some(v_int(cols as i64)), out);
        self.set_attr("rows", Some(v_int(rows as i64)), out);
    }

    fn on_ttype(&mut self, data: &[u8], out: &mut Vec<Action>) {
        let reply = self.ttype.on_subneg(data);
        if let Some(first) = reply.first {
            self.set_attr("terminal_type", Some(v_str(&first)), out);
            if !self.client_name_from_gmcp {
                self.set_attr("client_name", Some(v_str(&first)), out);
            }
        }
        if let Some(bits) = reply.mtts {
            self.set_attr("mtts", Some(v_int(bits)), out);
            if bits & ttype::MTTS_UTF8 != 0 {
                self.set_attr("utf8", Some(v_bool(true)), out);
            }
            if bits & ttype::MTTS_SCREEN_READER != 0 {
                self.set_attr("screen-reader", Some(v_bool(true)), out);
            }
        }
        if reply.send_again {
            out.push(Action::Send(OutFrame::Subneg {
                option: OPT_TTYPE,
                payload: Bytes::from_static(&ttype::SEND_BODY),
            }));
        }
    }

    fn on_charset(&mut self, data: &[u8], out: &mut Vec<Action>) {
        match charset::parse(data) {
            CharsetMessage::Accepted(Some(cs), _) => {
                self.charset_pending = false;
                self.select_charset(cs, out);
            }
            CharsetMessage::Accepted(None, name) => {
                self.charset_pending = false;
                warn!(name, "client accepted a charset that was not offered");
            }
            CharsetMessage::Rejected => self.charset_pending = false,
            // RFC 2066: while our own REQUEST is outstanding, the peer's is rejected.
            CharsetMessage::Request(_) if self.charset_pending => {
                out.push(self.charset_reply(vec![charset::REJECTED]));
            }
            CharsetMessage::Request(Some(cs)) => {
                out.push(self.charset_reply(charset::accepted_body(cs)));
                self.select_charset(cs, out);
            }
            CharsetMessage::Request(None) => {
                out.push(self.charset_reply(vec![charset::REJECTED]));
            }
            CharsetMessage::Other => trace!("ignored CHARSET subnegotiation"),
        }
    }

    fn charset_reply(&self, body: Vec<u8>) -> Action {
        Action::Send(OutFrame::Subneg {
            option: OPT_CHARSET,
            payload: Bytes::from(body),
        })
    }

    fn select_charset(&mut self, cs: Charset, out: &mut Vec<Action>) {
        self.set_attr("charset", Some(v_str(cs.name())), out);
        let utf8 = cs == Charset::Utf8;
        self.utf8_from_charset = utf8;
        self.set_attr("utf8", Some(v_bool(utf8)), out);
        if self.charset != cs {
            self.charset = cs;
            out.push(Action::SetCharset(cs));
        }
    }

    fn on_gmcp(&mut self, data: &[u8], out: &mut Vec<Action>) {
        let Some(message) = gmcp::decode(data, self.boolean_returns) else {
            warn!("GMCP message with an invalid package name");
            return;
        };
        let lower = message.package.to_ascii_lowercase();
        if lower == "core.hello" {
            let (client, version) = gmcp::hello_fields(&message.payload);
            if let Some(client) = client {
                self.client_name_from_gmcp = true;
                self.set_attr("client_name", Some(v_str(&client)), out);
            }
            if let Some(version) = version {
                self.set_attr("client_version", Some(v_str(&version)), out);
            }
        } else if lower.starts_with("core.supports.")
            && self.supports.apply(&message.package, &message.payload)
        {
            self.set_attr("gmcp_supports", Some(self.supports.to_var()), out);
        }
        out.push(Action::Deliver {
            namespace: Symbol::mk("gmcp"),
            kind: Symbol::mk(&message.package),
            payload: message.payload,
        });
    }

    fn compute_prompt_mark(&self) -> PromptMark {
        if self.passive {
            return PromptMark::None;
        }
        if self.options.is_enabled(OPT_EOR, Side::Us) {
            return PromptMark::Eor;
        }
        if self.options.is_enabled(OPT_SGA, Side::Us) {
            return PromptMark::None;
        }
        PromptMark::Ga
    }

    fn update_prompt_mark(&mut self, out: &mut Vec<Action>) {
        let mark = self.compute_prompt_mark();
        if mark == self.prompt_mark {
            return;
        }
        self.prompt_mark = mark;
        out.push(Action::SetPromptMark(mark));
    }

    /// Record an attribute and emit `SetAttribute` only when the value changes.
    fn set_attr(&mut self, key: &str, value: Option<Var>, out: &mut Vec<Action>) {
        let key = Symbol::mk(key);
        let current = self.attributes.get(&key);
        if current == value.as_ref() {
            return;
        }
        match &value {
            Some(v) => self.attributes.insert(key, v.clone()),
            None => self.attributes.remove(&key),
        };
        out.push(Action::SetAttribute { key, value });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{NOTHING, v_list, v_obj};

    fn all_on() -> ProtocolPolicy {
        ProtocolPolicy {
            offer_on_connect: true,
            gmcp: true,
            msdp: true,
            mssp: true,
            mxp: true,
            naws: true,
            ttype: true,
            eor: true,
            charset: true,
            mccp2: true,
            max_subneg: DEFAULT_MAX_SUBNEG,
            mssp_values: vec![("NAME".into(), "Test".into())],
        }
    }

    fn only(f: impl FnOnce(&mut ProtocolPolicy)) -> TelnetNegotiator {
        let mut p = ProtocolPolicy::default();
        f(&mut p);
        TelnetNegotiator::new(p)
    }

    fn neg(verb: Verb, option: u8) -> TelnetEvent {
        TelnetEvent::Negotiate { verb, option }
    }

    fn sub(option: u8, data: &[u8]) -> TelnetEvent {
        TelnetEvent::Subneg {
            option,
            data: Bytes::copy_from_slice(data),
        }
    }

    fn send(verb: Verb, option: u8) -> Action {
        Action::Send(OutFrame::Negotiate { verb, option })
    }

    fn send_sub(option: u8, payload: &[u8]) -> Action {
        Action::Send(OutFrame::Subneg {
            option,
            payload: Bytes::copy_from_slice(payload),
        })
    }

    fn attr(key: &str, value: Var) -> Action {
        Action::SetAttribute {
            key: Symbol::mk(key),
            value: Some(value),
        }
    }

    fn clear(key: &str) -> Action {
        Action::SetAttribute {
            key: Symbol::mk(key),
            value: None,
        }
    }

    fn sends(actions: &[Action]) -> Vec<OutFrame> {
        actions
            .iter()
            .filter_map(|a| match a {
                Action::Send(f) => Some(f.clone()),
                _ => None,
            })
            .collect()
    }

    fn attrs(actions: &[Action]) -> Vec<(String, Option<Var>)> {
        actions
            .iter()
            .filter_map(|a| match a {
                Action::SetAttribute { key, value } => Some((key.as_string(), value.clone())),
                _ => None,
            })
            .collect()
    }

    fn delivers(actions: &[Action]) -> Vec<(String, String, Var)> {
        actions
            .iter()
            .filter_map(|a| match a {
                Action::Deliver {
                    namespace,
                    kind,
                    payload,
                } => Some((namespace.as_string(), kind.as_string(), payload.clone())),
                _ => None,
            })
            .collect()
    }

    /// A negotiator with GMCP enabled by the client's DO.
    fn gmcp_on() -> TelnetNegotiator {
        let mut n = only(|p| p.gmcp = true);
        n.on_event(neg(Verb::Do, OPT_GMCP));
        assert!(n.is_enabled(OPT_GMCP));
        n
    }

    #[test]
    fn initial_offers_follow_policy() {
        let mut n = TelnetNegotiator::new(all_on());
        let offers = n.initial_offers();
        assert_eq!(
            offers,
            vec![
                send(Verb::Will, OPT_GMCP),
                send(Verb::Will, OPT_MSDP),
                send(Verb::Will, OPT_MSSP),
                send(Verb::Will, OPT_MXP),
                send(Verb::Will, OPT_EOR),
                send(Verb::Will, OPT_CHARSET),
                send(Verb::Will, OPT_MCCP2),
                send(Verb::Do, OPT_NAWS),
                send(Verb::Do, OPT_TTYPE),
            ]
        );
        // Offering twice sends nothing more.
        assert!(n.initial_offers().is_empty());

        let mut n = only(|p| {
            p.offer_on_connect = true;
            p.naws = true;
            p.gmcp = true;
        });
        assert_eq!(
            n.initial_offers(),
            vec![send(Verb::Will, OPT_GMCP), send(Verb::Do, OPT_NAWS)]
        );
    }

    #[test]
    fn no_offers_without_offer_on_connect() {
        let mut p = all_on();
        p.offer_on_connect = false;
        let mut n = TelnetNegotiator::new(p);
        assert!(n.initial_offers().is_empty());
        let mut n = TelnetNegotiator::new(ProtocolPolicy::default());
        assert!(n.initial_offers().is_empty());
    }

    #[test]
    fn passive_by_default() {
        let mut n = TelnetNegotiator::new(ProtocolPolicy::default());
        assert!(n.is_passive());
        assert_eq!(n.prompt_mark(), PromptMark::None);
        // No refusal on the wire, but the event still reaches MOO.
        let out = n.on_event(neg(Verb::Will, OPT_GMCP));
        assert!(sends(&out).is_empty());
        assert_eq!(delivers(&out).len(), 1);
        let out = n.on_event(neg(Verb::Do, 77));
        assert!(sends(&out).is_empty());
        // Client echo still works through the option table.
        assert_eq!(
            n.request(OPT_ECHO, Side::Us, true),
            vec![send(Verb::Will, OPT_ECHO)]
        );
    }

    #[test]
    fn naws_sets_columns_and_rows() {
        let mut n = only(|p| p.naws = true);
        assert_eq!(
            n.on_event(neg(Verb::Will, OPT_NAWS)),
            vec![send(Verb::Do, OPT_NAWS)]
        );
        let out = n.on_event(sub(OPT_NAWS, &[0, 132, 0, 50]));
        assert_eq!(
            out,
            vec![attr("columns", v_int(132)), attr("rows", v_int(50))]
        );
        // Same size again changes nothing.
        assert!(n.on_event(sub(OPT_NAWS, &[0, 132, 0, 50])).is_empty());
        let out = n.on_event(sub(OPT_NAWS, &[0, 80, 0, 50]));
        assert_eq!(out, vec![attr("columns", v_int(80))]);
        // Malformed is ignored.
        assert!(n.on_event(sub(OPT_NAWS, &[0, 80])).is_empty());
        // Disabling clears.
        let out = n.on_event(neg(Verb::Wont, OPT_NAWS));
        assert_eq!(
            out,
            vec![send(Verb::Dont, OPT_NAWS), clear("columns"), clear("rows")]
        );
    }

    #[test]
    fn naws_before_enabled_is_ignored() {
        let mut n = only(|p| p.naws = true);
        assert!(n.on_event(sub(OPT_NAWS, &[0, 80, 0, 24])).is_empty());
    }

    #[test]
    fn ttype_cycle_with_mtts() {
        let mut n = only(|p| p.ttype = true);
        let out = n.on_event(neg(Verb::Will, OPT_TTYPE));
        assert_eq!(
            out,
            vec![send(Verb::Do, OPT_TTYPE), send_sub(OPT_TTYPE, &[1])]
        );
        let out = n.on_event(sub(OPT_TTYPE, b"\x00MUDLET"));
        assert_eq!(
            out,
            vec![
                attr("terminal_type", v_str("MUDLET")),
                attr("client_name", v_str("MUDLET")),
                send_sub(OPT_TTYPE, &[1]),
            ]
        );
        let out = n.on_event(sub(OPT_TTYPE, b"\x00XTERM-256COLOR"));
        assert_eq!(out, vec![send_sub(OPT_TTYPE, &[1])]);
        // 4 (UTF-8) | 64 (screen reader) | 1 (ANSI) = 69
        let out = n.on_event(sub(OPT_TTYPE, b"\x00MTTS 69"));
        assert_eq!(
            out,
            vec![
                attr("mtts", v_int(69)),
                attr("utf8", v_bool(true)),
                attr("screen-reader", v_bool(true)),
            ]
        );
        // The cycle is over.
        assert!(n.on_event(sub(OPT_TTYPE, b"\x00MORE")).is_empty());
    }

    #[test]
    fn ttype_mtts_without_flags() {
        let mut n = only(|p| p.ttype = true);
        n.on_event(neg(Verb::Will, OPT_TTYPE));
        n.on_event(sub(OPT_TTYPE, b"\x00tintin++"));
        n.on_event(sub(OPT_TTYPE, b"\x00xterm"));
        let out = n.on_event(sub(OPT_TTYPE, b"\x00MTTS 9"));
        assert_eq!(out, vec![attr("mtts", v_int(9))]);
    }

    #[test]
    fn ttype_stops_on_repeat() {
        let mut n = only(|p| p.ttype = true);
        n.on_event(neg(Verb::Will, OPT_TTYPE));
        let out = n.on_event(sub(OPT_TTYPE, b"\x00ANSI"));
        assert_eq!(sends(&out).len(), 1);
        let out = n.on_event(sub(OPT_TTYPE, b"\x00ANSI"));
        assert!(out.is_empty());
        assert!(n.on_event(sub(OPT_TTYPE, b"\x00VT100")).is_empty());
    }

    #[test]
    fn ttype_disable_clears() {
        let mut n = only(|p| p.ttype = true);
        n.on_event(neg(Verb::Will, OPT_TTYPE));
        n.on_event(sub(OPT_TTYPE, b"\x00A"));
        let out = n.request(OPT_TTYPE, Side::Him, false);
        assert_eq!(
            out,
            vec![send(Verb::Dont, OPT_TTYPE), clear("terminal_type")]
        );
    }

    #[test]
    fn charset_accept_utf8() {
        let mut n = only(|p| p.charset = true);
        let out = n.on_event(neg(Verb::Do, OPT_CHARSET));
        assert_eq!(
            out,
            vec![
                send(Verb::Will, OPT_CHARSET),
                send_sub(OPT_CHARSET, b"\x01;UTF-8;ISO-8859-1")
            ]
        );
        let out = n.on_event(sub(OPT_CHARSET, b"\x02UTF-8"));
        assert_eq!(
            out,
            vec![attr("charset", v_str("UTF-8")), attr("utf8", v_bool(true))]
        );
        assert_eq!(n.charset(), Charset::Utf8);
    }

    #[test]
    fn charset_accept_latin1() {
        let mut n = only(|p| p.charset = true);
        n.on_event(neg(Verb::Do, OPT_CHARSET));
        let out = n.on_event(sub(OPT_CHARSET, b"\x02ISO-8859-1"));
        assert_eq!(
            out,
            vec![
                attr("charset", v_str("ISO-8859-1")),
                attr("utf8", v_bool(false)),
                Action::SetCharset(Charset::Latin1),
            ]
        );
        assert_eq!(n.charset(), Charset::Latin1);
        // Disabling returns to UTF-8.
        let out = n.on_event(neg(Verb::Dont, OPT_CHARSET));
        assert_eq!(
            out,
            vec![
                send(Verb::Wont, OPT_CHARSET),
                clear("charset"),
                Action::SetCharset(Charset::Utf8),
            ]
        );
    }

    #[test]
    fn charset_reject_keeps_default() {
        let mut n = only(|p| p.charset = true);
        n.on_event(neg(Verb::Do, OPT_CHARSET));
        assert!(n.on_event(sub(OPT_CHARSET, b"\x03")).is_empty());
        assert_eq!(n.charset(), Charset::Utf8);
        assert!(!n.attributes().contains_key(&Symbol::mk("charset")));
        // Accepting something we never offered is ignored.
        let mut n = only(|p| p.charset = true);
        n.on_event(neg(Verb::Do, OPT_CHARSET));
        assert!(n.on_event(sub(OPT_CHARSET, b"\x02KOI8-R")).is_empty());
    }

    #[test]
    fn charset_peer_request() {
        let mut n = only(|p| p.charset = true);
        n.on_event(neg(Verb::Do, OPT_CHARSET));
        // Our REQUEST is outstanding, so the peer's crossing REQUEST is rejected.
        let out = n.on_event(sub(OPT_CHARSET, b"\x01;ISO-8859-1"));
        assert_eq!(out, vec![send_sub(OPT_CHARSET, &[3])]);
        n.on_event(sub(OPT_CHARSET, b"\x03"));
        // Now a peer REQUEST is answered.
        let out = n.on_event(sub(OPT_CHARSET, b"\x01;KOI8-R;ISO-8859-1"));
        assert_eq!(
            out,
            vec![
                send_sub(OPT_CHARSET, b"\x02ISO-8859-1"),
                attr("charset", v_str("ISO-8859-1")),
                attr("utf8", v_bool(false)),
                Action::SetCharset(Charset::Latin1),
            ]
        );
        let out = n.on_event(sub(OPT_CHARSET, b"\x01;KOI8-R"));
        assert_eq!(out, vec![send_sub(OPT_CHARSET, &[3])]);
    }

    #[test]
    fn gmcp_enable_and_disable() {
        let mut n = only(|p| p.gmcp = true);
        assert!(!n.is_enabled(OPT_GMCP));
        let out = n.on_event(neg(Verb::Do, OPT_GMCP));
        assert_eq!(
            out,
            vec![send(Verb::Will, OPT_GMCP), attr("gmcp", v_bool(true))]
        );
        // A WILL GMCP as well does not report gmcp twice.
        let out = n.on_event(neg(Verb::Will, OPT_GMCP));
        assert_eq!(out, vec![send(Verb::Do, OPT_GMCP)]);
        // Disabling one side leaves it on.
        let out = n.on_event(neg(Verb::Dont, OPT_GMCP));
        assert_eq!(out, vec![send(Verb::Wont, OPT_GMCP)]);
        assert!(n.is_enabled(OPT_GMCP));
        let out = n.on_event(neg(Verb::Wont, OPT_GMCP));
        assert_eq!(
            out,
            vec![send(Verb::Dont, OPT_GMCP), attr("gmcp", v_bool(false))]
        );
    }

    #[test]
    fn gmcp_core_hello() {
        let mut n = gmcp_on();
        let out = n.on_event(sub(
            OPT_GMCP,
            br#"Core.Hello {"client":"Mudlet","version":"4.17"}"#,
        ));
        assert_eq!(
            attrs(&out),
            vec![
                ("client_name".into(), Some(v_str("Mudlet"))),
                ("client_version".into(), Some(v_str("4.17"))),
            ]
        );
        let d = delivers(&out);
        assert_eq!(d.len(), 1);
        assert_eq!((d[0].0.as_str(), d[0].1.as_str()), ("gmcp", "Core.Hello"));
    }

    #[test]
    fn gmcp_hello_wins_over_ttype_for_client_name() {
        let mut n = only(|p| {
            p.gmcp = true;
            p.ttype = true;
        });
        n.on_event(neg(Verb::Do, OPT_GMCP));
        n.on_event(neg(Verb::Will, OPT_TTYPE));
        n.on_event(sub(OPT_GMCP, br#"Core.Hello {"client":"Mudlet"}"#));
        let out = n.on_event(sub(OPT_TTYPE, b"\x00MUDLET"));
        assert_eq!(
            attrs(&out),
            vec![("terminal_type".into(), Some(v_str("MUDLET")))]
        );
    }

    #[test]
    fn gmcp_supports_set_add_remove() {
        let mut n = gmcp_on();
        let out = n.on_event(sub(OPT_GMCP, br#"Core.Supports.Set ["Char 1", "Room 1"]"#));
        let supports = v_map(&[(v_str("Char"), v_int(1)), (v_str("Room"), v_int(1))]);
        assert_eq!(attrs(&out), vec![("gmcp_supports".into(), Some(supports))]);
        assert_eq!(delivers(&out)[0].1, "Core.Supports.Set");

        let out = n.on_event(sub(OPT_GMCP, br#"Core.Supports.Add ["Comm.Channel 2"]"#));
        assert_eq!(
            attrs(&out),
            vec![(
                "gmcp_supports".into(),
                Some(v_map(&[
                    (v_str("Char"), v_int(1)),
                    (v_str("Comm.Channel"), v_int(2)),
                    (v_str("Room"), v_int(1)),
                ]))
            )]
        );
        let out = n.on_event(sub(OPT_GMCP, br#"Core.Supports.Remove ["Room"]"#));
        assert_eq!(
            attrs(&out),
            vec![(
                "gmcp_supports".into(),
                Some(v_map(&[
                    (v_str("Char"), v_int(1)),
                    (v_str("Comm.Channel"), v_int(2))
                ]))
            )]
        );
        // No change, no attribute.
        let out = n.on_event(sub(OPT_GMCP, br#"Core.Supports.Remove ["Room"]"#));
        assert!(attrs(&out).is_empty());
        assert_eq!(n.gmcp_supports().version("comm.channel"), Some(2));

        // Disabling GMCP clears gmcp_supports.
        let out = n.request(OPT_GMCP, Side::Us, false);
        assert_eq!(
            attrs(&out),
            vec![
                ("gmcp".into(), Some(v_bool(false))),
                ("gmcp_supports".into(), None)
            ]
        );
    }

    #[test]
    fn gmcp_outbound_gating() {
        let n = only(|p| p.gmcp = true);
        assert_eq!(
            n.encode_data("gmcp", "Char.Vitals", &v_map(&[])),
            Err(DataDrop::NotNegotiated)
        );
        let mut n = gmcp_on();
        let payload = v_map(&[(v_str("hp"), v_int(1))]);
        // Before Core.Supports everything goes.
        assert!(n.encode_data("gmcp", "Room.Info", &payload).is_ok());
        n.on_event(sub(OPT_GMCP, br#"Core.Supports.Set ["Char 1"]"#));
        assert_eq!(
            n.encode_data("gmcp", "Char.Vitals", &payload),
            Ok(OutFrame::Subneg {
                option: OPT_GMCP,
                payload: Bytes::from_static(br#"Char.Vitals {"hp":1}"#),
            })
        );
        assert_eq!(
            n.encode_data("gmcp", "Room.Info", &payload),
            Err(DataDrop::NotSupported)
        );
        assert_eq!(
            n.encode_data("gmcp", "Core.Ping", &v_map(&[])),
            Ok(OutFrame::Subneg {
                option: OPT_GMCP,
                payload: Bytes::from_static(b"Core.Ping")
            })
        );
        assert_eq!(
            n.encode_data("gmcp", "Char Vitals", &payload),
            Err(DataDrop::InvalidName)
        );
        assert!(matches!(
            n.encode_data("gmcp", "Char.X", &v_binary(vec![1])),
            Err(DataDrop::Unconvertible(_))
        ));
        assert_eq!(
            n.encode_data("web", "Char.X", &payload),
            Err(DataDrop::UnknownNamespace)
        );
    }

    #[test]
    fn gmcp_outbound_escapes_ff_on_wire() {
        let n = gmcp_on();
        let frame = n.encode_data("gmcp", "A.B", &v_str("ÿ")).unwrap();
        // UTF-8 "ÿ" is C3 BF, no 0xFF; a JSON body cannot contain 0xFF, so check framing only.
        assert_eq!(
            frame.to_bytes().as_ref(),
            b"\xFF\xFA\xC9A.B \"\xC3\xBF\"\xFF\xF0"
        );
    }

    #[test]
    fn gmcp_inbound_messages() {
        let mut n = gmcp_on();
        let out = n.on_event(sub(
            OPT_GMCP,
            br#"Char.Login {"name":"bob","ok":true,"x":null}"#,
        ));
        assert_eq!(
            delivers(&out),
            vec![(
                "gmcp".into(),
                "Char.Login".into(),
                v_map(&[
                    (v_str("name"), v_str("bob")),
                    (v_str("ok"), v_int(1)),
                    (v_str("x"), v_obj(NOTHING)),
                ])
            )]
        );
        n.set_boolean_returns(true);
        let out = n.on_event(sub(OPT_GMCP, b"A.B true"));
        assert_eq!(delivers(&out)[0].2, v_bool(true));
        let out = n.on_event(sub(OPT_GMCP, b"Core.Ping"));
        assert_eq!(
            delivers(&out),
            vec![("gmcp".into(), "Core.Ping".into(), v_map(&[]))]
        );
        let out = n.on_event(sub(OPT_GMCP, b"Core.Ping {}"));
        assert_eq!(delivers(&out)[0].2, v_map(&[]));
        let out = n.on_event(sub(OPT_GMCP, b"Comm.Say {not json"));
        assert_eq!(delivers(&out)[0].2, v_str("{not json"));
        assert!(n.on_event(sub(OPT_GMCP, b"bad/name 1")).is_empty());
    }

    #[test]
    fn gmcp_subneg_before_enabled_is_dropped() {
        let mut n = only(|p| p.gmcp = true);
        assert!(n.on_event(sub(OPT_GMCP, b"Core.Ping")).is_empty());
    }

    #[test]
    fn msdp_inbound_and_outbound() {
        let mut n = only(|p| p.msdp = true);
        assert_eq!(
            n.encode_data("msdp", "HEALTH", &v_int(1)),
            Err(DataDrop::NotNegotiated)
        );
        let out = n.on_event(neg(Verb::Do, OPT_MSDP));
        assert_eq!(attrs(&out), vec![("msdp".into(), Some(v_bool(true)))]);
        let out = n.on_event(sub(
            OPT_MSDP,
            b"\x01REPORT\x02HEALTH\x02MANA\x01LIST\x02COMMANDS",
        ));
        assert_eq!(
            delivers(&out),
            vec![
                (
                    "msdp".into(),
                    "REPORT".into(),
                    v_list(&[v_str("HEALTH"), v_str("MANA")])
                ),
                ("msdp".into(), "LIST".into(), v_str("COMMANDS")),
            ]
        );
        assert_eq!(
            n.encode_data("msdp", "HEALTH", &v_int(10)),
            Ok(OutFrame::Subneg {
                option: OPT_MSDP,
                payload: Bytes::from_static(b"\x01HEALTH\x0210")
            })
        );
    }

    #[test]
    fn mssp_on_do() {
        let mut n = only(|p| {
            p.mssp = true;
            p.mssp_values = vec![("NAME".into(), "Test".into())];
        });
        let out = n.on_event(neg(Verb::Do, OPT_MSSP));
        assert_eq!(out[..2], [send(Verb::Will, OPT_MSSP), Action::MsspRequest]);
        assert_eq!(
            n.mssp_response(2, 100).to_bytes().as_ref(),
            b"\xFF\xFA\x46\x01NAME\x02Test\x01PLAYERS\x022\x01UPTIME\x02100\xFF\xF0"
        );
        // The peer may only receive, so WILL MSSP is refused.
        assert_eq!(
            n.on_event(neg(Verb::Will, OPT_MSSP)),
            vec![send(Verb::Dont, OPT_MSSP)]
        );
    }

    #[test]
    fn mccp2_on_do_starts_compression() {
        let mut n = only(|p| p.mccp2 = true);
        let mut out = n.request(OPT_MCCP2, Side::Us, true);
        assert_eq!(out, vec![send(Verb::Will, OPT_MCCP2)]);
        out = n.on_event(neg(Verb::Do, OPT_MCCP2));
        assert_eq!(
            out[..2],
            [Action::StartCompress, attr("mccp2", v_bool(true))]
        );
        out = n.on_event(neg(Verb::Dont, OPT_MCCP2));
        assert_eq!(
            out[..3],
            [
                send(Verb::Wont, OPT_MCCP2),
                Action::StopCompress,
                attr("mccp2", v_bool(false))
            ]
        );
        // Not configured: refused, no compression.
        let mut n = only(|p| p.gmcp = true);
        assert_eq!(n.on_event(neg(Verb::Do, OPT_MCCP2)), {
            let mut v = vec![send(Verb::Wont, OPT_MCCP2)];
            v.extend(delivers_negotiate(OPT_MCCP2, "do"));
            v
        });
    }

    fn delivers_negotiate(option: u8, verb: &str) -> Vec<Action> {
        vec![Action::Deliver {
            namespace: Symbol::mk("telnet"),
            kind: Symbol::mk("negotiate"),
            payload: v_map(&[
                (v_str("option"), v_int(option as i64)),
                (v_str("verb"), v_sym(verb)),
            ]),
        }]
    }

    #[test]
    fn mxp_enable_locks_by_default() {
        let mut n = only(|p| p.mxp = true);
        let out = n.on_event(neg(Verb::Do, OPT_MXP));
        assert_eq!(
            out[..4],
            [
                send(Verb::Will, OPT_MXP),
                attr("mxp", v_bool(true)),
                send_sub(OPT_MXP, b""),
                Action::Send(OutFrame::Raw(Bytes::from_static(b"\x1b[7z"))),
            ]
        );
    }

    #[test]
    fn eor_changes_prompt_mark() {
        let mut n = only(|p| p.eor = true);
        assert_eq!(n.prompt_mark(), PromptMark::Ga);
        let out = n.on_event(neg(Verb::Do, OPT_EOR));
        assert_eq!(
            out,
            vec![
                send(Verb::Will, OPT_EOR),
                attr("eor", v_bool(true)),
                Action::SetPromptMark(PromptMark::Eor),
            ]
        );
        let out = n.on_event(neg(Verb::Do, OPT_SGA));
        assert_eq!(out, vec![send(Verb::Will, OPT_SGA)]);
        assert_eq!(n.prompt_mark(), PromptMark::Eor);
        let out = n.on_event(neg(Verb::Dont, OPT_EOR));
        assert_eq!(
            out,
            vec![
                send(Verb::Wont, OPT_EOR),
                attr("eor", v_bool(false)),
                Action::SetPromptMark(PromptMark::None),
            ]
        );
        let out = n.on_event(neg(Verb::Dont, OPT_SGA));
        assert_eq!(
            out,
            vec![
                send(Verb::Wont, OPT_SGA),
                Action::SetPromptMark(PromptMark::Ga)
            ]
        );
    }

    #[test]
    fn sga_us_updates_prompt_mark_when_him_already_on() {
        let mut n = only(|p| p.gmcp = true);
        assert_eq!(n.prompt_mark(), PromptMark::Ga);
        assert_eq!(
            n.on_event(neg(Verb::Will, OPT_SGA)),
            vec![send(Verb::Do, OPT_SGA)]
        );
        assert_eq!(n.prompt_mark(), PromptMark::Ga);
        let out = n.on_event(neg(Verb::Do, OPT_SGA));
        assert_eq!(
            out,
            vec![
                send(Verb::Will, OPT_SGA),
                Action::SetPromptMark(PromptMark::None)
            ]
        );
    }

    #[test]
    fn unknown_option_negotiate_is_refused_and_delivered() {
        let mut n = only(|p| p.gmcp = true);
        let out = n.on_event(neg(Verb::Will, 77));
        let mut expect = vec![send(Verb::Dont, 77)];
        expect.extend(delivers_negotiate(77, "will"));
        assert_eq!(out, expect);
        let out = n.on_event(neg(Verb::Do, 77));
        let mut expect = vec![send(Verb::Wont, 77)];
        expect.extend(delivers_negotiate(77, "do"));
        assert_eq!(out, expect);
        // WONT/DONT for an option already off: delivered, not answered.
        assert_eq!(
            n.on_event(neg(Verb::Wont, 77)),
            delivers_negotiate(77, "wont")
        );
        assert_eq!(
            n.on_event(neg(Verb::Dont, 77)),
            delivers_negotiate(77, "dont")
        );
        // A configured-off protocol is refused the same way.
        let out = n.on_event(neg(Verb::Will, OPT_NAWS));
        assert_eq!(out[0], send(Verb::Dont, OPT_NAWS));
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn unknown_option_subneg_is_delivered_unescaped() {
        let mut n = only(|p| p.gmcp = true);
        let out = n.on_event(sub(77, &[1, 0xFF, 2]));
        assert_eq!(
            out,
            vec![Action::Deliver {
                namespace: Symbol::mk("telnet"),
                kind: Symbol::mk("subneg"),
                payload: v_map(&[
                    (v_str("option"), v_int(77)),
                    (v_str("data"), v_binary(vec![1, 0xFF, 2])),
                ]),
            }]
        );
    }

    #[test]
    fn known_commands_are_ignored() {
        let mut n = TelnetNegotiator::new(all_on());
        assert!(n.on_event(TelnetEvent::Command(NOP)).is_empty());
    }

    #[test]
    fn requests_send_one_verb_and_are_idempotent() {
        let mut n = TelnetNegotiator::new(all_on());
        for (option, side, on, off) in [
            (OPT_GMCP, Side::Us, Verb::Will, Verb::Wont),
            (OPT_NAWS, Side::Him, Verb::Do, Verb::Dont),
            (OPT_ECHO, Side::Us, Verb::Will, Verb::Wont),
        ] {
            assert_eq!(n.request(option, side, true), vec![send(on, option)]);
            assert!(n.request(option, side, true).is_empty());
            // Peer agrees.
            let peer = if side == Side::Us {
                Verb::Do
            } else {
                Verb::Will
            };
            assert!(sends(&n.on_event(neg(peer, option))).is_empty());
            assert!(n.request(option, side, true).is_empty());
            assert_eq!(
                sends(&n.request(option, side, false)),
                vec![OutFrame::Negotiate { verb: off, option }]
            );
            assert!(n.request(option, side, false).is_empty());
            let peer_off = if side == Side::Us {
                Verb::Dont
            } else {
                Verb::Wont
            };
            assert!(sends(&n.on_event(neg(peer_off, option))).is_empty());
            assert!(n.request(option, side, false).is_empty());
        }
        // A request for an option the policy forbids does nothing.
        let mut n = only(|p| p.gmcp = true);
        assert!(n.request(OPT_MSDP, Side::Us, true).is_empty());
        assert!(n.request(77, Side::Him, true).is_empty());
    }

    #[test]
    fn client_echo_round_trip() {
        // `client-echo 0` asks the server to echo: WILL ECHO.
        let mut n = TelnetNegotiator::new(ProtocolPolicy::default());
        assert_eq!(
            n.request(OPT_ECHO, Side::Us, true),
            vec![send(Verb::Will, OPT_ECHO)]
        );
        assert!(n.on_event(neg(Verb::Do, OPT_ECHO)).is_empty());
        assert_eq!(n.state(OPT_ECHO, Side::Us), QState::Yes);
        // `client-echo 1`: WONT ECHO, once.
        assert_eq!(
            n.request(OPT_ECHO, Side::Us, false),
            vec![send(Verb::Wont, OPT_ECHO)]
        );
        assert!(n.request(OPT_ECHO, Side::Us, false).is_empty());
        assert!(n.on_event(neg(Verb::Dont, OPT_ECHO)).is_empty());
        // An unsolicited DO ECHO is not accepted while active.
        let mut n = TelnetNegotiator::new(all_on());
        assert_eq!(
            n.on_event(neg(Verb::Do, OPT_ECHO)),
            vec![send(Verb::Wont, OPT_ECHO)]
        );
    }

    /// Two negotiators wired back to back reach a fixed point.
    #[test]
    fn back_to_back_negotiators_converge() {
        let mut a = TelnetNegotiator::new(all_on());
        let mut b = TelnetNegotiator::new(all_on());
        let mut queue: std::collections::VecDeque<(bool, TelnetEvent)> = Default::default();
        let push = |queue: &mut std::collections::VecDeque<(bool, TelnetEvent)>,
                    to_b: bool,
                    actions: Vec<Action>| {
            for action in actions {
                let Action::Send(OutFrame::Negotiate { verb, option }) = action else {
                    continue;
                };
                queue.push_back((to_b, neg(verb, option)));
            }
        };
        let offers_a = a.initial_offers();
        let offers_b = b.initial_offers();
        push(&mut queue, true, offers_a);
        push(&mut queue, false, offers_b);
        let mut steps = 0;
        while let Some((to_b, event)) = queue.pop_front() {
            steps += 1;
            assert!(steps < 500, "no fixed point");
            let out = if to_b {
                b.on_event(event)
            } else {
                a.on_event(event)
            };
            push(&mut queue, !to_b, out);
        }
        // Options both ends accept on both sides end up on.
        for option in [OPT_GMCP, OPT_MSDP, OPT_CHARSET] {
            for n in [&a, &b] {
                assert_eq!(n.state(option, Side::Us), QState::Yes, "{option}");
                assert_eq!(n.state(option, Side::Him), QState::Yes, "{option}");
            }
        }
        // Options a server only performs, or only asks of a client, end up off between two
        // servers: each refuses the other's offer.
        for option in [OPT_EOR, OPT_MCCP2, OPT_MSSP, OPT_MXP, OPT_NAWS, OPT_TTYPE] {
            for n in [&a, &b] {
                assert!(!n.is_enabled(option), "{option}");
            }
        }
        // And nothing more is pending.
        for opt in 0..=255u8 {
            for side in [Side::Us, Side::Him] {
                for n in [&a, &b] {
                    assert!(matches!(n.state(opt, side), QState::Yes | QState::No));
                }
            }
        }
    }
}
