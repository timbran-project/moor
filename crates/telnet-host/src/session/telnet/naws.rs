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

//! NAWS (Negotiate About Window Size, RFC 1073, option 31).

/// Parse `<width16> <height16>` (big-endian). Zero means "unknown" and is passed through.
pub fn parse(data: &[u8]) -> Option<(u16, u16)> {
    let [w0, w1, h0, h1] = data else {
        return None;
    };
    Some((
        u16::from_be_bytes([*w0, *w1]),
        u16::from_be_bytes([*h0, *h1]),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sizes() {
        assert_eq!(parse(&[0, 80, 0, 24]), Some((80, 24)));
        assert_eq!(parse(&[0x01, 0x00, 0xFF, 0xFF]), Some((256, 65535)));
        assert_eq!(parse(&[0, 0, 0, 0]), Some((0, 0)));
        assert_eq!(parse(&[0, 80, 0]), None);
        assert_eq!(parse(&[0, 80, 0, 24, 0]), None);
    }
}
