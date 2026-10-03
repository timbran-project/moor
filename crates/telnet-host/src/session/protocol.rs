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

//! Turning negotiator [`Action`]s and outbound data events into codec frames and daemon
//! requests, without I/O. The session writes the frames in order and sends the requests.

use std::{collections::HashMap, time::Instant};

use moor_runtime_api::{AuthToken, ClientToken, api::ClientRequest};
use moor_var::{NOTHING, Obj, Symbol, Var, v_map, v_obj, v_sym};
use tracing::{trace, warn};

use super::{
    codec::ConnectionFrame,
    telnet::{Action, OutFrame, TelnetNegotiator, negotiator::DataDrop},
};

/// Token bucket for inbound `ClientData`: `rate` per second, bursts of twice that.
#[derive(Debug)]
pub(crate) struct ClientDataLimiter {
    rate: f64,
    burst: f64,
    tokens: f64,
    last: Instant,
}

impl ClientDataLimiter {
    /// `rate` messages per second; 0 disables the limit.
    pub(crate) fn new(rate: u32, now: Instant) -> Self {
        let rate = f64::from(rate);
        Self {
            rate,
            burst: rate * 2.0,
            tokens: rate * 2.0,
            last: now,
        }
    }

    /// Take one token if available.
    pub(crate) fn allow(&mut self, now: Instant) -> bool {
        if self.rate == 0.0 {
            return true;
        }
        let elapsed = now.saturating_duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * self.rate).min(self.burst);
        if self.tokens < 1.0 {
            return false;
        }
        self.tokens -= 1.0;
        true
    }
}

/// What the session knows when applying actions.
pub(crate) struct PlanContext<'a> {
    pub(crate) client_token: &'a ClientToken,
    /// Present once logged in.
    pub(crate) auth_token: Option<&'a AuthToken>,
    pub(crate) handler_object: Obj,
    /// No protocol is configured: nothing goes to the daemon as `ClientData`.
    pub(crate) passive: bool,
    /// `disable-oob` is set: `ClientData('telnet, ...)` is not sent.
    pub(crate) disable_oob: bool,
    /// MSSP `PLAYERS`.
    pub(crate) players: u64,
    /// MSSP `UPTIME`: host start time, Unix seconds.
    pub(crate) uptime: u64,
    pub(crate) now: Instant,
}

/// The result of applying one negotiation step.
#[derive(Debug, Default)]
pub(crate) struct Plan {
    /// Frames to write, in order.
    pub(crate) frames: Vec<ConnectionFrame>,
    /// Requests to send to the daemon, in order.
    pub(crate) requests: Vec<ClientRequest>,
    /// Attributes that changed, as recorded in the local map.
    pub(crate) changed: Vec<(Symbol, Option<Var>)>,
}

/// Apply one step's actions: record attributes in `attributes`, and produce the frames and
/// requests. Attribute changes become one `SetClientAttribute` each, then a single
/// `ClientData('client, 'attributes, [key -> value])`; a removed key maps to `#-1`.
pub(crate) fn plan_actions(
    actions: Vec<Action>,
    negotiator: &TelnetNegotiator,
    ctx: &PlanContext<'_>,
    attributes: &mut HashMap<Symbol, Var>,
    limiter: &mut ClientDataLimiter,
) -> Plan {
    let mut plan = Plan::default();
    for action in actions {
        match action {
            Action::Send(frame) => plan.frames.push(out_frame(frame)),
            Action::StartCompress => plan.frames.push(ConnectionFrame::StartCompress),
            Action::StopCompress => plan.frames.push(ConnectionFrame::StopCompress),
            Action::SetCharset(cs) => plan.frames.push(ConnectionFrame::SetCharset(cs)),
            Action::SetPromptMark(mark) => plan.frames.push(ConnectionFrame::SetPromptMark(mark)),
            Action::MsspRequest => plan
                .frames
                .push(out_frame(negotiator.mssp_response(ctx.players, ctx.uptime))),
            Action::SetAttribute { key, value } => {
                match &value {
                    Some(v) => attributes.insert(key, v.clone()),
                    None => attributes.remove(&key),
                };
                plan.requests.push(ClientRequest::SetClientAttribute {
                    client_token: ctx.client_token.clone(),
                    auth_token: ctx.auth_token.cloned(),
                    key,
                    value: value.clone(),
                });
                plan.changed.push((key, value));
            }
            Action::Deliver {
                namespace,
                kind,
                payload,
            } => {
                if ctx.passive || (ctx.disable_oob && namespace.as_arc_str().as_str() == "telnet") {
                    continue;
                }
                push_client_data(&mut plan, ctx, limiter, namespace, kind, payload);
            }
        }
    }
    if plan.changed.is_empty() || ctx.passive {
        return plan;
    }
    let pairs: Vec<(Var, Var)> = plan
        .changed
        .iter()
        .map(|(k, v)| (v_sym(*k), v.clone().unwrap_or_else(|| v_obj(NOTHING))))
        .collect();
    push_client_data(
        &mut plan,
        ctx,
        limiter,
        Symbol::mk("client"),
        Symbol::mk("attributes"),
        v_map(&pairs),
    );
    plan
}

fn push_client_data(
    plan: &mut Plan,
    ctx: &PlanContext<'_>,
    limiter: &mut ClientDataLimiter,
    namespace: Symbol,
    kind: Symbol,
    payload: Var,
) {
    if !limiter.allow(ctx.now) {
        warn!(%namespace, %kind, "inbound client data over the rate limit; dropped");
        return;
    }
    plan.requests.push(ClientRequest::ClientData {
        client_token: ctx.client_token.clone(),
        auth_token: ctx.auth_token.cloned(),
        handler_object: ctx.handler_object,
        namespace,
        kind,
        payload,
    });
}

/// The codec frame for a negotiator frame.
pub(crate) fn out_frame(frame: OutFrame) -> ConnectionFrame {
    match frame {
        OutFrame::Subneg { option, payload } => ConnectionFrame::Subneg { option, payload },
        OutFrame::Negotiate { .. } | OutFrame::Raw(_) => ConnectionFrame::Telnet(frame.to_bytes()),
    }
}

/// The frame for an outbound `Event::Data`, or `None` when this connection does not take it.
/// Drops are logged and never fatal.
pub(crate) fn data_frame(
    negotiator: &TelnetNegotiator,
    namespace: &str,
    kind: &str,
    payload: &Var,
) -> Option<ConnectionFrame> {
    match negotiator.encode_data(namespace, kind, payload) {
        Ok(frame) => Some(out_frame(frame)),
        Err(DataDrop::UnknownNamespace | DataDrop::NotNegotiated | DataDrop::NotSupported) => {
            trace!(namespace, kind, "data event not sent");
            None
        }
        Err(DataDrop::InvalidName) => {
            warn!(namespace, kind, "data event with an invalid name dropped");
            None
        }
        Err(DataDrop::Unconvertible(reason)) => {
            warn!(
                namespace,
                kind, reason, "data event payload not convertible; dropped"
            );
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::telnet::{
        ProtocolPolicy, TelnetEvent, Verb,
        consts::{OPT_ECHO, OPT_GMCP, OPT_NAWS},
    };
    use bytes::Bytes;
    use moor_var::{v_bool, v_int, v_str};
    use std::time::Duration;

    fn token() -> ClientToken {
        ClientToken("client".to_string())
    }

    fn auth() -> AuthToken {
        AuthToken("auth".to_string())
    }

    fn ctx<'a>(
        client_token: &'a ClientToken,
        auth_token: Option<&'a AuthToken>,
        passive: bool,
    ) -> PlanContext<'a> {
        PlanContext {
            client_token,
            auth_token,
            handler_object: Obj::mk_id(7),
            passive,
            disable_oob: false,
            players: 3,
            uptime: 1_700_000_000,
            now: Instant::now(),
        }
    }

    fn policy() -> ProtocolPolicy {
        ProtocolPolicy {
            gmcp: true,
            naws: true,
            ..ProtocolPolicy::default()
        }
    }

    fn unlimited() -> ClientDataLimiter {
        ClientDataLimiter::new(0, Instant::now())
    }

    fn client_data(r: &ClientRequest) -> Option<(&Option<AuthToken>, Obj, String, String, &Var)> {
        let ClientRequest::ClientData {
            auth_token,
            handler_object,
            namespace,
            kind,
            payload,
            ..
        } = r
        else {
            return None;
        };
        Some((
            auth_token,
            *handler_object,
            namespace.as_arc_str().to_string(),
            kind.as_arc_str().to_string(),
            payload,
        ))
    }

    #[test]
    fn attribute_changes_coalesce_into_one_client_data() {
        let mut n = TelnetNegotiator::new(policy());
        let ct = token();
        let c = ctx(&ct, None, false);
        let mut attrs = HashMap::new();
        let mut limiter = unlimited();
        let actions = n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Will,
            option: OPT_NAWS,
        });
        let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
        // DO NAWS acknowledging, no attribute yet.
        assert_eq!(plan.frames.len(), 1);
        assert!(plan.requests.is_empty());

        let actions = n.on_event(TelnetEvent::Subneg {
            option: OPT_NAWS,
            data: Bytes::from_static(&[0, 120, 0, 40]),
        });
        let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
        assert!(plan.frames.is_empty());
        assert_eq!(attrs.get(&Symbol::mk("columns")), Some(&v_int(120)));
        assert_eq!(attrs.get(&Symbol::mk("rows")), Some(&v_int(40)));
        assert_eq!(plan.requests.len(), 3);
        for r in &plan.requests[..2] {
            let ClientRequest::SetClientAttribute { auth_token, .. } = r else {
                panic!("expected SetClientAttribute, got {r:?}");
            };
            assert!(auth_token.is_none());
        }
        let (auth, _, ns, kind, payload) = client_data(&plan.requests[2]).unwrap();
        assert!(auth.is_none());
        assert_eq!((ns.as_str(), kind.as_str()), ("client", "attributes"));
        assert_eq!(
            payload,
            &v_map(&[(v_sym("columns"), v_int(120)), (v_sym("rows"), v_int(40))])
        );
    }

    #[test]
    fn removed_attribute_maps_to_nothing() {
        let mut n = TelnetNegotiator::new(policy());
        let ct = token();
        let c = ctx(&ct, None, false);
        let mut attrs = HashMap::new();
        let mut limiter = unlimited();
        for event in [
            TelnetEvent::Negotiate {
                verb: Verb::Will,
                option: OPT_NAWS,
            },
            TelnetEvent::Subneg {
                option: OPT_NAWS,
                data: Bytes::from_static(&[0, 80, 0, 24]),
            },
        ] {
            let actions = n.on_event(event);
            plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
        }
        let actions = n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Wont,
            option: OPT_NAWS,
        });
        let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
        assert!(!attrs.contains_key(&Symbol::mk("columns")));
        let (_, _, _, _, payload) = client_data(plan.requests.last().unwrap()).unwrap();
        assert_eq!(
            payload,
            &v_map(&[
                (v_sym("columns"), v_obj(NOTHING)),
                (v_sym("rows"), v_obj(NOTHING))
            ])
        );
    }

    #[test]
    fn deliver_carries_auth_only_after_login() {
        let mut n = TelnetNegotiator::new(policy());
        let ct = token();
        let at = auth();
        let mut attrs = HashMap::new();
        let mut limiter = unlimited();
        let enable = n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Do,
            option: OPT_GMCP,
        });
        plan_actions(enable, &n, &ctx(&ct, None, false), &mut attrs, &mut limiter);
        let ping = || TelnetEvent::Subneg {
            option: OPT_GMCP,
            data: Bytes::from_static(b"Core.Ping"),
        };

        let actions = n.on_event(ping());
        let plan = plan_actions(
            actions,
            &n,
            &ctx(&ct, None, false),
            &mut attrs,
            &mut limiter,
        );
        let (auth_token, handler, ns, kind, payload) = client_data(&plan.requests[0]).unwrap();
        assert!(auth_token.is_none());
        assert_eq!(handler, Obj::mk_id(7));
        assert_eq!((ns.as_str(), kind.as_str()), ("gmcp", "Core.Ping"));
        assert_eq!(payload, &v_map(&[]));

        let actions = n.on_event(ping());
        let plan = plan_actions(
            actions,
            &n,
            &ctx(&ct, Some(&at), false),
            &mut attrs,
            &mut limiter,
        );
        let (auth_token, ..) = client_data(&plan.requests[0]).unwrap();
        assert_eq!(auth_token.as_ref(), Some(&at));
    }

    #[test]
    fn passive_sends_no_client_data() {
        let mut n = TelnetNegotiator::new(ProtocolPolicy::default());
        let ct = token();
        let at = auth();
        let c = ctx(&ct, Some(&at), true);
        let mut attrs = HashMap::new();
        let mut limiter = unlimited();
        for event in [
            TelnetEvent::Negotiate {
                verb: Verb::Will,
                option: OPT_NAWS,
            },
            TelnetEvent::Subneg {
                option: 77,
                data: Bytes::from_static(b"x"),
            },
            TelnetEvent::Negotiate {
                verb: Verb::Do,
                option: OPT_ECHO,
            },
        ] {
            let actions = n.on_event(event);
            let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
            assert!(plan.frames.is_empty(), "{:?}", plan.frames);
            assert!(plan.requests.is_empty(), "{:?}", plan.requests);
        }
    }

    #[test]
    fn disable_oob_drops_telnet_namespace_only() {
        let mut n = TelnetNegotiator::new(policy());
        let ct = token();
        let mut c = ctx(&ct, None, false);
        c.disable_oob = true;
        let mut attrs = HashMap::new();
        let mut limiter = unlimited();
        let actions = n.on_event(TelnetEvent::Subneg {
            option: 77,
            data: Bytes::from_static(b"x"),
        });
        let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
        assert!(plan.requests.is_empty());
    }

    #[test]
    fn mssp_request_answers_with_players_and_uptime() {
        let mut n = TelnetNegotiator::new(ProtocolPolicy {
            mssp: true,
            mssp_values: vec![("NAME".to_string(), "Test".to_string())],
            ..ProtocolPolicy::default()
        });
        let ct = token();
        let c = ctx(&ct, None, false);
        let actions = n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Do,
            option: 70,
        });
        let plan = plan_actions(actions, &n, &c, &mut HashMap::new(), &mut unlimited());
        let Some(ConnectionFrame::Subneg { option, payload }) = plan.frames.last() else {
            panic!("expected an MSSP subneg, got {:?}", plan.frames);
        };
        assert_eq!(*option, 70);
        assert_eq!(
            payload.as_ref(),
            b"\x01NAME\x02Test\x01PLAYERS\x023\x01UPTIME\x021700000000"
        );
    }

    #[test]
    fn rate_limiter_bursts_then_refills() {
        let start = Instant::now();
        let mut l = ClientDataLimiter::new(50, start);
        let allowed = (0..150).filter(|_| l.allow(start)).count();
        assert_eq!(allowed, 100);
        assert!(!l.allow(start));
        // 100 ms refills five tokens.
        let later = start + Duration::from_millis(100);
        let allowed = (0..10).filter(|_| l.allow(later)).count();
        assert_eq!(allowed, 5);
        // The bucket never holds more than the burst.
        let much_later = start + Duration::from_secs(60);
        let allowed = (0..150).filter(|_| l.allow(much_later)).count();
        assert_eq!(allowed, 100);
    }

    #[test]
    fn rate_limit_applies_to_deliveries() {
        let mut n = TelnetNegotiator::new(policy());
        let ct = token();
        let c = ctx(&ct, None, false);
        let mut attrs = HashMap::new();
        let mut limiter = ClientDataLimiter::new(1, c.now);
        let enable = n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Do,
            option: OPT_GMCP,
        });
        // Enabling GMCP sets `gmcp`: one ClientData('client, 'attributes) takes a token.
        let plan = plan_actions(enable, &n, &c, &mut attrs, &mut limiter);
        assert_eq!(plan.requests.len(), 2);
        assert_eq!(attrs.get(&Symbol::mk("gmcp")), Some(&v_bool(true)));
        let mut delivered = 0;
        for _ in 0..5 {
            let actions = n.on_event(TelnetEvent::Subneg {
                option: OPT_GMCP,
                data: Bytes::from_static(b"Char.Login {\"name\":\"x\"}"),
            });
            let plan = plan_actions(actions, &n, &c, &mut attrs, &mut limiter);
            delivered += plan.requests.len();
        }
        assert_eq!(delivered, 1);
    }

    #[test]
    fn data_frame_gates_and_encodes() {
        let mut n = TelnetNegotiator::new(policy());
        let payload = v_map(&[(v_str("hp"), v_int(1))]);
        assert!(data_frame(&n, "gmcp", "Char.Vitals", &payload).is_none());
        n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Do,
            option: OPT_GMCP,
        });
        let Some(ConnectionFrame::Subneg { option, payload }) =
            data_frame(&n, "gmcp", "Char.Vitals", &payload)
        else {
            panic!("expected a GMCP frame");
        };
        assert_eq!(option, OPT_GMCP);
        assert_eq!(payload.as_ref(), br#"Char.Vitals {"hp":1}"#);
        assert!(data_frame(&n, "gmcp", "bad name", &v_map(&[])).is_none());
        assert!(data_frame(&n, "other", "x", &v_map(&[])).is_none());
    }
}
