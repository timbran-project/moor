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

//! Decoded telnet protocol events, as produced by the connection codec.

use bytes::{BufMut, Bytes, BytesMut};

use super::consts::{DO, DONT, IAC, SB, SE, WILL, WONT};

/// The four option negotiation verbs.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Verb {
    Will,
    Wont,
    Do,
    Dont,
}

impl Verb {
    /// The command byte for this verb.
    pub fn byte(self) -> u8 {
        match self {
            Verb::Will => WILL,
            Verb::Wont => WONT,
            Verb::Do => DO,
            Verb::Dont => DONT,
        }
    }

    pub fn from_byte(b: u8) -> Option<Self> {
        match b {
            WILL => Some(Verb::Will),
            WONT => Some(Verb::Wont),
            DO => Some(Verb::Do),
            DONT => Some(Verb::Dont),
            _ => None,
        }
    }

    /// Lower-case name, used as the `verb` symbol delivered to MOO code.
    pub fn name(self) -> &'static str {
        match self {
            Verb::Will => "will",
            Verb::Wont => "wont",
            Verb::Do => "do",
            Verb::Dont => "dont",
        }
    }

    /// The wire form `IAC <verb> <option>`.
    pub fn frame(self, option: u8) -> [u8; 3] {
        [IAC, self.byte(), option]
    }
}

/// One telnet protocol element received from the peer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TelnetEvent {
    /// A two-byte command, `IAC <cmd>` (NOP, GA, AYT, ...).
    Command(u8),
    /// `IAC WILL|WONT|DO|DONT <option>`.
    Negotiate { verb: Verb, option: u8 },
    /// `IAC SB <option> <data> IAC SE`, with `IAC IAC` in the data unescaped.
    Subneg { option: u8, data: Bytes },
}

impl TelnetEvent {
    /// Re-encode the event in wire form, escaping 0xFF in subnegotiation data.
    pub fn to_raw(&self) -> Bytes {
        match self {
            TelnetEvent::Command(c) => Bytes::copy_from_slice(&[IAC, *c]),
            TelnetEvent::Negotiate { verb, option } => Bytes::copy_from_slice(&verb.frame(*option)),
            TelnetEvent::Subneg { option, data } => {
                let mut out = BytesMut::with_capacity(data.len() + 5);
                write_subneg(*option, data, &mut out);
                out.freeze()
            }
        }
    }
}

/// Append `data` to `out`, doubling every 0xFF byte.
pub fn escape_iac(data: &[u8], out: &mut BytesMut) {
    let mut rest = data;
    while let Some(pos) = rest.iter().position(|&b| b == IAC) {
        out.put_slice(&rest[..=pos]);
        out.put_u8(IAC);
        rest = &rest[pos + 1..];
    }
    out.put_slice(rest);
}

/// Append `IAC SB <option> <escaped data> IAC SE` to `out`.
pub fn write_subneg(option: u8, data: &[u8], out: &mut BytesMut) {
    out.reserve(data.len() + 5);
    out.put_slice(&[IAC, SB, option]);
    escape_iac(data, out);
    out.put_slice(&[IAC, SE]);
}
