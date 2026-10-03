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

//! MSSP (Mud Server Status Protocol, option 70) response encoding.

pub const VAR: u8 = 1;
pub const VAL: u8 = 2;

/// Build the body (unescaped, no framing) of an MSSP response from the configured values plus
/// the computed `PLAYERS` and `UPTIME` (Unix time the server started). Configured `PLAYERS` or
/// `UPTIME` entries are replaced by the computed ones.
pub fn encode(values: &[(String, String)], players: u64, uptime: u64) -> Vec<u8> {
    let mut out = Vec::new();
    let computed = [
        ("PLAYERS".to_string(), players.to_string()),
        ("UPTIME".to_string(), uptime.to_string()),
    ];
    let configured = values
        .iter()
        .filter(|(k, _)| !k.eq_ignore_ascii_case("PLAYERS") && !k.eq_ignore_ascii_case("UPTIME"));
    for (k, v) in configured.chain(computed.iter()) {
        out.push(VAR);
        push_text(&mut out, k);
        out.push(VAL);
        push_text(&mut out, v);
    }
    out
}

/// MSSP forbids NUL, VAR and VAL in names and values.
fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend(text.bytes().filter(|&b| b != 0 && b != VAR && b != VAL));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_configured_then_computed() {
        let values = vec![
            ("NAME".to_string(), "Test MOO".to_string()),
            ("CODEBASE".to_string(), "mooR".to_string()),
            ("players".to_string(), "999".to_string()),
        ];
        assert_eq!(
            encode(&values, 3, 1_700_000_000),
            b"\x01NAME\x02Test MOO\x01CODEBASE\x02mooR\x01PLAYERS\x023\x01UPTIME\x021700000000"
                .to_vec()
        );
    }

    #[test]
    fn strips_reserved_bytes() {
        let values = vec![("A\x01B".to_string(), "x\x02\x00y".to_string())];
        let out = encode(&values, 0, 0);
        assert!(out.starts_with(b"\x01AB\x02xy\x01PLAYERS"));
    }
}
