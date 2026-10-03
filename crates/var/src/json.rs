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

//! Mapping between MOO values and JSON values.
//!
//! This is the one mapping used by `generate_json` / `parse_json` and by hosts that carry MOO
//! values over JSON-based protocols, so the two sides agree on how values look on the wire.
//!
//! Outbound (`var_to_json`):
//!
//! | MOO | JSON |
//! |---|---|
//! | INT | number |
//! | FLOAT (finite) | number |
//! | STR, SYM | string |
//! | BOOL | `true` / `false` |
//! | OBJ `#-1` | `null` |
//! | other OBJ | its literal form as a string (`"#42"`, `"#048D05-1234567890"`) |
//! | LIST | array |
//! | MAP with STR, SYM, INT, FLOAT or OBJ keys | object, keys rendered as strings |
//!
//! Everything else (ERR, BINARY, FLYWEIGHT, LAMBDA, NONE, non-finite FLOAT, other map key types)
//! is a [`JsonConversionError`].
//!
//! Inbound (`json_to_var`) is total: `null` becomes `#-1`, objects become maps with STR keys,
//! integers that fit in an `i64` become INT and every other number becomes FLOAT.

use crate::{
    Associative, NOTHING, Var, VarType, Variant, v_bool, v_bool_int, v_float, v_int, v_list, v_map,
    v_nothing, v_str,
};
use serde_json::Value;
use std::fmt::{Display, Formatter};

/// Why a MOO value could not be converted to JSON.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JsonConversionError {
    /// A value of this type has no JSON form.
    UnsupportedType(VarType),
    /// A map key of this type has no JSON object key form.
    UnsupportedKeyType(VarType),
    /// A NaN or infinite float, which JSON numbers cannot represent.
    NonFiniteFloat,
}

impl Display for JsonConversionError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            JsonConversionError::UnsupportedType(t) => {
                write!(
                    f,
                    "Cannot translate values of type {} to JSON",
                    t.to_literal()
                )
            }
            JsonConversionError::UnsupportedKeyType(t) => {
                write!(f, "Cannot use {} as a json map key", t.to_literal())
            }
            JsonConversionError::NonFiniteFloat => {
                write!(f, "Cannot translate a non-finite float to JSON")
            }
        }
    }
}

impl std::error::Error for JsonConversionError {}

/// Convert a MOO value to a JSON value, following the table in the module documentation.
pub fn var_to_json(v: &Var) -> Result<Value, JsonConversionError> {
    match v.variant() {
        Variant::Int(i) => Ok(Value::Number(i.into())),
        Variant::Float(f) => serde_json::Number::from_f64(f)
            .map(Value::Number)
            .ok_or(JsonConversionError::NonFiniteFloat),
        Variant::Str(s) => Ok(Value::String(s.as_str().to_string())),
        Variant::Sym(s) => Ok(Value::String(s.as_string())),
        Variant::Bool(b) => Ok(Value::Bool(b)),
        Variant::Obj(o) if o == NOTHING => Ok(Value::Null),
        Variant::Obj(o) => Ok(Value::String(format!("{o}"))),
        Variant::List(list) => {
            let items = list
                .iter()
                .map(|item| var_to_json(&item))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Value::Array(items))
        }
        Variant::Map(map) => {
            let mut object = serde_json::Map::with_capacity(map.len());
            for (k, v) in map.iter() {
                object.insert(map_key_to_string(&k)?, var_to_json(&v)?);
            }
            Ok(Value::Object(object))
        }
        _ => Err(JsonConversionError::UnsupportedType(v.type_code())),
    }
}

/// Render a map key as a JSON object key. JSON object keys are always strings.
fn map_key_to_string(k: &Var) -> Result<String, JsonConversionError> {
    match k.variant() {
        Variant::Str(s) => Ok(s.as_str().to_string()),
        Variant::Sym(s) => Ok(s.as_string()),
        Variant::Int(i) => Ok(i.to_string()),
        Variant::Float(f) => Ok(f.to_string()),
        Variant::Obj(o) => Ok(format!("{o}")),
        _ => Err(JsonConversionError::UnsupportedKeyType(k.type_code())),
    }
}

/// Convert a JSON value to a MOO value.
///
/// `use_boolean_returns` selects between BOOL values (`true`) and the integers 1/0 (`false`) for
/// JSON booleans, matching the server's `use_boolean_returns` feature.
pub fn json_to_var(j: &Value, use_boolean_returns: bool) -> Var {
    match j {
        Value::Null => v_nothing(),
        Value::Bool(b) if use_boolean_returns => v_bool(*b),
        Value::Bool(b) => v_bool_int(*b),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                return v_int(i);
            }
            // u64 beyond i64::MAX and non-integers. serde_json numbers are always finite f64s
            // when its arbitrary_precision feature is off, as it is in this workspace.
            v_float(
                n.as_f64()
                    .expect("serde_json number without arbitrary_precision is an f64"),
            )
        }
        Value::String(s) => v_str(s),
        Value::Array(arr) => {
            let items: Vec<Var> = arr
                .iter()
                .map(|item| json_to_var(item, use_boolean_returns))
                .collect();
            v_list(&items)
        }
        Value::Object(obj) => {
            let pairs: Vec<(Var, Var)> = obj
                .iter()
                .map(|(k, v)| (v_str(k), json_to_var(v, use_boolean_returns)))
                .collect();
            v_map(&pairs)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        E_PERM, List, Obj, UuObjid,
        program::{labels::Label, opcode::ScatterArgs, program::Program},
        v_binary, v_err, v_flyweight, v_none, v_objid, v_sym,
    };
    use serde_json::json;

    #[test]
    fn int_to_json() {
        assert_eq!(var_to_json(&v_int(42)).unwrap(), json!(42));
        assert_eq!(var_to_json(&v_int(-7)).unwrap(), json!(-7));
        assert_eq!(var_to_json(&v_int(i64::MAX)).unwrap(), json!(i64::MAX));
    }

    #[test]
    fn finite_float_to_json() {
        assert_eq!(var_to_json(&v_float(1.5)).unwrap(), json!(1.5));
        assert_eq!(var_to_json(&v_float(-0.25)).unwrap(), json!(-0.25));
    }

    #[test]
    fn non_finite_float_is_an_error() {
        for f in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert_eq!(
                var_to_json(&Var::mk_float_unchecked(f)),
                Err(JsonConversionError::NonFiniteFloat)
            );
        }
        // Nested inside a container too.
        assert_eq!(
            var_to_json(&v_list(&[v_int(1), Var::mk_float_unchecked(f64::NAN)])),
            Err(JsonConversionError::NonFiniteFloat)
        );
    }

    #[test]
    fn str_to_json() {
        assert_eq!(var_to_json(&v_str("hello")).unwrap(), json!("hello"));
        assert_eq!(var_to_json(&v_str("")).unwrap(), json!(""));
    }

    #[test]
    fn sym_to_json_is_a_string() {
        assert_eq!(var_to_json(&v_sym("gmcp")).unwrap(), json!("gmcp"));
    }

    #[test]
    fn bool_to_json() {
        assert_eq!(var_to_json(&v_bool(true)).unwrap(), json!(true));
        assert_eq!(var_to_json(&v_bool(false)).unwrap(), json!(false));
    }

    #[test]
    fn nothing_to_null() {
        assert_eq!(var_to_json(&v_nothing()).unwrap(), Value::Null);
    }

    #[test]
    fn objects_to_literal_strings() {
        assert_eq!(var_to_json(&v_objid(42)).unwrap(), json!("#42"));
        assert_eq!(var_to_json(&v_objid(0)).unwrap(), json!("#0"));
        let uuid = Var::from(Obj::mk_uuobjid(UuObjid::new(0x1234, 0x5, 0x1234567890)));
        assert_eq!(var_to_json(&uuid).unwrap(), json!("#048D05-1234567890"));
    }

    #[test]
    fn list_to_array() {
        assert_eq!(var_to_json(&v_list(&[])).unwrap(), json!([]));
        let l = v_list(&[v_int(1), v_str("two"), v_sym("three"), v_nothing()]);
        assert_eq!(var_to_json(&l).unwrap(), json!([1, "two", "three", null]));
    }

    #[test]
    fn map_keys_render_as_strings() {
        let uuid = Var::from(Obj::mk_uuobjid(UuObjid::new(0x1234, 0x5, 0x1234567890)));
        let m = v_map(&[
            (v_str("s"), v_int(1)),
            (v_sym("y"), v_int(2)),
            (v_int(3), v_int(3)),
            (v_float(4.5), v_int(4)),
            (v_objid(42), v_str("regular")),
            (uuid, v_str("uuid")),
        ]);
        assert_eq!(
            var_to_json(&m).unwrap(),
            json!({
                "s": 1,
                "y": 2,
                "3": 3,
                "4.5": 4,
                "#42": "regular",
                "#048D05-1234567890": "uuid",
            })
        );
    }

    #[test]
    fn sym_map_values() {
        let m = v_map(&[(v_sym("kind"), v_sym("vitals"))]);
        assert_eq!(var_to_json(&m).unwrap(), json!({"kind": "vitals"}));
    }

    #[test]
    fn nested_structures_to_json() {
        let v = v_map(&[
            (
                v_str("list"),
                v_list(&[v_int(1), v_list(&[v_bool(true), v_nothing()])]),
            ),
            (
                v_str("map"),
                v_map(&[(v_sym("inner"), v_map(&[(v_int(1), v_float(2.5))]))]),
            ),
        ]);
        assert_eq!(
            var_to_json(&v).unwrap(),
            json!({
                "list": [1, [true, null]],
                "map": {"inner": {"1": 2.5}},
            })
        );
    }

    #[test]
    fn unsupported_value_types() {
        let lambda = Var::mk_lambda(
            ScatterArgs {
                labels: vec![],
                done: Label(0),
            },
            Program::new(),
            vec![],
            None,
        );
        let cases = [
            (v_err(E_PERM), VarType::TYPE_ERR),
            (v_binary(vec![1, 2, 3]), VarType::TYPE_BINARY),
            (
                v_flyweight(Obj::mk_id(1), &[], List::mk_list(&[])),
                VarType::TYPE_FLYWEIGHT,
            ),
            (lambda, VarType::TYPE_LAMBDA),
            (v_none(), VarType::TYPE_NONE),
        ];
        for (v, t) in cases {
            assert_eq!(
                var_to_json(&v),
                Err(JsonConversionError::UnsupportedType(t))
            );
        }
        // Inside a container the error still surfaces.
        assert_eq!(
            var_to_json(&v_map(&[(v_str("e"), v_err(E_PERM))])),
            Err(JsonConversionError::UnsupportedType(VarType::TYPE_ERR))
        );
    }

    #[test]
    fn unsupported_map_key_types() {
        let cases = [
            (v_list(&[v_int(1)]), VarType::TYPE_LIST),
            (v_bool(true), VarType::TYPE_BOOL),
            (v_err(E_PERM), VarType::TYPE_ERR),
        ];
        for (k, t) in cases {
            let m = v_map(&[(k, v_int(1))]);
            assert_eq!(
                var_to_json(&m),
                Err(JsonConversionError::UnsupportedKeyType(t))
            );
        }
    }

    #[test]
    fn error_messages_name_the_type() {
        assert_eq!(
            JsonConversionError::UnsupportedType(VarType::TYPE_ERR).to_string(),
            "Cannot translate values of type TYPE_ERR to JSON"
        );
        assert_eq!(
            JsonConversionError::UnsupportedKeyType(VarType::TYPE_LIST).to_string(),
            "Cannot use TYPE_LIST as a json map key"
        );
        assert!(
            JsonConversionError::NonFiniteFloat
                .to_string()
                .contains("non-finite")
        );
    }

    #[test]
    fn json_scalars_to_var() {
        assert_eq!(json_to_var(&Value::Null, false), v_nothing());
        assert_eq!(json_to_var(&json!(42), false), v_int(42));
        assert_eq!(json_to_var(&json!(-42), false), v_int(-42));
        assert_eq!(json_to_var(&json!(1.5), false), v_float(1.5));
        assert_eq!(json_to_var(&json!("hi"), false), v_str("hi"));
        // A string that looks like an object stays a string.
        assert_eq!(json_to_var(&json!("#42"), false), v_str("#42"));
    }

    #[test]
    fn json_u64_beyond_i64_becomes_float() {
        let big = json!(u64::MAX);
        assert_eq!(json_to_var(&big, false), v_float(u64::MAX as f64));
    }

    #[test]
    fn json_booleans_follow_use_boolean_returns() {
        assert_eq!(json_to_var(&json!(true), true), v_bool(true));
        assert_eq!(json_to_var(&json!(false), true), v_bool(false));
        assert_eq!(json_to_var(&json!(true), false), v_int(1));
        assert_eq!(json_to_var(&json!(false), false), v_int(0));
        // And the choice propagates into containers.
        assert_eq!(
            json_to_var(&json!([true, {"b": false}]), true),
            v_list(&[v_bool(true), v_map(&[(v_str("b"), v_bool(false))])])
        );
        assert_eq!(
            json_to_var(&json!([true, {"b": false}]), false),
            v_list(&[v_int(1), v_map(&[(v_str("b"), v_int(0))])])
        );
    }

    #[test]
    fn json_containers_to_var() {
        let v = json_to_var(&json!({"a": [1, null, "x"], "b": {"c": 2.5}}), false);
        let m = v.as_map().unwrap();
        assert_eq!(
            m.get(&v_str("a")).unwrap(),
            v_list(&[v_int(1), v_nothing(), v_str("x")])
        );
        assert_eq!(
            m.get(&v_str("b")).unwrap(),
            v_map(&[(v_str("c"), v_float(2.5))])
        );
        assert_eq!(json_to_var(&json!([]), false), v_list(&[]));
        assert_eq!(json_to_var(&json!({}), false), v_map(&[]));
    }

    #[test]
    fn null_round_trip() {
        let nothing = json_to_var(&Value::Null, false);
        assert_eq!(nothing, v_nothing());
        assert_eq!(var_to_json(&nothing).unwrap(), Value::Null);

        let j = json!({
            "field": null,
            "array": [1, null, "null", "#-1"],
        });
        assert_eq!(var_to_json(&json_to_var(&j, false)).unwrap(), j);
    }

    #[test]
    fn round_trip_with_booleans() {
        let j = json!({"on": true, "off": false, "n": [1, 2.5, "s"]});
        assert_eq!(var_to_json(&json_to_var(&j, true)).unwrap(), j);
    }
}
