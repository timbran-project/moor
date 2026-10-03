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

//! MSDP (Mud Server Data Protocol, option 69) value encoding and decoding.

use moor_var::{Var, Variant, v_list, v_map, v_str};

pub const VAR: u8 = 1;
pub const VAL: u8 = 2;
pub const TABLE_OPEN: u8 = 3;
pub const TABLE_CLOSE: u8 = 4;
pub const ARRAY_OPEN: u8 = 5;
pub const ARRAY_CLOSE: u8 = 6;

/// Nesting deeper than this is written as an empty string, and read as the empty string.
const MAX_DEPTH: usize = 32;

/// Build the body (unescaped, no framing) of `VAR <name> VAL <value>`.
pub fn encode(name: &str, value: &Var) -> Vec<u8> {
    let mut out = Vec::with_capacity(name.len() + 16);
    out.push(VAR);
    push_text(&mut out, name);
    out.push(VAL);
    encode_value(value, &mut out, 0);
    out
}

fn encode_value(value: &Var, out: &mut Vec<u8>, depth: usize) {
    if depth >= MAX_DEPTH {
        return;
    }
    match value.variant() {
        Variant::Map(m) => {
            out.push(TABLE_OPEN);
            for (k, v) in m.iter_ref() {
                out.push(VAR);
                push_text(out, &scalar_text(k));
                out.push(VAL);
                encode_value(v, out, depth + 1);
            }
            out.push(TABLE_CLOSE);
        }
        Variant::List(l) => {
            out.push(ARRAY_OPEN);
            for v in l.iter() {
                out.push(VAL);
                encode_value(&v, out, depth + 1);
            }
            out.push(ARRAY_CLOSE);
        }
        _ => push_text(out, &scalar_text(value)),
    }
}

/// The string form of a scalar. MSDP control bytes are dropped from it.
fn scalar_text(v: &Var) -> String {
    match v.variant() {
        Variant::Str(s) => s.as_str().to_string(),
        Variant::Sym(s) => s.as_string(),
        Variant::Int(i) => i.to_string(),
        Variant::Float(f) => f.to_string(),
        Variant::Bool(b) => if b { "1" } else { "0" }.to_string(),
        Variant::Obj(o) => o.to_string(),
        Variant::None => String::new(),
        _ => format!("{v:?}"),
    }
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend(text.bytes().filter(|b| !(VAR..=ARRAY_CLOSE).contains(b)));
}

/// Decode a body into its top-level `(name, value)` pairs. Tables become maps with string keys,
/// arrays become lists, and scalars become strings. A variable with several `VAL`s becomes a
/// list of them.
pub fn decode(data: &[u8]) -> Vec<(String, Var)> {
    let mut p = Parser { data, pos: 0 };
    p.pairs(None, 0)
}

struct Parser<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.data.get(self.pos).copied()
    }

    /// Read `VAR name VAL value...` pairs until `end` or the end of input.
    fn pairs(&mut self, end: Option<u8>, depth: usize) -> Vec<(String, Var)> {
        let mut pairs = Vec::new();
        while let Some(b) = self.peek() {
            if Some(b) == end {
                self.pos += 1;
                break;
            }
            if b != VAR {
                // Stray bytes between pairs.
                self.pos += 1;
                continue;
            }
            self.pos += 1;
            let name = self.text();
            let mut values = Vec::new();
            while self.peek() == Some(VAL) {
                self.pos += 1;
                values.push(self.value(depth));
            }
            let value = match values.len() {
                0 => v_str(""),
                1 => values.pop().unwrap_or_else(|| v_str("")),
                _ => v_list(&values),
            };
            pairs.push((name, value));
        }
        pairs
    }

    fn value(&mut self, depth: usize) -> Var {
        if depth >= MAX_DEPTH {
            self.skip_value();
            return v_str("");
        }
        match self.peek() {
            Some(TABLE_OPEN) => {
                self.pos += 1;
                let pairs: Vec<(Var, Var)> = self
                    .pairs(Some(TABLE_CLOSE), depth + 1)
                    .into_iter()
                    .map(|(k, v)| (v_str(&k), v))
                    .collect();
                v_map(&pairs)
            }
            Some(ARRAY_OPEN) => {
                self.pos += 1;
                let mut items = Vec::new();
                loop {
                    match self.peek() {
                        None => break,
                        Some(ARRAY_CLOSE) => {
                            self.pos += 1;
                            break;
                        }
                        Some(VAL) => {
                            self.pos += 1;
                            items.push(self.value(depth + 1));
                        }
                        Some(_) => self.pos += 1,
                    }
                }
                v_list(&items)
            }
            _ => v_str(&self.text()),
        }
    }

    /// Skip one value, including any nested tables and arrays.
    fn skip_value(&mut self) {
        let mut level = 0usize;
        while let Some(b) = self.peek() {
            match b {
                TABLE_OPEN | ARRAY_OPEN => level += 1,
                TABLE_CLOSE | ARRAY_CLOSE if level == 0 => return,
                TABLE_CLOSE | ARRAY_CLOSE => level -= 1,
                VAR | VAL if level == 0 => return,
                _ => {}
            }
            self.pos += 1;
        }
    }

    /// Bytes up to the next MSDP control byte, as lossy UTF-8.
    fn text(&mut self) -> String {
        let start = self.pos;
        while let Some(b) = self.peek() {
            if (VAR..=ARRAY_CLOSE).contains(&b) {
                break;
            }
            self.pos += 1;
        }
        String::from_utf8_lossy(&self.data[start..self.pos]).into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{v_int, v_sym};

    #[test]
    fn encode_scalar() {
        assert_eq!(encode("HEALTH", &v_int(100)), b"\x01HEALTH\x02100".to_vec());
        assert_eq!(encode("NAME", &v_str("Bob")), b"\x01NAME\x02Bob".to_vec());
        assert_eq!(encode("S", &v_sym("x")), b"\x01S\x02x".to_vec());
        // Control bytes inside text are dropped so they cannot change structure.
        assert_eq!(encode("N", &v_str("a\x01b")), b"\x01N\x02ab".to_vec());
    }

    #[test]
    fn encode_array_and_table() {
        let list = v_list(&[v_str("a"), v_int(2)]);
        assert_eq!(encode("L", &list), b"\x01L\x02\x05\x02a\x022\x06".to_vec());
        let map = v_map(&[(v_str("hp"), v_int(1)), (v_str("mp"), v_list(&[v_int(3)]))]);
        assert_eq!(
            encode("ROOM", &map),
            b"\x01ROOM\x02\x03\x01hp\x021\x01mp\x02\x05\x023\x06\x04".to_vec()
        );
    }

    #[test]
    fn decode_commands() {
        assert_eq!(
            decode(b"\x01LIST\x02COMMANDS"),
            vec![("LIST".to_string(), v_str("COMMANDS"))]
        );
        assert_eq!(
            decode(b"\x01REPORT\x02HEALTH\x02MANA"),
            vec![(
                "REPORT".to_string(),
                v_list(&[v_str("HEALTH"), v_str("MANA")])
            )]
        );
        assert_eq!(
            decode(b"\x01SEND\x02\x05\x02A\x02B\x06"),
            vec![("SEND".to_string(), v_list(&[v_str("A"), v_str("B")]))]
        );
        assert_eq!(
            decode(b"\x01A\x021\x01B\x022"),
            vec![("A".to_string(), v_str("1")), ("B".to_string(), v_str("2"))]
        );
        assert_eq!(decode(b"\x01X"), vec![("X".to_string(), v_str(""))]);
        assert_eq!(decode(b""), vec![]);
        assert_eq!(decode(b"junk"), vec![]);
    }

    #[test]
    fn round_trip_nested() {
        let map = v_map(&[
            (v_str("a"), v_str("1")),
            (
                v_str("t"),
                v_map(&[(v_str("x"), v_list(&[v_str("p"), v_str("q")]))]),
            ),
        ]);
        let body = encode("V", &map);
        assert_eq!(decode(&body), vec![("V".to_string(), map)]);
    }

    #[test]
    fn deep_nesting_is_bounded() {
        let mut body = b"\x01D\x02".to_vec();
        for _ in 0..1000 {
            body.extend_from_slice(b"\x05\x02");
        }
        body.extend_from_slice(b"x");
        // Must terminate without blowing the stack; content past the cap is discarded.
        let out = decode(&body);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].0, "D");

        let mut v = v_str("x");
        for _ in 0..1000 {
            v = v_list(&[v]);
        }
        let enc = encode("D", &v);
        assert!(enc.len() < 200);
    }
}
