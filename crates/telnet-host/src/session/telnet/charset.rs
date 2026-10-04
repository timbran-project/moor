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

//! Character sets the codec can speak, and CHARSET (RFC 2066) subnegotiation.

use bytes::{BufMut, BytesMut};

use super::consts::IAC;

/// The character set of a connection's text.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Default)]
pub enum Charset {
    /// UTF-8; invalid input is replaced with U+FFFD.
    #[default]
    Utf8,
    /// ISO-8859-1; characters above U+00FF are written as `?`.
    Latin1,
}

impl Charset {
    /// The name used on the wire and in the `charset` attribute.
    pub fn name(self) -> &'static str {
        match self {
            Charset::Utf8 => "UTF-8",
            Charset::Latin1 => "ISO-8859-1",
        }
    }

    /// Look up a charset name as a client might spell it.
    pub fn from_name(name: &str) -> Option<Self> {
        let n = name.trim().to_ascii_uppercase().replace('_', "-");
        match n.as_str() {
            "UTF-8" | "UTF8" => Some(Charset::Utf8),
            "ISO-8859-1" | "ISO8859-1" | "LATIN1" | "LATIN-1" | "ISO-LATIN-1" | "L1" => {
                Some(Charset::Latin1)
            }
            _ => None,
        }
    }

    /// Decode received text bytes into a string.
    pub fn decode(self, bytes: &[u8]) -> String {
        match self {
            Charset::Utf8 => String::from_utf8_lossy(bytes).into_owned(),
            Charset::Latin1 => bytes.iter().map(|&b| char::from(b)).collect(),
        }
    }

    /// Encode text for the wire, writing a 0xFF byte as `IAC IAC`.
    pub fn encode_into(self, text: &str, out: &mut BytesMut) {
        match self {
            // UTF-8 never produces 0xFF.
            Charset::Utf8 => out.put_slice(text.as_bytes()),
            Charset::Latin1 => {
                out.reserve(text.len());
                for c in text.chars() {
                    let b = u8::try_from(u32::from(c)).unwrap_or(b'?');
                    out.put_u8(b);
                    if b == IAC {
                        out.put_u8(IAC);
                    }
                }
            }
        }
    }
}

/// CHARSET subnegotiation codes (RFC 2066).
pub const REQUEST: u8 = 1;
pub const ACCEPTED: u8 = 2;
pub const REJECTED: u8 = 3;

/// The charsets we ask for, in order of preference.
pub const OFFERED: [Charset; 2] = [Charset::Utf8, Charset::Latin1];

/// Body of our `REQUEST`: `REQUEST ;UTF-8;ISO-8859-1`.
pub fn request_body() -> Vec<u8> {
    let mut body = vec![REQUEST];
    for c in OFFERED {
        body.push(b';');
        body.extend_from_slice(c.name().as_bytes());
    }
    body
}

/// A CHARSET subnegotiation received from the peer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CharsetMessage {
    /// The peer accepted one charset from our request. `None` when it is one we do not speak.
    Accepted(Option<Charset>, String),
    /// The peer rejected our request.
    Rejected,
    /// The peer asks us to pick from its list. Holds the first we speak, if any.
    Request(Option<Charset>),
    /// TTABLE messages and anything malformed.
    Other,
}

pub fn parse(data: &[u8]) -> CharsetMessage {
    let Some((&code, rest)) = data.split_first() else {
        return CharsetMessage::Other;
    };
    match code {
        ACCEPTED => {
            let name = String::from_utf8_lossy(rest).into_owned();
            CharsetMessage::Accepted(Charset::from_name(&name), name)
        }
        REJECTED => CharsetMessage::Rejected,
        REQUEST => CharsetMessage::Request(parse_request(rest)),
        _ => CharsetMessage::Other,
    }
}

/// `REQUEST [TTABLE <version>] <sep> name <sep> name ...`: the first name we speak.
fn parse_request(rest: &[u8]) -> Option<Charset> {
    let rest = match rest.strip_prefix(b"[TTABLE]") {
        // A version byte follows the TTABLE marker.
        Some(after) => after.get(1..)?,
        None => rest,
    };
    let (&sep, names) = rest.split_first()?;
    names
        .split(|&b| b == sep)
        .filter_map(|n| std::str::from_utf8(n).ok())
        .find_map(Charset::from_name)
}

/// Body of an `ACCEPTED <name>` reply.
pub fn accepted_body(charset: Charset) -> Vec<u8> {
    let mut body = vec![ACCEPTED];
    body.extend_from_slice(charset.name().as_bytes());
    body
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(Charset::from_name("utf-8"), Some(Charset::Utf8));
        assert_eq!(Charset::from_name("UTF8"), Some(Charset::Utf8));
        assert_eq!(Charset::from_name("iso_8859-1"), Some(Charset::Latin1));
        assert_eq!(Charset::from_name("latin1"), Some(Charset::Latin1));
        assert_eq!(Charset::from_name("KOI8-R"), None);
    }

    #[test]
    fn request_body_order() {
        assert_eq!(request_body(), b"\x01;UTF-8;ISO-8859-1".to_vec());
    }

    #[test]
    fn parse_messages() {
        assert_eq!(
            parse(b"\x02UTF-8"),
            CharsetMessage::Accepted(Some(Charset::Utf8), "UTF-8".into())
        );
        assert_eq!(
            parse(b"\x02KOI8-R"),
            CharsetMessage::Accepted(None, "KOI8-R".into())
        );
        assert_eq!(parse(b"\x03"), CharsetMessage::Rejected);
        assert_eq!(
            parse(b"\x01 KOI8-R ISO-8859-1 UTF-8"),
            CharsetMessage::Request(Some(Charset::Latin1))
        );
        assert_eq!(
            parse(b"\x01[TTABLE]\x01;UTF-8"),
            CharsetMessage::Request(Some(Charset::Utf8))
        );
        assert_eq!(parse(b"\x01;KOI8-R"), CharsetMessage::Request(None));
        assert_eq!(parse(b""), CharsetMessage::Other);
        assert_eq!(parse(b"\x04\x01"), CharsetMessage::Other);
    }

    #[test]
    fn latin1_round_trip() {
        let all: String = (0u8..=255).map(char::from).collect();
        let mut out = BytesMut::new();
        Charset::Latin1.encode_into(&all, &mut out);
        // 256 bytes plus one doubled IAC.
        assert_eq!(out.len(), 257);
        assert_eq!(&out[255..], &[0xFF, 0xFF]);
        assert_eq!(Charset::Latin1.decode(&out[..255]), all[..all.len() - 2]);
        assert_eq!(Charset::Latin1.decode(&[0xFF]), "ÿ");
    }

    #[test]
    fn latin1_unmappable() {
        let mut out = BytesMut::new();
        Charset::Latin1.encode_into("a€b写", &mut out);
        assert_eq!(&out[..], b"a?b?");
    }
}
