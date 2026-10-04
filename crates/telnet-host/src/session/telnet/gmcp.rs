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
//! A message is `<Package.Name>[ <json>]`.

use std::collections::{BTreeMap, btree_map::Entry};

use moor_var::{
    Map, Var, Variant,
    json::{json_to_var, var_to_json},
    v_int, v_map, v_str,
};
use serde_json::Value as JsonValue;

/// Why an outbound message was not built.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GmcpError {
    InvalidPackageName,
    Json(String),
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
pub fn encode(kind: &str, payload: &Var) -> Result<Vec<u8>, GmcpError> {
    if !valid_package_name(kind) {
        return Err(GmcpError::InvalidPackageName);
    }
    let mut body = kind.as_bytes().to_vec();
    if is_empty_map(payload) {
        return Ok(body);
    }
    let value = var_to_json(payload).map_err(|e| GmcpError::Json(e.to_string()))?;
    body.push(b' ');
    serde_json::to_writer(&mut body, &value).map_err(|e| GmcpError::Json(e.to_string()))?;
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
pub fn decode(data: &[u8], boolean_returns: bool) -> Option<Message> {
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
            Ok(value) => json_to_var(&value, boolean_returns),
            Err(_) => v_str(body),
        }
    };
    Some(Message {
        package: package.to_string(),
        payload,
    })
}

/// Bound retained client input across repeated `Core.Supports.Add` messages.
const MAX_SUPPORTED_PACKAGES: usize = 1024;

/// The packages a client declared with `Core.Supports.*`. Names compare case-insensitively.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GmcpSupports {
    /// False until the client sends `Core.Supports.Set` or `.Add`.
    declared: bool,
    /// Lower-cased name -> (name as sent, version).
    packages: BTreeMap<String, (String, i64)>,
}

impl GmcpSupports {
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
        match message.to_ascii_lowercase().as_str() {
            "core.supports.set" => {
                let mut replacement = Self {
                    declared: true,
                    ..Self::default()
                };
                replacement.insert_all(payload);
                if *self == replacement {
                    return false;
                }
                *self = replacement;
                true
            }
            "core.supports.add" => {
                let changed = self.insert_all(payload) || !self.declared;
                self.declared = true;
                changed
            }
            "core.supports.remove" => {
                let mut changed = false;
                for (name, _) in supports_entries(payload) {
                    changed |= self.packages.remove(&name.to_ascii_lowercase()).is_some();
                }
                changed
            }
            _ => false,
        }
    }

    fn insert_all(&mut self, payload: &Var) -> bool {
        let mut changed = false;
        for (name, version) in supports_entries(payload) {
            let has_capacity = self.packages.len() < MAX_SUPPORTED_PACKAGES;
            match self.packages.entry(name.to_ascii_lowercase()) {
                Entry::Occupied(mut entry) => {
                    if entry.get().0 != name || entry.get().1 != version {
                        entry.insert((name, version));
                        changed = true;
                    }
                }
                Entry::Vacant(entry) if has_capacity => {
                    entry.insert((name, version));
                    changed = true;
                }
                Entry::Vacant(_) => {}
            }
        }
        changed
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
fn supports_entries(payload: &Var) -> impl Iterator<Item = (String, i64)> + '_ {
    payload
        .as_list()
        .into_iter()
        .flat_map(|list| list.iter())
        .filter_map(|item| {
            let mut parts = item.as_string()?.split_ascii_whitespace();
            let name = parts.next()?;
            if !valid_package_name(name) {
                return None;
            }
            let version = parts.next().and_then(|v| v.parse().ok()).unwrap_or(1);
            Some((name.to_string(), version))
        })
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

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{E_PERM, NOTHING, v_binary, v_bool, v_err, v_float, v_list, v_obj};

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
        let payload = v_map(&[(v_str("hp"), v_int(12))]);
        let body = encode("Char.Vitals", &payload).unwrap();
        let (name, rest) = body.split_at(12);
        assert_eq!(name, b"Char.Vitals ");
        assert_eq!(json(rest), serde_json::json!({"hp": 12}));
    }

    #[test]
    fn encode_empty_map_has_no_body() {
        assert_eq!(encode("Core.Ping", &v_map(&[])).unwrap(), b"Core.Ping");
        // The empty list is a value, not "no body".
        assert_eq!(encode("X.Y", &v_list(&[])).unwrap(), b"X.Y []");
    }

    #[test]
    fn encode_rejects_bad_name_and_unconvertible() {
        assert!(matches!(
            encode("bad name", &v_int(1)),
            Err(GmcpError::InvalidPackageName)
        ));
        // MOO values cannot hold non-finite floats, so that row is not reachable here.
        for v in [v_err(E_PERM), v_binary(vec![1])] {
            assert!(matches!(encode("A.B", &v), Err(GmcpError::Json(_))));
        }
        let err_key = v_map(&[(v_err(E_PERM), v_int(1))]);
        assert!(matches!(encode("A.B", &err_key), Err(GmcpError::Json(_))));
    }

    #[test]
    fn decode_messages() {
        let m = decode(b"Char.Vitals {\"hp\": 5, \"ok\": true}", false).unwrap();
        assert_eq!(m.package, "Char.Vitals");
        assert_eq!(
            m.payload,
            v_map(&[(v_str("hp"), v_int(5)), (v_str("ok"), v_int(1))])
        );
        let m = decode(b"A.B {\"ok\": true, \"n\": null}", true).unwrap();
        assert_eq!(
            m.payload,
            v_map(&[(v_str("ok"), v_bool(true)), (v_str("n"), v_obj(NOTHING))])
        );
        // No body and explicit {} both mean the empty map.
        let m = decode(b"Core.Ping", false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        let m = decode(b"Core.Ping {}", false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        let m = decode(b"Core.Ping   ", false).unwrap();
        assert_eq!(m.payload, v_map(&[]));
        // Invalid JSON is the raw text.
        let m = decode(b"Comm.Say hello there", false).unwrap();
        assert_eq!(m.payload, v_str("hello there"));
        // Invalid names are dropped.
        assert!(decode(b"", false).is_none());
        assert!(decode(b"bad/name 1", false).is_none());
        // Floats and arrays.
        let m = decode(b"X.Y [1, 2.5, \"s\"]", false).unwrap();
        assert_eq!(m.payload, v_list(&[v_int(1), v_float(2.5), v_str("s")]));
    }

    #[test]
    fn supports_set_add_remove() {
        let mut s = GmcpSupports::default();
        assert!(!s.declared);
        assert!(s.wants("Anything.At.All"));

        let set = v_list(&[
            v_str("Char 1"),
            v_str("Room 2"),
            v_str("Bogus/1 1"),
            v_int(5),
        ]);
        assert!(s.apply("Core.Supports.Set", &set));
        assert!(s.declared);
        assert_eq!(s.packages.get("char").map(|(_, version)| *version), Some(1));
        assert_eq!(s.packages.get("room").map(|(_, version)| *version), Some(2));
        assert_eq!(s.packages.get("bogus/1").map(|(_, version)| *version), None);
        // Applying the same set again is not a change.
        assert!(!s.apply("Core.Supports.Set", &set));

        assert!(s.apply("Core.Supports.Add", &v_list(&[v_str("Comm.Channel")])));
        assert_eq!(
            s.packages.get("comm.channel").map(|(_, version)| *version),
            Some(1)
        );

        assert!(s.apply("Core.Supports.Remove", &v_list(&[v_str("Room")])));
        assert_eq!(s.packages.get("room").map(|(_, version)| *version), None);

        // Set replaces.
        assert!(s.apply("Core.Supports.Set", &v_list(&[v_str("IRE.Rift 1")])));
        assert_eq!(s.packages.get("char").map(|(_, version)| *version), None);
        assert_eq!(s.to_var(), v_map(&[(v_str("IRE.Rift"), v_int(1))]));
        assert!(!s.apply("Core.Hello", &v_list(&[])));
    }

    #[test]
    fn supports_limit_allows_updates_and_reclaims_removed_entries() {
        let mut supports = GmcpSupports::default();
        let entries: Vec<_> = (0..MAX_SUPPORTED_PACKAGES)
            .map(|i| v_str(&format!("Package{i} 1")))
            .collect();
        assert!(supports.apply("Core.Supports.Set", &v_list(&entries)));
        assert!(!supports.apply("Core.Supports.Add", &v_list(&[v_str("Overflow 1")])));
        assert!(!supports.wants("Overflow"));
        assert!(supports.apply("Core.Supports.Add", &v_list(&[v_str("Package0 2")])));
        assert_eq!(supports.packages.get("package0").unwrap().1, 2);
        assert!(supports.apply("Core.Supports.Remove", &v_list(&[v_str("Package0")])));
        assert!(supports.apply("Core.Supports.Add", &v_list(&[v_str("Overflow 1")])));
        assert!(supports.wants("Overflow"));
        assert_eq!(supports.packages.len(), MAX_SUPPORTED_PACKAGES);
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
        assert!(s.declared);
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
