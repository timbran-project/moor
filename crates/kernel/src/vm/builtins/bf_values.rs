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

//! Builtin functions for value inspection, conversion, and manipulation.

use crate::{
    task_context::with_current_transaction,
    vm::builtins::{
        BfCallState, BfErr, BfRet, BfRet::Ret, BuiltinFunction, hash, world_state_bf_err,
    },
};
use moor_common::util::write_i64_decimal;
use moor_compiler::{ObjDefParseError, offset_for_builtin, parse_literal_value, to_literal};
use moor_var::{
    ByteSized, E_ARGS, E_FLOAT, E_INVARG, E_MAXREC, E_RANGE, E_TYPE, ValueDiffOptions, Var,
    Variant, decode_var_cbor, encode_var_cbor, v_binary, v_err, v_float, v_int, v_list_iter, v_obj,
    v_objid, v_str, v_string, v_sym, value_diff, value_diff3,
};
use std::fmt::Write;
use uuid::Uuid;

/// Usage: `int typeof(any value)`
/// Returns an integer representing the type code of the given value. Type codes are:
/// 0=INT, 1=OBJ, 2=STR, 3=ERR, 4=LIST, 5=NONE/CLEAR, 6=CATCH, 7=FINALLY, 9=FLOAT.
fn bf_typeof(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    let arg = &bf_args.args[0];
    Ok(Ret(v_int(arg.type_code() as i64)))
}

/// Usage: `str tostr(any ...)`
/// Converts each argument to a string representation and concatenates them all together.
/// Integers are formatted as decimal numbers, floats with decimal notation, objects as "#N",
/// errors as their name (e.g., "E_PERM"), and lists/maps as "{list}" or "[map]".
fn bf_tostr(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() == 1 && matches!(bf_args.args[0].variant(), Variant::Str(_)) {
        return Ok(Ret(bf_args.args[0].clone()));
    }

    let mut result = String::with_capacity(bf_args.args.len().saturating_mul(16));
    for arg in bf_args.args.iter() {
        match arg.variant() {
            Variant::None => result.push_str("None"),
            Variant::Bool(true) => result.push_str("true"),
            Variant::Bool(false) => result.push_str("false"),
            Variant::Int(i) => {
                let _ = write_i64_decimal(&mut result, i);
            }
            Variant::Float(f) => {
                let _ = write!(result, "{f:?}");
            }
            Variant::Str(s) => result.push_str(s.as_str()),
            Variant::Binary(b) => {
                result.push_str("<binary ");
                let _ = write_i64_decimal(&mut result, b.len() as i64);
                result.push_str(" bytes>");
            }
            Variant::Obj(o) => {
                if o.is_oid() {
                    result.push('#');
                    let _ = write_i64_decimal(&mut result, o.id().0 as i64);
                } else {
                    let _ = write!(result, "{o}");
                }
            }
            Variant::List(_) => result.push_str("{list}"),
            Variant::Map(_) => result.push_str("[map]"),
            Variant::Sym(s) => {
                result.push_str(s.as_str());
            }
            Variant::Err(e) => result.push_str(e.name().as_str()),
            Variant::Flyweight(_) => result.push_str("<flyweight>"),
            Variant::Lambda(l) => {
                use moor_var::program::opcode::ScatterLabel;
                result.push_str("<lambda:(");
                let mut first = true;
                for label in l.0.params.labels.iter() {
                    if !first {
                        result.push_str(", ");
                    }
                    first = false;
                    match label {
                        ScatterLabel::Required(_) => result.push('x'),
                        ScatterLabel::Optional(_, _) => result.push_str("?x"),
                        ScatterLabel::Rest(_) => result.push_str("@x"),
                    }
                }
                result.push_str(")>");
            }
        }
    }
    Ok(Ret(v_string(result)))
}

/// Usage: `symbol tosym(str|bool|error|symbol value)`
/// Converts scalar values to symbols.
fn bf_tosym(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    // Convert scalar values to symbols.
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("tosym() requires exactly 1 argument"),
        ));
    }

    match bf_args.args[0].variant() {
        Variant::Bool(b) => {
            let s = format!("{b}");
            Ok(Ret(v_sym(s.as_str())))
        }
        Variant::Str(s) => Ok(Ret(v_sym(s.as_str()))),
        Variant::Err(e) => Ok(Ret(v_sym(e.name()))),
        Variant::Sym(s) => Ok(Ret(v_sym(s))),
        _ => Err(BfErr::ErrValue(E_TYPE.msg(
            "tosym() requires a string, boolean, error, or symbol argument",
        ))),
    }
}

/// Usage: `str toliteral(any value)`
/// Returns a string containing the MOO literal representation of the value. The result can
/// be evaluated to recreate the original value. Raises E_INVARG for closures with captures.
fn bf_toliteral(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("toliteral() requires exactly 1 argument"),
        ));
    }

    // Check if this is a lambda with captures - if so, raise an error
    if let Some(lambda) = bf_args.args[0].as_lambda()
        && !lambda.0.captured_env.is_empty()
    {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("Cannot convert closure with captured variables to literal"),
        ));
    }

    let literal = to_literal(&bf_args.args[0]);
    Ok(Ret(v_string(literal)))
}

/// Usage: `any fromliteral(str literal)`
/// Parses a single MOO literal value from a string without evaluating code.
fn bf_fromliteral(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("fromliteral() requires exactly 1 argument"),
        ));
    }

    let Some(literal) = bf_args.args[0].as_string() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("fromliteral() requires a string argument"),
        ));
    };

    let value = match parse_literal_value(literal) {
        Ok(value) => value,
        Err(ObjDefParseError::LiteralNestingTooDeep { max_depth }) => {
            return Err(BfErr::ErrValue(E_MAXREC.msg(format!(
                "literal nesting exceeds maximum depth of {max_depth}"
            ))));
        }
        Err(err) => {
            return Err(BfErr::ErrValue(
                E_INVARG.with_msg(|| format!("invalid literal: {err}")),
            ));
        }
    };
    Ok(Ret(value))
}

/// Mirrors LambdaMOO's `inrange_for_float_to_int`: a float converts to an integer
/// when truncation toward zero lands inside the integer range.
fn float_to_int_in_range(f: f64) -> bool {
    const MIN: f64 = i64::MIN as f64; // -2^63, exactly representable
    const MAX_EXCLUSIVE: f64 = 9223372036854775808.0; // 2^63
    f.ceil() >= MIN && f < MAX_EXCLUSIVE
}

/// Usage: `int toint(int|float|obj|str|error value)`
/// Converts a value to an integer. Floats are truncated toward zero and raise
/// `E_FLOAT` when out of integer range; objects return their ID number; strings
/// are parsed as numbers (invalid or unrepresentable strings return 0); errors
/// return their code. Raises `E_INVARG` for UUID objects and `E_TYPE` for
/// unconvertible types.
fn bf_toint(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("toint() requires exactly 1 argument"),
        ));
    }
    match bf_args.args[0].variant() {
        Variant::Bool(b) => Ok(Ret(v_int(if b { 1 } else { 0 }))),
        Variant::Int(i) => Ok(Ret(v_int(i))),
        Variant::Float(f) => {
            if !float_to_int_in_range(f) {
                return Err(BfErr::ErrValue(
                    E_FLOAT.msg("float is out of range for an integer"),
                ));
            }
            Ok(Ret(v_int(f as i64)))
        }
        Variant::Obj(o) => {
            if o.is_uuobjid() {
                Err(BfErr::ErrValue(
                    E_INVARG.msg("cannot convert UUID Objects to integer"),
                ))
            } else {
                Ok(Ret(v_int(o.id().0 as i64)))
            }
        }
        Variant::Str(s) => {
            let s = s.as_str().trim();
            if let Ok(i) = s.parse::<i64>() {
                return Ok(Ret(v_int(i)));
            }
            // Strings denoting non-integer numbers truncate toward zero, matching
            // toint(tofloat(s)); unparseable or unrepresentable strings give 0.
            let Ok(f) = s.parse::<f64>() else {
                return Ok(Ret(v_int(0)));
            };
            if !float_to_int_in_range(f) {
                return Ok(Ret(v_int(0)));
            }
            Ok(Ret(v_int(f as i64)))
        }
        Variant::Err(e) => {
            let Some(v) = e.to_int() else {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("cannot convert this error to integer"),
                ));
            };

            Ok(Ret(v_int(v as i64)))
        }
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg("cannot convert this type to integer"),
        )),
    }
}

/// Usage: `bool tobool(any value)`
/// Converts a value to its truthiness equivalent. Empty lists/strings/binaries, zero numbers, and nullish
/// values convert to false; everything else converts to true.
fn bf_tobool(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("tobool() requires exactly 1 argument"),
        ));
    }

    let truthy = bf_args.args[0].is_true();
    Ok(Ret(bf_args.v_bool(truthy)))
}

/// Usage: `obj toobj(int|float|str|obj value)`
/// Converts a value to an object reference. Strings accept formats like "123" or "#123".
/// Invalid strings return #0. Raises E_RANGE for integers outside the valid object ID
/// range, E_FLOAT for floats outside it, and E_TYPE for unconvertible types.
fn bf_toobj(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("toobj() requires exactly 1 argument"),
        ));
    }
    match bf_args.args[0].variant() {
        Variant::Bool(b) => Ok(Ret(v_objid(if b { 1 } else { 0 }))),
        Variant::Int(i) => {
            let i = if i < i32::MIN as i64 || i > i32::MAX as i64 {
                return Err(BfErr::ErrValue(
                    E_RANGE.msg("integer value outside valid object ID range"),
                ));
            } else {
                i as i32
            };
            Ok(Ret(v_objid(i)))
        }
        Variant::Float(f) => {
            // Truncation toward zero must land inside the object number range;
            // as in LambdaMOO's float-to-integer conversion, a float outside it
            // raises E_FLOAT.
            const MIN: f64 = i32::MIN as f64; // -2^31, exactly representable
            const MAX_EXCLUSIVE: f64 = 2147483648.0; // 2^31
            if f.ceil() < MIN || f >= MAX_EXCLUSIVE {
                return Err(BfErr::ErrValue(
                    E_FLOAT.msg("float value out of range for an object number"),
                ));
            }
            Ok(Ret(v_objid(f as i32)))
        }
        Variant::Str(s) if s.as_str().starts_with('#') => {
            match moor_var::Obj::try_from(s.as_str()) {
                Ok(obj) => Ok(Ret(v_obj(obj))),
                Err(_) => Ok(Ret(v_objid(0))),
            }
        }
        Variant::Str(s) => {
            let i = s.as_str().trim().parse::<i32>();
            match i {
                Ok(i) => Ok(Ret(v_objid(i))),
                Err(_) => Ok(Ret(v_objid(0))),
            }
        }
        Variant::Obj(o) => Ok(Ret(v_obj(o))),
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg("cannot convert this type to object"),
        )),
    }
}

/// Usage: `float tofloat(int|float|obj|str|error value)`
/// Converts a value to a floating-point number. Strings must contain a real
/// number: unparseable strings, "nan"/"inf", and values that overflow raise
/// `E_INVARG`, as MOO floats are always finite. Errors return their code as a
/// float. Raises `E_TYPE` for unconvertible types.
fn bf_tofloat(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("tofloat() requires exactly 1 argument"),
        ));
    }
    match bf_args.args[0].variant() {
        Variant::Bool(b) => Ok(Ret(v_float(if b { 1.0 } else { 0.0 }))),
        Variant::Int(i) => Ok(Ret(v_float(i as f64))),
        Variant::Float(f) => Ok(Ret(v_float(f))),
        Variant::Obj(o) => {
            if o.is_uuobjid() {
                Err(BfErr::ErrValue(
                    E_INVARG.msg("cannot convert UUID Objects to float"),
                ))
            } else {
                Ok(Ret(v_float(o.id().0 as f64)))
            }
        }
        Variant::Str(s) => {
            // As in LambdaMOO: the string must parse to a real number. Rust's
            // float parser accepts "nan"/"inf" and overflow to infinity, none of
            // which are representable MOO floats.
            match s.as_str().trim().parse::<f64>() {
                Ok(f) if f.is_finite() => Ok(Ret(v_float(f))),
                _ => Err(BfErr::ErrValue(
                    E_INVARG.msg("string does not contain a real number"),
                )),
            }
        }

        Variant::Err(e) => {
            let Some(v) = e.to_int() else {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("cannot convert this error to float"),
                ));
            };

            Ok(Ret(v_float(v as f64)))
        }
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg("cannot convert this type to float"),
        )),
    }
}

/// Usage: `bool equal(any a, any b)`
/// Performs a case-sensitive equality comparison between two values. Unlike the == operator,
/// string comparisons are case-sensitive.
fn bf_equal(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("equal() requires exactly 2 arguments"),
        ));
    }
    let (a1, a2) = (&bf_args.args[0], &bf_args.args[1]);
    let result = a1.eq_case_sensitive(a2);
    Ok(Ret(bf_args.v_bool(result)))
}

/// Usage: `int value_bytes(any value)`
/// Returns the number of bytes used to store the value in memory.
fn bf_value_bytes(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("value_bytes() requires exactly 1 argument"),
        ));
    }
    let count = bf_args.args[0].size_bytes();
    Ok(Ret(v_int(count as i64)))
}

/// Usage: `str value_hash(any value [, str algorithm [, bool binary]])`
/// Returns a hash of the value's canonical CBOR representation.
fn bf_value_hash(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() || bf_args.args.len() > 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("value_hash() requires 1 to 3 arguments"),
        ));
    }

    let algo = if bf_args.args.len() > 1 {
        hash::hash_algorithm_arg(&bf_args.args[1])?
    } else {
        "sha256".to_string()
    };
    let binary = bf_args.args.len() > 2 && bf_args.args[2].is_true();
    let bytes = encode_var_cbor(&bf_args.args[0])
        .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))?;
    let digest = hash::hash_bytes(&algo, &bytes)?;
    Ok(Ret(hash::hash_output(digest, binary)))
}

fn parse_value_diff_options(value: Option<&moor_var::Var>) -> Result<ValueDiffOptions, BfErr> {
    let mut options = ValueDiffOptions::default();
    let Some(value) = value else {
        return Ok(options);
    };
    let Some(map) = value.as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("value_diff() options must be a map"),
        ));
    };

    for (key, value) in map.iter() {
        let key = match key.variant() {
            Variant::Str(s) => s.as_str().to_string(),
            Variant::Sym(s) => s.as_str().to_string(),
            _ => {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("value_diff() option keys must be strings or symbols"),
                ));
            }
        };

        match key.as_str() {
            "max_depth" => options.max_depth = nonnegative_usize_option(&value, &key)?,
            "max_changes" => options.max_changes = positive_usize_option(&value, &key)?,
            "max_lcs_cells" => options.max_lcs_cells = nonnegative_usize_option(&value, &key)?,
            "include_values" => options.include_values = value.is_true(),
            _ => {
                return Err(BfErr::ErrValue(
                    E_INVARG.with_msg(|| format!("unknown value_diff() option: {key}")),
                ));
            }
        }
    }

    Ok(options)
}

fn nonnegative_usize_option(value: &moor_var::Var, name: &str) -> Result<usize, BfErr> {
    let Some(value) = value.as_integer() else {
        return Err(BfErr::ErrValue(
            E_TYPE.with_msg(|| format!("{name} must be an integer")),
        ));
    };
    usize::try_from(value)
        .map_err(|_| BfErr::ErrValue(E_RANGE.with_msg(|| format!("{name} must be non-negative"))))
}

fn positive_usize_option(value: &moor_var::Var, name: &str) -> Result<usize, BfErr> {
    let value = nonnegative_usize_option(value, name)?;
    if value == 0 {
        return Err(BfErr::ErrValue(
            E_RANGE.with_msg(|| format!("{name} must be positive")),
        ));
    }
    Ok(value)
}

/// Usage: `map value_diff(any old, any new [, map options])`
/// Returns a bounded structural diff between two values.
fn bf_value_diff(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 2 || bf_args.args.len() > 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("value_diff() requires 2 to 3 arguments"),
        ));
    }

    let options = parse_value_diff_options(bf_args.args.iter_ref().nth(2))?;
    Ok(Ret(value_diff(
        &bf_args.args[0],
        &bf_args.args[1],
        &options,
    )))
}

/// Usage: `map value_diff3(any base, any local, any incoming [, map options])`
/// Returns bounded structural diffs for a three-way comparison.
fn bf_value_diff3(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 3 || bf_args.args.len() > 4 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("value_diff3() requires 3 to 4 arguments"),
        ));
    }

    let options = parse_value_diff_options(bf_args.args.iter_ref().nth(3))?;
    Ok(Ret(value_diff3(
        &bf_args.args[0],
        &bf_args.args[1],
        &bf_args.args[2],
        &options,
    )))
}

/// Usage: `binary encode_cbor(any value)`
/// Encodes a value as mooR's canonical CBOR representation.
fn bf_encode_cbor(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("encode_cbor() requires exactly 1 argument"),
        ));
    }

    let bytes = encode_var_cbor(&bf_args.args[0])
        .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))?;
    Ok(Ret(v_binary(bytes)))
}

/// Usage: `any decode_cbor(binary value)`
/// Decodes a value from mooR's canonical CBOR representation.
fn bf_decode_cbor(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("decode_cbor() requires exactly 1 argument"),
        ));
    }

    let Variant::Binary(bytes) = bf_args.args[0].variant() else {
        return Err(BfErr::Code(E_INVARG));
    };
    let value = decode_var_cbor(bytes.as_bytes())
        .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))?;
    Ok(Ret(value))
}

/// Usage: `int length(list|map|str|binary value)`
/// Returns the length of a sequence: number of elements for lists and maps, number of
/// characters for strings, number of bytes for binary. Raises E_TYPE for non-sequences.
fn bf_length(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("length() requires exactly 1 argument"),
        ));
    }

    match bf_args.args[0].len() {
        Ok(l) => Ok(Ret(v_int(l as i64))),
        Err(e) => Err(BfErr::ErrValue(e)),
    }
}

/// Usage: `int object_bytes(obj o)`
/// Returns the number of bytes used to store the object in the database, including all
/// properties, verbs, and other object data.
fn bf_object_bytes(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("object_bytes() requires exactly 1 argument"),
        ));
    }
    let Some(o) = bf_args.args[0].as_object() else {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("object_bytes() requires an object argument"),
        ));
    };
    if !with_current_transaction(|world_state| world_state.valid(&o)).map_err(world_state_bf_err)? {
        return Err(BfErr::ErrValue(E_INVARG.msg("object is not valid")));
    };
    let size = with_current_transaction(|world_state| {
        world_state.object_bytes(&bf_args.task_permissions(), &o)
    })
    .map_err(world_state_bf_err)?;
    Ok(Ret(v_int(size as i64)))
}

/// Usage: `error error_code(error e)`
/// Returns the base error type from an error value, stripping off any attached message
/// or value. E.g., error_code(E_PERM.msg("denied")) returns E_PERM.
fn bf_error_code(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("error_code() takes one argument"),
        ));
    }
    let Some(e) = bf_args.args[0].as_error() else {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("error_code() takes an error object"),
        ));
    };
    let code = e.err_type();
    Ok(Ret(v_err(code)))
}

/// Usage: `str error_message(error e)`
/// Returns the message string attached to an error value. Returns the default message
/// if no custom message was attached.
fn bf_error_message(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("error_message() takes one argument"),
        ));
    }
    let Some(e) = bf_args.args[0].as_error() else {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("error_message() takes an error object"),
        ));
    };
    let msg = e.message();
    Ok(Ret(v_str(msg.as_str())))
}

/// Usage: `str uuid([int high, int low])`
/// With no arguments, generates a new time-ordered v7 UUID. With two integer arguments,
/// reconstructs a UUID from its high and low 64-bit components (big-endian).
/// Raises E_ARGS if the argument count is not 0 or 2, and E_TYPE if either argument
/// is not an integer.
fn bf_uuid(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    match bf_args.args.len() {
        0 => {
            // Generate a new v7 UUID
            let uuid = Uuid::now_v7();
            Ok(Ret(v_str(uuid.to_string().as_str())))
        }
        2 => {
            // Reconstruct UUID from two i64 values (big-endian)
            let Some(high) = bf_args.args[0].as_integer() else {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("uuid() requires integer arguments"),
                ));
            };
            let Some(low) = bf_args.args[1].as_integer() else {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("uuid() requires integer arguments"),
                ));
            };

            // Convert i64 to u64 for bit manipulation
            let high_u64 = high as u64;
            let low_u64 = low as u64;

            // Construct the 128-bit UUID bytes (big-endian)
            let mut bytes = [0u8; 16];
            bytes[0..8].copy_from_slice(&high_u64.to_be_bytes());
            bytes[8..16].copy_from_slice(&low_u64.to_be_bytes());

            let uuid = Uuid::from_bytes(bytes);
            Ok(Ret(v_str(uuid.to_string().as_str())))
        }
        _ => Err(BfErr::ErrValue(E_ARGS.msg("uuid() takes 0 or 2 arguments"))),
    }
}

/// Entries packed, unpacked or changed per tick charged by the packed-field builtins.
const PACKED_ENTRIES_PER_TICK: usize = 256;

/// The widest packed field, in bits.
const MAX_PACKED_WIDTH: i64 = 32;

/// Packed fields: unsigned integers of `width` bits laid end to end in one bit stream, entry `i`
/// (from 0) at bits `i * width` to `i * width + width - 1`. Bit `k` of the stream is bit `k % 8` of
/// byte `k / 8`, and each value's lowest bit comes first. Entries may span bytes.
fn packed_width(arg: &Var, name: &str) -> Result<usize, BfErr> {
    let Some(width) = arg.as_integer() else {
        return Err(BfErr::Code(E_TYPE));
    };
    if !(1..=MAX_PACKED_WIDTH).contains(&width) {
        return Err(BfErr::ErrValue(E_INVARG.msg(format!(
            "{name}() width must be from 1 to {MAX_PACKED_WIDTH}"
        ))));
    }
    Ok(width as usize)
}

fn packed_entries(bytes: &[u8], width: usize) -> usize {
    bytes.len() * 8 / width
}

fn packed_get(bytes: &[u8], width: usize, entry: usize) -> u64 {
    let bit = entry * width;
    let first = bit / 8;
    let last = (bit + width - 1) / 8;
    let mut word = 0u64;
    for (i, byte) in bytes[first..=last].iter().enumerate() {
        word |= u64::from(*byte) << (i * 8);
    }
    (word >> (bit % 8)) & ((1u64 << width) - 1)
}

fn packed_set(bytes: &mut [u8], width: usize, entry: usize, value: u64) {
    let bit = entry * width;
    let shift = bit % 8;
    let first = bit / 8;
    let last = (bit + width - 1) / 8;
    let mask = ((1u64 << width) - 1) << shift;
    let value = value << shift;
    for (i, byte) in bytes[first..=last].iter_mut().enumerate() {
        let byte_mask = (mask >> (i * 8)) as u8;
        *byte = (*byte & !byte_mask) | ((value >> (i * 8)) as u8 & byte_mask);
    }
}

/// A value to store in a packed field, checked against the width.
fn packed_value(value: &Var, width: usize, name: &str) -> Result<u64, BfErr> {
    let Some(value) = value.as_integer() else {
        return Err(BfErr::Code(E_TYPE));
    };
    if value < 0 || value >= 1i64 << width {
        return Err(BfErr::ErrValue(E_INVARG.msg(format!(
            "{name}() value {value} does not fit in {width} bits"
        ))));
    }
    Ok(value as u64)
}

/// A 1-based entry index, as a 0-based one.
fn packed_index(index: &Var, entries: usize, name: &str) -> Result<usize, BfErr> {
    let Some(index) = index.as_integer() else {
        return Err(BfErr::Code(E_TYPE));
    };
    if index < 1 || index as u64 > entries as u64 {
        return Err(BfErr::ErrValue(
            E_RANGE.msg(format!("{name}() index {index} is outside 1 to {entries}")),
        ));
    }
    Ok(index as usize - 1)
}

fn packed_ticks(bf_args: &mut BfCallState<'_>, entries: usize) -> Result<(), BfErr> {
    bf_args
        .tick_budget()
        .consume_ticks(entries / PACKED_ENTRIES_PER_TICK)
}

/// Usage: `binary binary_pack(list values, int width)`
/// Packs non-negative integers into a binary value, `width` bits each, end to end. The result is
/// as many bytes as the values need, with any unused bits of the last byte zero.
fn bf_binary_pack(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("binary_pack() requires exactly 2 arguments"),
        ));
    }
    let width = packed_width(&bf_args.args[1], "binary_pack")?;
    let Some(values) = bf_args.args[0].as_list() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let mut bytes = vec![0u8; (values.len() * width).div_ceil(8)];
    for (entry, value) in values.iter().enumerate() {
        packed_set(
            &mut bytes,
            width,
            entry,
            packed_value(&value, width, "binary_pack")?,
        );
    }
    let entries = values.len();
    packed_ticks(bf_args, entries)?;
    Ok(Ret(v_binary(bytes)))
}

/// Usage: `list binary_unpack(binary data, int width [, int start [, int count]])`
/// Reads `count` packed fields of `width` bits from `data`, starting at entry `start` (default
/// 1). By default it reads every whole entry from `start` to the end.
fn bf_binary_unpack(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 2 || bf_args.args.len() > 4 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("binary_unpack() takes 2 to 4 arguments"),
        ));
    }
    let width = packed_width(&bf_args.args[1], "binary_unpack")?;
    let Variant::Binary(data) = bf_args.args[0].variant() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let bytes = data.as_bytes();
    let entries = packed_entries(bytes, width);
    let start = match bf_args.args.iter_ref().nth(2) {
        None => 1,
        Some(start) => start.as_integer().ok_or(BfErr::Code(E_TYPE))?,
    };
    let count = match bf_args.args.iter_ref().nth(3) {
        None => entries as i64 - start + 1,
        Some(count) => count.as_integer().ok_or(BfErr::Code(E_TYPE))?,
    };
    if start < 1 || count < 0 || (start - 1).saturating_add(count) > entries as i64 {
        return Err(BfErr::ErrValue(E_RANGE.msg(format!(
            "binary_unpack() entries {start} to {} are outside 1 to {entries}",
            start.saturating_add(count) - 1
        ))));
    }
    let first = start as usize - 1;
    let values: Vec<Var> = (first..first + count as usize)
        .map(|entry| v_int(packed_get(bytes, width, entry) as i64))
        .collect();
    packed_ticks(bf_args, values.len())?;
    Ok(Ret(v_list_iter(values)))
}

/// Usage: `int binary_field(binary data, int width, int index)`
/// Returns entry `index` of the packed fields of `width` bits in `data`.
fn bf_binary_field(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("binary_field() requires exactly 3 arguments"),
        ));
    }
    let width = packed_width(&bf_args.args[1], "binary_field")?;
    let Variant::Binary(data) = bf_args.args[0].variant() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let bytes = data.as_bytes();
    let entry = packed_index(
        &bf_args.args[2],
        packed_entries(bytes, width),
        "binary_field",
    )?;
    Ok(Ret(v_int(packed_get(bytes, width, entry) as i64)))
}

/// Usage: `binary binary_set_field(binary data, int width, int index, int value)`
/// Returns a copy of `data` with entry `index` of its packed fields of `width` bits set to
/// `value`.
fn bf_binary_set_field(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 4 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("binary_set_field() requires exactly 4 arguments"),
        ));
    }
    let width = packed_width(&bf_args.args[1], "binary_set_field")?;
    let Variant::Binary(data) = bf_args.args[0].variant() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let mut bytes = data.as_bytes().to_vec();
    let entry = packed_index(
        &bf_args.args[2],
        packed_entries(&bytes, width),
        "binary_set_field",
    )?;
    let value = packed_value(&bf_args.args[3], width, "binary_set_field")?;
    packed_set(&mut bytes, width, entry, value);
    Ok(Ret(v_binary(bytes)))
}

/// Usage: `binary binary_set_fields(binary data, int width, list changes)`
/// Returns a copy of `data` with each `{index, value}` pair in `changes` applied to its packed
/// fields of `width` bits, in order, so a later pair for the same index wins.
fn bf_binary_set_fields(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("binary_set_fields() requires exactly 3 arguments"),
        ));
    }
    let width = packed_width(&bf_args.args[1], "binary_set_fields")?;
    let Variant::Binary(data) = bf_args.args[0].variant() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let Some(changes) = bf_args.args[2].as_list() else {
        return Err(BfErr::Code(E_TYPE));
    };
    let mut bytes = data.as_bytes().to_vec();
    let entries = packed_entries(&bytes, width);
    for change in changes.iter() {
        let Some(pair) = change.as_list() else {
            return Err(BfErr::Code(E_TYPE));
        };
        if pair.len() != 2 {
            return Err(BfErr::ErrValue(
                E_TYPE.msg("binary_set_fields() changes must be {index, value} pairs"),
            ));
        }
        let entry = packed_index(&pair[0], entries, "binary_set_fields")?;
        let value = packed_value(&pair[1], width, "binary_set_fields")?;
        packed_set(&mut bytes, width, entry, value);
    }
    let count = changes.len();
    packed_ticks(bf_args, count)?;
    Ok(Ret(v_binary(bytes)))
}

pub(crate) fn register_bf_values(builtins: &mut [BuiltinFunction]) {
    builtins[offset_for_builtin("typeof")] = bf_typeof;
    builtins[offset_for_builtin("tostr")] = bf_tostr;
    builtins[offset_for_builtin("tosym")] = bf_tosym;
    builtins[offset_for_builtin("toliteral")] = bf_toliteral;
    builtins[offset_for_builtin("fromliteral")] = bf_fromliteral;
    builtins[offset_for_builtin("toint")] = bf_toint;
    builtins[offset_for_builtin("tonum")] = bf_toint;
    builtins[offset_for_builtin("toobj")] = bf_toobj;
    builtins[offset_for_builtin("tofloat")] = bf_tofloat;
    builtins[offset_for_builtin("equal")] = bf_equal;
    builtins[offset_for_builtin("value_bytes")] = bf_value_bytes;
    builtins[offset_for_builtin("object_bytes")] = bf_object_bytes;
    builtins[offset_for_builtin("value_hash")] = bf_value_hash;
    builtins[offset_for_builtin("length")] = bf_length;
    builtins[offset_for_builtin("error_code")] = bf_error_code;
    builtins[offset_for_builtin("error_message")] = bf_error_message;
    builtins[offset_for_builtin("uuid")] = bf_uuid;
    builtins[offset_for_builtin("tobool")] = bf_tobool;
    builtins[offset_for_builtin("encode_cbor")] = bf_encode_cbor;
    builtins[offset_for_builtin("decode_cbor")] = bf_decode_cbor;
    builtins[offset_for_builtin("value_diff")] = bf_value_diff;
    builtins[offset_for_builtin("value_diff3")] = bf_value_diff3;
    builtins[offset_for_builtin("binary_pack")] = bf_binary_pack;
    builtins[offset_for_builtin("binary_unpack")] = bf_binary_unpack;
    builtins[offset_for_builtin("binary_field")] = bf_binary_field;
    builtins[offset_for_builtin("binary_set_field")] = bf_binary_set_field;
    builtins[offset_for_builtin("binary_set_fields")] = bf_binary_set_fields;
}

#[cfg(test)]
mod tests {
    use super::{packed_entries, packed_get, packed_set};

    fn pack(values: &[u64], width: usize) -> Vec<u8> {
        let mut bytes = vec![0u8; (values.len() * width).div_ceil(8)];
        for (entry, value) in values.iter().enumerate() {
            packed_set(&mut bytes, width, entry, *value);
        }
        bytes
    }

    #[test]
    fn fields_round_trip_at_every_width() {
        for width in 1..=32 {
            let max = (1u64 << width) - 1;
            let values: Vec<u64> = (0..37u64)
                .map(|i| i.wrapping_mul(0x9E37_79B9) & max)
                .collect();
            let bytes = pack(&values, width);
            assert_eq!(bytes.len(), (values.len() * width).div_ceil(8));
            for (entry, value) in values.iter().enumerate() {
                assert_eq!(packed_get(&bytes, width, entry), *value, "width {width}");
            }
        }
    }

    #[test]
    fn fields_are_lowest_bit_first_and_span_bytes() {
        // Width 5: entry 0 is bits 0-4 of byte 0, entry 1 is bits 5-7 of byte 0 and 0-1 of
        // byte 1.
        let bytes = pack(&[0b10110, 0b01101, 0b11111], 5);
        assert_eq!(bytes, vec![0b1011_0110, 0b0111_1101]);
        // Width 12, as for a large palette: entry 1 starts half way through byte 1.
        let bytes = pack(&[0xABC, 0x123], 12);
        assert_eq!(bytes, vec![0xBC, 0x3A, 0x12]);
    }

    #[test]
    fn setting_a_field_leaves_its_neighbours() {
        let mut bytes = vec![0xFF; 4];
        packed_set(&mut bytes, 7, 1, 0);
        assert_eq!(packed_get(&bytes, 7, 0), 0x7F);
        assert_eq!(packed_get(&bytes, 7, 1), 0);
        assert_eq!(packed_get(&bytes, 7, 2), 0x7F);
        assert_eq!(bytes, vec![0x7F, 0xC0, 0xFF, 0xFF]);
    }

    #[test]
    fn only_whole_entries_count() {
        assert_eq!(packed_entries(&[0; 2048], 4), 4096);
        assert_eq!(packed_entries(&[0; 3], 5), 4);
        assert_eq!(packed_entries(&[], 1), 0);
    }
}
