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

//! TTYPE (Terminal Type, RFC 1091, option 24) cycling and MTTS
//! (<https://tintin.mudhalla.net/protocols/mtts/>).
//!
//! We ask up to three times. By convention the first reply is the client name, the second a
//! terminal type, and the third `MTTS <bitvector>`. A reply equal to the previous one means the
//! client has no more names, and we stop.

pub const IS: u8 = 0;
pub const SEND: u8 = 1;

/// The body of `SEND`.
pub const SEND_BODY: [u8; 1] = [SEND];

/// Most replies we ask for.
pub const MAX_REPLIES: usize = 3;

pub const MTTS_UTF8: i64 = 4;
pub const MTTS_SCREEN_READER: i64 = 64;

/// Progress of the TTYPE cycle.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TtypeCycle {
    replies: Vec<String>,
    done: bool,
}

/// What one reply tells us.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TtypeReply {
    /// The first reply: terminal type and client name.
    pub first: Option<String>,
    /// An `MTTS n` reply.
    pub mtts: Option<i64>,
    /// Whether to send another `SEND`.
    pub send_again: bool,
}

impl TtypeCycle {
    pub fn is_done(&self) -> bool {
        self.done
    }

    pub fn replies(&self) -> &[String] {
        &self.replies
    }

    /// Restart, e.g. after the peer re-enables TTYPE.
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Handle a subnegotiation body. Anything but `IS <name>` is ignored.
    pub fn on_subneg(&mut self, data: &[u8]) -> TtypeReply {
        let Some((&IS, name)) = data.split_first() else {
            return TtypeReply::default();
        };
        if self.done {
            return TtypeReply::default();
        }
        let name = String::from_utf8_lossy(name).trim().to_string();
        if self.replies.last() == Some(&name) {
            self.done = true;
            return TtypeReply::default();
        }
        let mut reply = TtypeReply {
            mtts: parse_mtts(&name),
            ..Default::default()
        };
        if self.replies.is_empty() {
            reply.first = Some(name.clone());
        }
        self.replies.push(name);
        self.done = self.replies.len() >= MAX_REPLIES;
        reply.send_again = !self.done;
        reply
    }
}

/// `MTTS 137` -> 137.
pub fn parse_mtts(name: &str) -> Option<i64> {
    let rest = name
        .strip_prefix("MTTS ")
        .or_else(|| name.strip_prefix("mtts "))?;
    rest.trim().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn three_replies() {
        let mut c = TtypeCycle::default();
        let r = c.on_subneg(b"\x00MUDLET");
        assert_eq!(r.first.as_deref(), Some("MUDLET"));
        assert!(r.send_again);
        let r = c.on_subneg(b"\x00ANSI-TRUECOLOR");
        assert_eq!(r.first, None);
        assert!(r.send_again);
        let r = c.on_subneg(b"\x00MTTS 2349");
        assert_eq!(r.mtts, Some(2349));
        assert!(!r.send_again);
        assert!(c.is_done());
        assert_eq!(c.on_subneg(b"\x00MORE"), TtypeReply::default());
    }

    #[test]
    fn stops_on_repeat() {
        let mut c = TtypeCycle::default();
        assert!(c.on_subneg(b"\x00xterm").send_again);
        let r = c.on_subneg(b"\x00xterm");
        assert_eq!(r, TtypeReply::default());
        assert!(c.is_done());
        assert_eq!(c.replies(), ["xterm".to_string()]);
    }

    #[test]
    fn ignores_non_is() {
        let mut c = TtypeCycle::default();
        assert_eq!(c.on_subneg(b"\x01"), TtypeReply::default());
        assert_eq!(c.on_subneg(b""), TtypeReply::default());
        assert!(!c.is_done());
    }

    #[test]
    fn mtts() {
        assert_eq!(parse_mtts("MTTS 68"), Some(68));
        assert_eq!(parse_mtts("MTTS x"), None);
        assert_eq!(parse_mtts("XTERM"), None);
    }
}
