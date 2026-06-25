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
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

//! CBOR representation for `Var` values.

use crate::{
    Error, ErrorCode, Obj, Symbol, Var, Variant, v_binary, v_bool, v_error, v_float, v_flyweight,
    v_int, v_list, v_map, v_none, v_obj, v_str, v_sym,
};
use minicbor::{Decode, Encode};
use std::fmt;

const VAR_CBOR_VERSION: u16 = 1;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum CborVarError {
    UnsupportedType(&'static str),
    Encode(String),
    Decode(String),
    InvalidData(String),
}

impl fmt::Display for CborVarError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedType(type_name) => write!(f, "cannot encode {type_name} as CBOR"),
            Self::Encode(msg) => write!(f, "CBOR encode error: {msg}"),
            Self::Decode(msg) => write!(f, "CBOR decode error: {msg}"),
            Self::InvalidData(msg) => write!(f, "invalid CBOR Var payload: {msg}"),
        }
    }
}

impl std::error::Error for CborVarError {}

#[derive(Clone, Debug, Encode, Decode)]
struct CborVarEnvelope {
    #[n(0)]
    version: u16,
    #[n(1)]
    value: CborVar,
}

#[derive(Clone, Debug, Encode, Decode)]
enum CborVar {
    #[n(0)]
    None,
    #[n(1)]
    Bool(#[n(0)] bool),
    #[n(2)]
    Int(#[n(0)] i64),
    #[n(3)]
    FloatBits(#[n(0)] u64),
    #[n(4)]
    Str(#[n(0)] String),
    #[n(5)]
    Obj(#[n(0)] u64),
    #[n(6)]
    Err(#[n(0)] CborError),
    #[n(7)]
    List(#[n(0)] Vec<CborVar>),
    #[n(8)]
    Map(#[n(0)] Vec<CborMapPair>),
    #[n(9)]
    Sym(#[n(0)] String),
    #[n(10)]
    Binary(#[n(0)] CborBinary),
    #[n(11)]
    Flyweight(#[n(0)] CborFlyweight),
}

#[derive(Clone, Debug, Encode, Decode)]
struct CborBinary {
    #[n(0)]
    #[cbor(with = "minicbor::bytes")]
    bytes: Vec<u8>,
}

#[derive(Clone, Debug, Encode, Decode)]
struct CborMapPair {
    #[n(0)]
    key: CborVar,
    #[n(1)]
    value: CborVar,
}

#[derive(Clone, Debug, Encode, Decode)]
struct CborFlyweight {
    #[n(0)]
    delegate: u64,
    #[n(1)]
    slots: Vec<CborFlyweightSlot>,
    #[n(2)]
    contents: Vec<CborVar>,
}

#[derive(Clone, Debug, Encode, Decode)]
struct CborFlyweightSlot {
    #[n(0)]
    name: String,
    #[n(1)]
    value: CborVar,
}

#[derive(Clone, Debug, Encode, Decode)]
struct CborError {
    #[n(0)]
    code: CborErrorCode,
    #[n(1)]
    message: Option<String>,
    #[n(2)]
    value: Option<Box<CborVar>>,
}

#[derive(Clone, Debug, Encode, Decode)]
enum CborErrorCode {
    #[n(0)]
    Builtin(#[n(0)] u8),
    #[n(1)]
    Custom(#[n(0)] String),
}

pub fn encode_var_cbor(value: &Var) -> Result<Vec<u8>, CborVarError> {
    let envelope = CborVarEnvelope {
        version: VAR_CBOR_VERSION,
        value: CborVar::try_from(value)?,
    };
    minicbor::to_vec(envelope).map_err(|e| CborVarError::Encode(e.to_string()))
}

pub fn decode_var_cbor(bytes: &[u8]) -> Result<Var, CborVarError> {
    let mut decoder = minicbor::Decoder::new(bytes);
    let envelope: CborVarEnvelope = decoder
        .decode()
        .map_err(|e| CborVarError::Decode(e.to_string()))?;
    if decoder.position() != bytes.len() {
        return Err(CborVarError::InvalidData(
            "trailing bytes after Var payload".to_string(),
        ));
    }
    if envelope.version != VAR_CBOR_VERSION {
        return Err(CborVarError::InvalidData(format!(
            "unsupported Var CBOR version {}",
            envelope.version
        )));
    }
    Var::try_from(envelope.value)
}

impl TryFrom<&Var> for CborVar {
    type Error = CborVarError;

    fn try_from(value: &Var) -> Result<Self, Self::Error> {
        match value.variant() {
            Variant::None => Ok(Self::None),
            Variant::Bool(value) => Ok(Self::Bool(value)),
            Variant::Int(value) => Ok(Self::Int(value)),
            Variant::Float(value) => Ok(Self::FloatBits(value.to_bits())),
            Variant::Str(value) => Ok(Self::Str(value.as_str().to_string())),
            Variant::Obj(value) => Ok(Self::Obj(value.as_u64())),
            Variant::Err(value) => Ok(Self::Err(CborError::try_from(value)?)),
            Variant::List(value) => value
                .iter_ref()
                .map(CborVar::try_from)
                .collect::<Result<Vec<_>, _>>()
                .map(Self::List),
            Variant::Map(value) => value
                .iter_ref()
                .map(|(key, value)| {
                    Ok(CborMapPair {
                        key: CborVar::try_from(key)?,
                        value: CborVar::try_from(value)?,
                    })
                })
                .collect::<Result<Vec<_>, _>>()
                .map(Self::Map),
            Variant::Sym(value) => Ok(Self::Sym(value.as_str().to_string())),
            Variant::Binary(value) => Ok(Self::Binary(CborBinary {
                bytes: value.as_bytes().to_vec(),
            })),
            Variant::Flyweight(value) => {
                let slots = value
                    .slots_storage()
                    .iter()
                    .map(|(name, value)| {
                        Ok(CborFlyweightSlot {
                            name: name.as_str().to_string(),
                            value: CborVar::try_from(value)?,
                        })
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                let contents = value
                    .contents()
                    .iter_ref()
                    .map(CborVar::try_from)
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(Self::Flyweight(CborFlyweight {
                    delegate: value.delegate().as_u64(),
                    slots,
                    contents,
                }))
            }
            Variant::Lambda(_) => Err(CborVarError::UnsupportedType("lambda")),
        }
    }
}

impl TryFrom<CborVar> for Var {
    type Error = CborVarError;

    fn try_from(value: CborVar) -> Result<Self, Self::Error> {
        match value {
            CborVar::None => Ok(v_none()),
            CborVar::Bool(value) => Ok(v_bool(value)),
            CborVar::Int(value) => Ok(v_int(value)),
            CborVar::FloatBits(bits) => Ok(v_float(f64::from_bits(bits))),
            CborVar::Str(value) => Ok(v_str(&value)),
            CborVar::Obj(value) => Obj::try_read(value)
                .map(v_obj)
                .map_err(|e| CborVarError::InvalidData(e.to_string())),
            CborVar::Err(value) => Error::try_from(value).map(v_error),
            CborVar::List(value) => value
                .into_iter()
                .map(Var::try_from)
                .collect::<Result<Vec<_>, _>>()
                .map(|values| v_list(&values)),
            CborVar::Map(value) => value
                .into_iter()
                .map(|pair| Ok((Var::try_from(pair.key)?, Var::try_from(pair.value)?)))
                .collect::<Result<Vec<_>, _>>()
                .map(|pairs| v_map(&pairs)),
            CborVar::Sym(value) => Ok(v_sym(Symbol::mk(&value))),
            CborVar::Binary(value) => Ok(v_binary(value.bytes)),
            CborVar::Flyweight(value) => {
                let delegate = Obj::try_read(value.delegate)
                    .map_err(|e| CborVarError::InvalidData(e.to_string()))?;
                let slots = value
                    .slots
                    .into_iter()
                    .map(|slot| Ok((Symbol::mk(&slot.name), Var::try_from(slot.value)?)))
                    .collect::<Result<Vec<_>, _>>()?;
                let contents = value
                    .contents
                    .into_iter()
                    .map(Var::try_from)
                    .collect::<Result<Vec<_>, _>>()?;
                let contents = v_list(&contents)
                    .as_list()
                    .expect("v_list returns a list")
                    .clone();
                Ok(v_flyweight(delegate, &slots, contents))
            }
        }
    }
}

impl TryFrom<&Error> for CborError {
    type Error = CborVarError;

    fn try_from(value: &Error) -> Result<Self, Self::Error> {
        Ok(Self {
            code: CborErrorCode::from(value.err_type()),
            message: value.msg().map(ToString::to_string),
            value: value
                .value()
                .map(CborVar::try_from)
                .transpose()?
                .map(Box::new),
        })
    }
}

impl TryFrom<CborError> for Error {
    type Error = CborVarError;

    fn try_from(value: CborError) -> Result<Self, Self::Error> {
        Ok(Error::new(
            ErrorCode::try_from(value.code)?,
            value.message,
            value.value.map(|value| Var::try_from(*value)).transpose()?,
        ))
    }
}

impl From<ErrorCode> for CborErrorCode {
    fn from(value: ErrorCode) -> Self {
        if let Some(code) = Error::new(value, None, None).to_int() {
            return Self::Builtin(code);
        }

        match value {
            ErrorCode::ErrCustom(symbol) => Self::Custom(symbol.as_str().to_string()),
            _ => unreachable!("all builtin error codes have integer representations"),
        }
    }
}

impl TryFrom<CborErrorCode> for ErrorCode {
    type Error = CborVarError;

    fn try_from(value: CborErrorCode) -> Result<Self, Self::Error> {
        match value {
            CborErrorCode::Builtin(code) => Error::from_repr(code)
                .map(|error| error.err_type())
                .ok_or_else(|| CborVarError::InvalidData(format!("unknown error code {code}"))),
            CborErrorCode::Custom(symbol) => Ok(ErrorCode::ErrCustom(Symbol::mk(&symbol))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AnonymousObjid, E_INVARG, E_PERM, v_binary, v_empty_list, v_err, v_map};

    fn round_trip(value: Var) {
        let encoded = encode_var_cbor(&value).expect("encode should succeed");
        let decoded = decode_var_cbor(&encoded).expect("decode should succeed");
        assert_eq!(decoded, value);
    }

    #[test]
    fn scalar_values_round_trip() {
        round_trip(v_none());
        round_trip(v_bool(true));
        round_trip(v_bool(false));
        round_trip(v_int(-42));
        round_trip(v_float(-0.0));
        round_trip(v_str("hello"));
        round_trip(v_sym(Symbol::mk("core")));
        round_trip(v_binary(vec![0, 1, 2, 255]));
        round_trip(v_obj(Obj::mk_id(-1)));
        round_trip(v_obj(Obj::mk_anonymous(AnonymousObjid(123))));
        round_trip(v_err(E_PERM));
    }

    #[test]
    fn compound_values_round_trip() {
        let pairs = vec![(v_str("b"), v_int(2)), (v_str("a"), v_int(1))];
        round_trip(v_map(&pairs));

        let err = E_INVARG.with_msg_and_value(|| "bad value".to_string(), v_str("x"));
        round_trip(v_error(err));

        let contents = v_empty_list().as_list().unwrap().clone();
        round_trip(v_flyweight(
            Obj::mk_id(7),
            &[(Symbol::mk("slot"), v_int(99))],
            contents,
        ));
    }
}
