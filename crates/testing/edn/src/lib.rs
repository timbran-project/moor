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

//! The subset of EDN used by mooR's Elle and Jepsen history tooling: `nil`, integers, keywords,
//! vectors and maps. Commas count as whitespace, and `;` starts a comment that runs to the end of
//! the line. Other EDN forms are rejected when read.

use std::{collections::BTreeMap, fmt};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Keyword(String);

impl Keyword {
    pub fn from_name(name: &str) -> Self {
        Self(name.to_string())
    }

    pub fn name(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Value {
    Nil,
    Integer(i64),
    Keyword(Keyword),
    Vector(Vec<Value>),
    Map(BTreeMap<Value, Value>),
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Nil => f.write_str("nil"),
            Value::Integer(i) => write!(f, "{i}"),
            Value::Keyword(k) => write!(f, ":{}", k.0),
            Value::Vector(items) => {
                f.write_str("[")?;
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        f.write_str(" ")?;
                    }
                    write!(f, "{item}")?;
                }
                f.write_str("]")
            }
            Value::Map(entries) => {
                f.write_str("{")?;
                for (i, (key, value)) in entries.iter().enumerate() {
                    if i > 0 {
                        f.write_str(", ")?;
                    }
                    write!(f, "{key} {value}")?;
                }
                f.write_str("}")
            }
        }
    }
}

/// Writes a value as EDN text.
pub fn emit_str(value: &Value) -> String {
    value.to_string()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    pub offset: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "EDN parse error at byte {}: {}",
            self.offset, self.message
        )
    }
}

impl std::error::Error for ParseError {}

/// Reads every top-level value in `input`.
pub fn parse_str(input: &str) -> Result<Vec<Value>, ParseError> {
    let mut reader = Reader {
        input: input.as_bytes(),
        pos: 0,
    };
    let mut values = Vec::new();
    while reader.skip_whitespace() {
        values.push(reader.value()?);
    }
    Ok(values)
}

struct Reader<'a> {
    input: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    /// Skips whitespace, commas and comments. Returns whether input remains.
    fn skip_whitespace(&mut self) -> bool {
        while let Some(&b) = self.input.get(self.pos) {
            match b {
                b' ' | b'\t' | b'\n' | b'\r' | b',' => self.pos += 1,
                b';' => {
                    while self.input.get(self.pos).is_some_and(|&b| b != b'\n') {
                        self.pos += 1;
                    }
                }
                _ => return true,
            }
        }
        false
    }

    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError {
            offset: self.pos,
            message: message.into(),
        }
    }

    fn value(&mut self) -> Result<Value, ParseError> {
        match self.input[self.pos] {
            b'[' => {
                self.pos += 1;
                Ok(Value::Vector(self.items(b']')?))
            }
            b'{' => {
                let start = self.pos;
                self.pos += 1;
                let items = self.items(b'}')?;
                if items.len() % 2 != 0 {
                    return Err(ParseError {
                        offset: start,
                        message: "map has a key without a value".into(),
                    });
                }
                let mut map = BTreeMap::new();
                let mut items = items.into_iter();
                while let (Some(key), Some(value)) = (items.next(), items.next()) {
                    map.insert(key, value);
                }
                Ok(Value::Map(map))
            }
            b':' => {
                self.pos += 1;
                let name = self.token();
                if name.is_empty() {
                    return Err(self.error("keyword has no name"));
                }
                Ok(Value::Keyword(Keyword(name.to_string())))
            }
            _ => {
                let start = self.pos;
                let token = self.token();
                if token == "nil" {
                    return Ok(Value::Nil);
                }
                token.parse().map(Value::Integer).map_err(|_| ParseError {
                    offset: start,
                    message: format!("unsupported EDN form `{token}`"),
                })
            }
        }
    }

    fn items(&mut self, close: u8) -> Result<Vec<Value>, ParseError> {
        let mut items = Vec::new();
        loop {
            if !self.skip_whitespace() {
                return Err(self.error(format!("missing `{}`", close as char)));
            }
            if self.input[self.pos] == close {
                self.pos += 1;
                return Ok(items);
            }
            if matches!(self.input[self.pos], b']' | b'}') {
                return Err(self.error(format!("expected `{}`", close as char)));
            }
            items.push(self.value()?);
        }
    }

    /// Reads up to the next delimiter. The result may be empty.
    fn token(&mut self) -> &str {
        let start = self.pos;
        while let Some(&b) = self.input.get(self.pos) {
            if matches!(
                b,
                b' ' | b'\t' | b'\n' | b'\r' | b',' | b';' | b'[' | b']' | b'{' | b'}'
            ) {
                break;
            }
            self.pos += 1;
        }
        // Delimiters are ASCII, so the slice ends on a character boundary.
        std::str::from_utf8(&self.input[start..self.pos]).unwrap_or("")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn written_history_reads_back() {
        let keyword = |name| Value::Keyword(Keyword::from_name(name));
        let event = Value::Map(BTreeMap::from([
            (keyword("index"), Value::Integer(0)),
            (keyword("time"), Value::Integer(-1)),
            (keyword("type"), keyword("invoke")),
            (
                keyword("value"),
                Value::Vector(vec![
                    Value::Vector(vec![
                        keyword("append"),
                        Value::Integer(9),
                        Value::Integer(1),
                    ]),
                    Value::Vector(vec![keyword("r"), Value::Integer(9), Value::Nil]),
                    Value::Vector(vec![
                        keyword("r"),
                        Value::Integer(9),
                        Value::Vector(vec![Value::Integer(1), Value::Integer(2)]),
                    ]),
                ]),
            ),
        ]));
        let text = format!(
            "{}\n; comment\n{}\n",
            emit_str(&event),
            emit_str(&Value::Nil)
        );
        assert_eq!(parse_str(&text).unwrap(), vec![event, Value::Nil]);
    }

    #[test]
    fn rejects_unsupported_and_malformed_input() {
        for input in [
            "\"text\"", "true", "#{1}", "[1 2", "{:a}", "[1}", ":", "1.5",
        ] {
            assert!(parse_str(input).is_err(), "{input} should not parse");
        }
    }
}
