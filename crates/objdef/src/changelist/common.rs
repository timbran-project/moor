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

use super::*;

pub(super) fn prop_perms_summary(perms: &PropPerms) -> String {
    format!(
        "owner={};flags={}",
        perms.owner(),
        prop_flags_string(perms.flags())
    )
}

pub(super) fn verb_summary(verb: &VerbDef) -> String {
    format!(
        "names={:?};owner={};flags={};args={:?}",
        verb.names(),
        verb.owner(),
        verb_perms_string(verb.flags()),
        verb.args()
    )
}

pub(super) fn metadata_summary(
    metadata: Vec<(Symbol, Var)>,
    ignore_prefix: Option<&str>,
) -> String {
    let mut ordered = BTreeMap::new();
    for (key, value) in metadata {
        if let Some(prefix) = ignore_prefix
            && key.as_string().starts_with(prefix)
        {
            continue;
        }
        ordered.insert(key.as_string(), format!("{value:?}"));
    }
    format!("{ordered:?}")
}

pub(super) fn metadata_value(metadata: &[(Symbol, Var)], key: Symbol) -> Option<Var> {
    metadata
        .iter()
        .find_map(|(metadata_key, value)| (*metadata_key == key).then(|| value.clone()))
}

pub(super) fn stable_hash(kind: &str, value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(kind.as_bytes());
    hasher.update([0]);
    hasher.update(value.as_bytes());
    let digest = hasher.finalize();
    let mut output = String::with_capacity("sha256:".len() + digest.len() * 2);
    output.push_str("sha256:");
    for byte in digest {
        output.push_str(&format!("{byte:02x}"));
    }
    output
}

pub(super) fn str_key(value: &str) -> Var {
    moor_var::v_str(value)
}

pub(super) fn key_debug(key: &[Var]) -> String {
    format!("{key:?}")
}

pub(super) fn world_diagnostic(
    kind: &'static str,
    object: Option<Obj>,
    error: WorldStateError,
) -> ChangelistDiagnostic {
    ChangelistDiagnostic {
        kind,
        object,
        constant: None,
        message: error.to_string(),
    }
}
