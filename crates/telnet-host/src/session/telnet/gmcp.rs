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

//! GMCP (Generic MUD Communication Protocol, option 201) message encoding and decoding,
//! `Core.Hello` and `Core.Supports.*` handling, and package gating.
//!
//! A message is `<Package.Name>[ <json>]`. The JSON mapping follows the contract table in
//! `doc/telnet-oob-protocols.md`.

use std::collections::BTreeMap;

use moor_var::{
    Map, NOTHING, Var, Variant, v_bool, v_bool_int, v_float, v_int, v_list, v_map, v_obj, v_str,
};
use serde_json::Value as JsonValue;

/// Why a value could not be turned into JSON.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct JsonError(pub String);

/// MOO value to JSON.
pub type JsonEncode = fn(&Var) -> Result<JsonValue, JsonError>;
/// JSON to MOO value; the flag is the daemon's `use_boolean_returns`.
pub type JsonDecode = fn(&JsonValue, bool) -> Var;

/// The value <-> JSON mapping the GMCP code uses.
#[derive(Copy, Clone, Debug)]
pub struct JsonCodec {
    pub encode: JsonEncode,
    pub decode: JsonDecode,
}

impl Default for JsonCodec {
    fn default() -> Self {
        // Replaced by moor_var::json when that module is merged.
        Self {
            encode: local_json::var_to_json,
            decode: local_json::json_to_var,
        }
    }
}

/// Why an outbound message was not built.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GmcpError {
    InvalidPackageName(String),
    Json(JsonError),
}

/// True when `name` matches `[A-Za-z0-9_.-]{1,128}`.
pub fn valid_package_name(name: &str) -> bool {
    (1..=128).contains(&name.len())
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'-'))
}

/// Build the subnegotiation body (unescaped, no framing) for `kind` with `payload`. The empty
/// map is sent as the bare package name.
pub fn encode(kind: &str, payload: &Var, json: &JsonCodec) -> Result<Vec<u8>, GmcpError> {
    if !valid_package_name(kind) {
        return Err(GmcpError::InvalidPackageName(kind.to_string()));
    }
    let mut body = kind.as_bytes().to_vec();
    if is_empty_map(payload) {
        return Ok(body);
    }
    let value = (json.encode)(payload).map_err(GmcpError::Json)?;
    body.push(b' ');
    serde_json::to_writer(&mut body, &value)
        .map_err(|e| GmcpError::Json(JsonError(e.to_string())))?;
    Ok(body)
}

fn is_empty_map(v: &Var) -> bool {
    matches!(v.variant(), Variant::Map(m) if moor_var::Associative::is_empty(m))
}

/// A received GMCP message.
#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub package: String,
    pub payload: Var,
}

/// Parse a subnegotiation body. `None` when the package name is missing or invalid.
pub fn decode(data: &[u8], json: &JsonCodec, boolean_returns: bool) -> Option<Message> {
    let text = String::from_utf8_lossy(data);
    let text = text.trim_start();
    let (package, body) = match text.find(|c: char| c.is_ascii_whitespace()) {
        Some(at) => (&text[..at], text[at..].trim()),
        None => (text, ""),
    };
    if !valid_package_name(package) {
        return None;
    }
    let payload = if body.is_empty() {
        v_map(&[])
    } else {
        match serde_json::from_str::<JsonValue>(body) {
            Ok(value) => (json.decode)(&value, boolean_returns),
            Err(_) => v_str(body),
        }
    };
    Some(Message {
        package: package.to_string(),
        payload,
    })
}

/// The packages a client declared with `Core.Supports.*`. Names compare case-insensitively.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GmcpSupports {
    /// False until the client sends `Core.Supports.Set` or `.Add`.
    declared: bool,
    /// Lower-cased name -> (name as sent, version).
    packages: BTreeMap<String, (String, i64)>,
}

impl GmcpSupports {
    pub fn is_declared(&self) -> bool {
        self.declared
    }

    pub fn version(&self, package: &str) -> Option<i64> {
        self.packages
            .get(&package.to_ascii_lowercase())
            .map(|(_, v)| *v)
    }

    /// Whether a message for `package` may be sent: always before any declaration; afterwards
    /// when the package or one of its parents is declared. `Core` is always allowed.
    pub fn wants(&self, package: &str) -> bool {
        if !self.declared {
            return true;
        }
        let lower = package.to_ascii_lowercase();
        if lower == "core" || lower.starts_with("core.") {
            return true;
        }
        let mut name = lower.as_str();
        loop {
            if self.packages.contains_key(name) {
                return true;
            }
            let Some(dot) = name.rfind('.') else {
                return false;
            };
            name = &name[..dot];
        }
    }

    /// Apply a `Core.Supports.Set|Add|Remove` message. Returns true when the set changed.
    pub fn apply(&mut self, message: &str, payload: &Var) -> bool {
        let entries = supports_entries(payload);
        let before = self.clone();
        match message.to_ascii_lowercase().as_str() {
            "core.supports.set" => {
                self.declared = true;
                self.packages.clear();
                self.insert_all(entries);
            }
            "core.supports.add" => {
                self.declared = true;
                self.insert_all(entries);
            }
            "core.supports.remove" => {
                for (name, _) in entries {
                    self.packages.remove(&name.to_ascii_lowercase());
                }
            }
            _ => return false,
        }
        *self != before
    }

    fn insert_all(&mut self, entries: Vec<(String, i64)>) {
        for (name, version) in entries {
            self.packages
                .insert(name.to_ascii_lowercase(), (name, version));
        }
    }

    /// The `gmcp_supports` attribute: MAP STR -> INT.
    pub fn to_var(&self) -> Var {
        let pairs: Vec<(Var, Var)> = self
            .packages
            .values()
            .map(|(name, version)| (v_str(name), v_int(*version)))
            .collect();
        v_map(&pairs)
    }
}

/// `["Char 1", "Room 1"]` -> `[("Char", 1), ("Room", 1)]`. A missing or bad version is 1.
fn supports_entries(payload: &Var) -> Vec<(String, i64)> {
    let Some(list) = payload.as_list() else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|item| {
            let s = item.as_string()?.trim().to_string();
            let mut parts = s.split_ascii_whitespace();
            let name = parts.next()?;
            if !valid_package_name(name) {
                return None;
            }
            let version = parts.next().and_then(|v| v.parse().ok()).unwrap_or(1);
            Some((name.to_string(), version))
        })
        .collect()
}

/// `Core.Hello {"client": ..., "version": ...}` -> (client, version).
pub fn hello_fields(payload: &Var) -> (Option<String>, Option<String>) {
    let Some(map) = payload.as_map() else {
        return (None, None);
    };
    (map_string(map, "client"), map_string(map, "version"))
}

fn map_string(map: &Map, key: &str) -> Option<String> {
    map.iter_ref()
        .find(|(k, _)| k.as_string().is_some_and(|s| s.eq_ignore_ascii_case(key)))
        .and_then(|(_, v)| match v.variant() {
            Variant::Str(s) => Some(s.as_str().to_string()),
            Variant::Int(i) => Some(i.to_string()),
            Variant::Float(f) => Some(f.to_string()),
            _ => None,
        })
}

/// Minimal MOO <-> JSON conversion following the contract table.
mod local_json {
    use super::*;

    pub fn var_to_json(v: &Var) -> Result<JsonValue, JsonError> {
        match v.variant() {
            Variant::Int(i) => Ok(JsonValue::from(i)),
            Variant::Float(f) => serde_json::Number::from_f64(f)
                .map(JsonValue::Number)
                .ok_or_else(|| JsonError(format!("non-finite float {f}"))),
            Variant::Str(s) => Ok(JsonValue::String(s.as_str().to_string())),
            Variant::Sym(s) => Ok(JsonValue::String(s.as_string())),
            Variant::Bool(b) => Ok(JsonValue::Bool(b)),
            Variant::Obj(o) if o == NOTHING => Ok(JsonValue::Null),
            Variant::Obj(o) => Ok(JsonValue::String(o.to_string())),
            Variant::List(l) => l
                .iter()
                .map(|e| var_to_json(&e))
                .collect::<Result<_, _>>()
                .map(JsonValue::Array),
            Variant::Map(m) => {
                let mut out = serde_json::Map::new();
                for (k, val) in m.iter_ref() {
                    out.insert(map_key(k)?, var_to_json(val)?);
                }
                Ok(JsonValue::Object(out))
            }
            _ => Err(JsonError(format!(
                "cannot convert {} to JSON",
                v.type_code().to_literal()
            ))),
        }
    }

    fn map_key(k: &Var) -> Result<String, JsonError> {
        match k.variant() {
            Variant::Str(s) => Ok(s.as_str().to_string()),
            Variant::Sym(s) => Ok(s.as_string()),
            Variant::Int(i) => Ok(i.to_string()),
            Variant::Float(f) if f.is_finite() => Ok(f.to_string()),
            Variant::Obj(o) => Ok(o.to_string()),
            _ => Err(JsonError(format!(
                "cannot use {} as a JSON key",
                k.type_code().to_literal()
            ))),
        }
    }

    pub fn json_to_var(j: &JsonValue, boolean_returns: bool) -> Var {
        match j {
            JsonValue::Null => v_obj(NOTHING),
            JsonValue::Bool(b) if boolean_returns => v_bool(*b),
            JsonValue::Bool(b) => v_bool_int(*b),
            JsonValue::Number(n) => match n.as_i64() {
                Some(i) => v_int(i),
                None => v_float(n.as_f64().unwrap_or(0.0)),
            },
            JsonValue::String(s) => v_str(s),
            JsonValue::Array(a) => {
                let items: Vec<Var> = a.iter().map(|e| json_to_var(e, boolean_returns)).collect();
                v_list(&items)
            }
            JsonValue::Object(o) => {
                let pairs: Vec<(Var, Var)> = o
                    .iter()
                    .map(|(k, v)| (v_str(k), json_to_var(v, boolean_returns)))
                    .collect();
                v_map(&pairs)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{E_PERM, Obj, Symbol, v_binary, v_err, v_sym};

    fn json(body: &[u8]) -> JsonValue {
        serde_json::from_slice(body).unwrap()
    }

    #[test]
    fn package_names() {
        assert!(valid_package_name("Char.Vitals"));
        assert!(valid_package_name("a_b-c.9"));
        assert!(valid_package_name(&"a".repeat(128)));
        assert!(!valid_package_name(&"a".repeat(129)));
        assert!(!valid_package_name(""));
        assert!(!valid_package_name("Char Vitals"));
        assert!(!valid_package_name("Char/Vitals"));
        assert!(!valid_package_name("Char.Vitäls"));
    }

    #[test]
    fn encode_with_body() {
        let codec = JsonCodec::default();
        let payload = v_map(&[(v_str("hp"), v_int(12))]);
        let body = encode("Char.Vitals", &payload, &codec).unwrap();
        let (name, rest) = body.split_at(12);
        assert_eq!(name, b"Char.Vitals ");
        assert_eq!(json(rest), serde_json::json!({"hp": 12}));
    }

    #[test]
    fn encode_empty_map_has_no_body() {
        let codec = JsonCodec::default();
        assert_eq!(
            encode("Core.Ping", &v_map(&[]), &codec).unwrap(),
            b"Core.Ping"
        );
        // The empty list is a value, not "no body".
        assert_eq!(encode("X.Y", &v_list(&[]), &codec).unwrap(), b"X.Y []");
    }

    #[test]
    fn encode_rejects_bad_name_and_unconvertible() {
        let codec = JsonCodec::default();
        assert!(matches!(
            encode("bad name", &v_int(1), &codec),
            Err(GmcpError::InvalidPackageName(_))
        ));
        // MOO values cannot hold non-finite floats, so that row is not reachable here.
        for v in [v_err(E_PERM), v_binary(vec![1])] {
            assert!(matches!(encode("A.B", &v, &codec), Err(GmcpError::Json(_))));
        }
        let err_key = v_map(&[(v_err(E_PERM), v_int(1))]);
        assert!(matches!(
            encode("A.B", &err_key, &codec),
            Err(GmcpError::Json(_))
        ));
    }

    #[test]
    fn json_conversion_table() {
        let enc = JsonCodec::default().encode;
        assert_eq!(enc(&v_int(-3)).unwrap(), serde_json::json!(-3));
        assert_eq!(enc(&v_float(1.5)).unwrap(), serde_json::json!(1.5));
        assert_eq!(enc(&v_str("x")).unwrap(), serde_json::json!("x"));
        assert_eq!(enc(&v_sym("foo")).unwrap(), serde_json::json!("foo"));
        assert_eq!(enc(&v_bool(true)).unwrap(), serde_json::json!(true));
        assert_eq!(enc(&v_obj(NOTHING)).unwrap(), JsonValue::Null);
        assert_eq!(
            enc(&v_obj(Obj::mk_id(42))).unwrap(),
            serde_json::json!("#42")
        );
        assert_eq!(
            enc(&v_list(&[v_int(1), v_str("a")])).unwrap(),
            serde_json::json!([1, "a"])
        );
        let m = v_map(&[
            (v_str("s"), v_int(1)),
            (Var::mk_symbol(Symbol::mk("y")), v_int(2)),
            (v_int(3), v_int(3)),
            (v_obj(Obj::mk_id(7)), v_int(4)),
        ]);
        assert_eq!(
            enc(&m).unwrap(),
            serde_json::json!({"s": 1, "y": 2, "3": 3, "#7": 4})
        );
    }

    #[test]
    fn decode_messages() {
        let codec = JsonCodec::default();
        let m = decode(b"Char.Vitals {\"hp\": 5, \"ok\": true}", &codec, false).unwrap();
        assert_eq!(m.package, "Char.Vitals");
        assert_eq!(
            m.payload,
            v_map(&[(v_str("hp"), v_int(5)), (v_str("ok"), v_int(1))])
        );
        let m = decode(b"A.B {\"ok\": true, \"n\": null}", &codec, true).unwrap();
        assert_eq!(
            m.payload,
            v_map(&[(v_str("ok"), v_bool(true)), (v_str("n"), v_obj(NOTHING))])
        );
        // No body and explicit {} both mean the empty map.
        let m = decode(b"Core.Ping", &codec, false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        let m = decode(b"Core.Ping {}", &codec, false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        let m = decode(b"Core.Ping   ", &codec, false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        // Invalid JSON is the raw text.
        let m = decode(b"Comm.Say hello there", &codec, false).unwrap();
        assert_eq!(m.payload, v_str("hello there"));
        assert!(m.payload.as_string() == Some("hello there"));
        // Invalid names are dropped.
        assert!(decode(b"", &codec, false).is_none());
        assert!(decode(b"bad/name 1", &codec, false).is_none());
        // Floats and arrays.
        let m = decode(b"X.Y [1, 2.5, \"s\"]", &codec, false).unwrap();
        assert_eq!(m.payload, v_list(&[v_int(1), v_float(2.5), v_str("s")]));
    }

    #[test]
    fn supports_set_add_remove() {
        let mut s = GmcpSupports::default();
        assert!(!s.is_declared());
        assert!(s.wants("Anything.At.All"));

        let set = v_list(&[
            v_str("Char 1"),
            v_str("Room 2"),
            v_str("Bogus/1 1"),
            v_int(5),
        ]);
        assert!(s.apply("Core.Supports.Set", &set));
        assert!(s.is_declared());
        assert_eq!(s.version("char"), Some(1));
        assert_eq!(s.version("Room"), Some(2));
        assert_eq!(s.version("Bogus/1"), None);
        // Applying the same set again is not a change.
        assert!(!s.apply("Core.Supports.Set", &set));

        assert!(s.apply("Core.Supports.Add", &v_list(&[v_str("Comm.Channel")])));
        assert_eq!(s.version("Comm.Channel"), Some(1));

        assert!(s.apply("Core.Supports.Remove", &v_list(&[v_str("Room")])));
        assert_eq!(s.version("Room"), None);

        // Set replaces.
        assert!(s.apply("Core.Supports.Set", &v_list(&[v_str("IRE.Rift 1")])));
        assert_eq!(s.version("Char"), None);
        assert_eq!(s.to_var(), v_map(&[(v_str("IRE.Rift"), v_int(1))]));
        assert!(!s.apply("Core.Hello", &v_list(&[])));
    }

    #[test]
    fn supports_gating_with_parents() {
        let mut s = GmcpSupports::default();
        s.apply(
            "Core.Supports.Set",
            &v_list(&[v_str("Char 1"), v_str("Room.Info 1")]),
        );
        assert!(s.wants("Char"));
        assert!(s.wants("Char.Vitals"));
        assert!(s.wants("char.items.list"));
        assert!(s.wants("Room.Info"));
        assert!(!s.wants("Room"));
        assert!(!s.wants("Room.Players"));
        assert!(!s.wants("Charm.Spell"));
        assert!(!s.wants("Comm.Channel"));
        assert!(s.wants("Core.Ping"));
        // An empty declared set allows only Core.
        s.apply(
            "Core.Supports.Remove",
            &v_list(&[v_str("Char"), v_str("Room.Info")]),
        );
        assert!(s.is_declared());
        assert!(!s.wants("Char.Vitals"));
        assert!(s.wants("Core.Goodbye"));
    }

    #[test]
    fn hello() {
        let p = v_map(&[
            (v_str("client"), v_str("Mudlet")),
            (v_str("version"), v_str("4.17.2")),
        ]);
        assert_eq!(
            hello_fields(&p),
            (Some("Mudlet".into()), Some("4.17.2".into()))
        );
        assert_eq!(hello_fields(&v_str("x")), (None, None));
        let p = v_map(&[(v_str("client"), v_str("TinTin++"))]);
        assert_eq!(hello_fields(&p), (Some("TinTin++".into()), None));
    }
}
