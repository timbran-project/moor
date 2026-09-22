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

use crate::{
    Error,
    error::ErrorCode::{E_DIV, E_FLOAT, E_INVARG, E_TYPE},
    variant::Variant,
    variant::{Var, v_float, v_int},
};
use std::ops::Neg;

/// `base ^ exp` with an exact integer exponent, via exponentiation by squaring.
/// Used where `f64::powf` would round exponents above 2^53.
fn float_pow_int(base: f64, exp: i64) -> f64 {
    // (-b)^n is b^n for even n and -(b^n) for odd n; factoring the sign out
    // keeps the parity of huge exponents exact.
    let sign_flip = base < 0.0 && exp % 2 != 0;
    let mut result = 1.0f64;
    let mut factor = base.abs();
    let mut e = exp.unsigned_abs();
    while e != 0 {
        if e & 1 == 1 {
            result *= factor;
        }
        e >>= 1;
        if e != 0 {
            factor *= factor;
        }
    }
    let result = if exp < 0 { 1.0 / result } else { result };
    if sign_flip { -result } else { result }
}

/// LambdaMOO does not allow IEEE infinities and NaNs in MOO values; `E_FLOAT` is
/// raised wherever one of these would otherwise be computed. All float-producing
/// arithmetic routes through here to enforce that.
#[inline(always)]
fn float_result(d: f64) -> Result<Var, Error> {
    if d.is_finite() {
        Ok(v_float(d))
    } else {
        Err(E_FLOAT.msg("result is not a real number"))
    }
}

#[inline(always)]
fn division_by_zero() -> Error {
    E_DIV.msg("division by zero")
}

impl Var {
    #[inline]
    pub fn add(&self, v: &Self) -> Result<Self, Error> {
        // Fast path: int + int (most common in MOO code)
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            return l
                .checked_add(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer overflow"));
        }
        // Fast path: float + float
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            return float_result(l + r);
        }
        self.add_slow(v)
    }

    #[inline(never)]
    fn add_slow(&self, v: &Self) -> Result<Self, Error> {
        match (self.variant(), v.variant()) {
            (Variant::Str(s), Variant::Str(r)) => Ok(s.str_append(r)),
            (_, _) => Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot add type {} and {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            })),
        }
    }

    #[inline]
    pub fn sub(&self, v: &Self) -> Result<Self, Error> {
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            return l
                .checked_sub(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer underflow"));
        }
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            return float_result(l - r);
        }
        self.sub_slow(v)
    }

    #[inline(never)]
    fn sub_slow(&self, v: &Self) -> Result<Self, Error> {
        // As in LambdaMOO, arithmetic operands must have the same type.
        Err(E_TYPE.with_msg(|| {
            format!(
                "Cannot sub type {} and {}",
                self.type_code().to_literal(),
                v.type_code().to_literal()
            )
        }))
    }

    #[inline]
    pub fn mul(&self, v: &Self) -> Result<Self, Error> {
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            return l
                .checked_mul(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer overflow"));
        }
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            return float_result(l * r);
        }
        self.mul_slow(v)
    }

    #[inline(never)]
    fn mul_slow(&self, v: &Self) -> Result<Self, Error> {
        Err(E_TYPE.with_msg(|| {
            format!(
                "Cannot mul type {} and {}",
                self.type_code().to_literal(),
                v.type_code().to_literal()
            )
        }))
    }

    #[inline]
    pub fn div(&self, v: &Self) -> Result<Self, Error> {
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            if r == 0 {
                return Err(division_by_zero());
            }
            return l
                .checked_div(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer overflow"));
        }
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            if r == 0.0 {
                return Err(division_by_zero());
            }
            return float_result(l / r);
        }
        self.div_slow(v)
    }

    #[inline(never)]
    fn div_slow(&self, v: &Self) -> Result<Self, Error> {
        Err(E_TYPE.with_msg(|| {
            format!(
                "Cannot div type {} and {}",
                self.type_code().to_literal(),
                v.type_code().to_literal()
            )
        }))
    }

    #[inline]
    pub fn modulus(&self, v: &Self) -> Result<Self, Error> {
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            if r == 0 {
                return Err(division_by_zero());
            }
            return l
                .checked_rem(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer overflow"));
        }
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            if r == 0.0 {
                return Err(division_by_zero());
            }
            // fmod of finite operands is finite whenever the divisor is not zero.
            return Ok(v_float(l % r));
        }
        self.modulus_slow(v)
    }

    #[inline(never)]
    fn modulus_slow(&self, v: &Self) -> Result<Self, Error> {
        Err(E_TYPE.with_msg(|| {
            format!(
                "Cannot modulus type {} and {}",
                self.type_code().to_literal(),
                v.type_code().to_literal()
            )
        }))
    }

    #[inline]
    pub fn pow(&self, v: &Self) -> Result<Self, Error> {
        if let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) {
            if r == 0 {
                return Ok(v_int(1));
            }
            if r < 0 {
                // LambdaMOO semantics for negative integer exponents: zero for
                // |base| >= 2, the degenerate bases cycle, and 0 ^ negative is
                // a division by zero.
                return match l {
                    -1 => Ok(v_int(if r % 2 == 0 { 1 } else { -1 })),
                    0 => Err(division_by_zero()),
                    1 => Ok(v_int(1)),
                    _ => Ok(v_int(0)),
                };
            }
            // These bases cannot overflow regardless of exponent size.
            if l == 0 {
                return Ok(v_int(0));
            }
            if l == 1 {
                return Ok(v_int(1));
            }
            if l == -1 {
                return Ok(v_int(if r % 2 == 0 { 1 } else { -1 }));
            }
            let r = u32::try_from(r).map_err(|_| E_INVARG.msg("Integer overflow"))?;
            return l
                .checked_pow(r)
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer overflow"));
        }
        if let (Some(l), Some(r)) = (self.as_float(), v.as_float()) {
            return float_result(l.powf(r));
        }
        self.pow_slow(v)
    }

    #[inline(never)]
    fn pow_slow(&self, v: &Self) -> Result<Self, Error> {
        match (self.variant(), v.variant()) {
            // LambdaMOO allows a float raised to an integer power; the exponent
            // needs no type equality with the base.
            (Variant::Float(l), Variant::Int(r)) => {
                // f64 cannot represent integers above 2^53 exactly; converting
                // the exponent would round e.g. 2^53 + 1 to an even exponent and
                // flip the sign of a negative base raised to it.
                if r.unsigned_abs() <= (1_u64 << 53) {
                    float_result(l.powf(r as f64))
                } else {
                    float_result(float_pow_int(l, r))
                }
            }
            (_, _) => Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot pow type {} and {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            })),
        }
    }

    #[inline]
    pub fn negative(&self) -> Result<Self, Error> {
        if let Some(i) = self.as_integer() {
            return i
                .checked_neg()
                .map(v_int)
                .ok_or_else(|| E_INVARG.msg("Integer underflow"));
        }
        if let Some(f) = self.as_float() {
            // Negation of a real number is a real number.
            return Ok(v_float(f.neg()));
        }
        Err(E_TYPE.with_msg(|| format!("Cannot negate type {}", self.type_code().to_literal())))
    }

    // === Integer-only operations (use direct accessors) ===

    #[inline]
    pub fn bitand(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot bitwise AND type {} and {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        Ok(v_int(l & r))
    }

    #[inline]
    pub fn bitor(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot bitwise OR type {} and {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        Ok(v_int(l | r))
    }

    #[inline]
    pub fn bitxor(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot bitwise XOR type {} and {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        Ok(v_int(l ^ r))
    }

    pub fn is_sysobj(&self) -> bool {
        self.as_object().map(|o| o.is_sysobj()).unwrap_or(false)
    }

    #[inline]
    pub fn bitshl(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot left shift type {} by {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        if !(0..=63).contains(&r) {
            return Err(E_INVARG.msg("Invalid shift amount"));
        }
        // Bits shifted out beyond the width are discarded.
        Ok(v_int(l.wrapping_shl(r as u32)))
    }

    #[inline]
    pub fn bitshr(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot right shift type {} by {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        if !(0..=63).contains(&r) {
            return Err(E_INVARG.msg("Invalid shift amount"));
        }
        Ok(v_int(l.wrapping_shr(r as u32)))
    }

    #[inline]
    pub fn bitlshr(&self, v: &Self) -> Result<Self, Error> {
        let (Some(l), Some(r)) = (self.as_integer(), v.as_integer()) else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot logical right shift type {} by {}",
                    self.type_code().to_literal(),
                    v.type_code().to_literal()
                )
            }));
        };
        if !(0..=63).contains(&r) {
            return Err(E_INVARG.msg("Invalid shift amount"));
        }
        // Logical (unsigned) right shift: cast to u64, shift, cast back to i64
        Ok(v_int(((l as u64) >> (r as u32)) as i64))
    }

    #[inline]
    pub fn bitnot(&self) -> Result<Self, Error> {
        let Some(l) = self.as_integer() else {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Cannot bitwise complement type {}",
                    self.type_code().to_literal()
                )
            }));
        };
        Ok(v_int(!l))
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        error::ErrorCode::{E_DIV, E_FLOAT, E_INVARG, E_RANGE, E_TYPE},
        variant::{v_err, v_float, v_int, v_list, v_objid, v_str},
    };
    use std::cmp::Ordering;

    #[test]
    fn test_truthy() {
        assert!(v_int(1).is_true());
        assert!(!v_int(0).is_true());
    }

    #[test]
    fn test_add() {
        assert_eq!(v_int(1).add(&v_int(2)), Ok(v_int(3)));
        assert_eq!(v_float(1.).add(&v_float(2.)), Ok(v_float(3.)));
        assert_eq!(v_str("a").add(&v_str("b")), Ok(v_str("ab")));
        // As in LambdaMOO, arithmetic operands must have the same type.
        assert_eq!(v_int(1).add(&v_float(2.)).unwrap_err().err_type(), E_TYPE);
        assert_eq!(v_float(1.).add(&v_int(2)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_sub() {
        assert_eq!(v_int(1).sub(&v_int(2)), Ok(v_int(-1)));
        assert_eq!(v_float(1.).sub(&v_float(2.)), Ok(v_float(-1.)));
        assert_eq!(v_int(1).sub(&v_float(2.)).unwrap_err().err_type(), E_TYPE);
        assert_eq!(v_float(1.).sub(&v_int(2)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_mul() {
        assert_eq!(v_int(1).mul(&v_int(2)), Ok(v_int(2)));
        assert_eq!(v_float(1.).mul(&v_float(2.)), Ok(v_float(2.)));
        assert_eq!(v_int(1).mul(&v_float(2.)).unwrap_err().err_type(), E_TYPE);
        assert_eq!(v_float(1.).mul(&v_int(2)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_div() {
        assert_eq!(v_int(1).div(&v_int(2)), Ok(v_int(0)));
        assert_eq!(v_float(1.).div(&v_float(2.)), Ok(v_float(0.5)));
        assert_eq!(v_int(1).div(&v_float(2.)).unwrap_err().err_type(), E_TYPE);
        assert_eq!(v_float(1.).div(&v_int(2)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_modulus() {
        assert_eq!(v_int(1).modulus(&v_int(2)), Ok(v_int(1)));
        assert_eq!(v_float(1.).modulus(&v_float(2.)), Ok(v_float(1.)));
        assert_eq!(
            v_str("moop").modulus(&v_int(2)).unwrap_err().err_type(),
            E_TYPE
        );
        assert_eq!(
            v_int(1).modulus(&v_float(2.)).unwrap_err().err_type(),
            E_TYPE
        );
        assert_eq!(
            v_float(1.).modulus(&v_int(2)).unwrap_err().err_type(),
            E_TYPE
        );
    }

    #[test]
    fn test_pow() {
        assert_eq!(v_int(1).pow(&v_int(2)), Ok(v_int(1)));
        assert_eq!(v_int(2).pow(&v_int(2)), Ok(v_int(4)));
        // A float may be raised to an integer power (LambdaMOO).
        assert_eq!(v_float(2.).pow(&v_int(2)), Ok(v_float(4.)));
        assert_eq!(v_float(2.).pow(&v_float(2.)), Ok(v_float(4.)));
        // An integer may not be raised to a float power.
        assert_eq!(v_int(2).pow(&v_float(2.)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_integer_power_semantics() {
        // LambdaMOO semantics for integer exponents
        assert_eq!(v_int(2).pow(&v_int(0)), Ok(v_int(1)));
        assert_eq!(v_int(2).pow(&v_int(10)), Ok(v_int(1024)));
        assert_eq!(v_int(2).pow(&v_int(63)).unwrap_err().err_type(), E_INVARG);
        assert_eq!(v_int(2).pow(&v_int(-3)), Ok(v_int(0)));
        assert_eq!(v_int(-1).pow(&v_int(-3)), Ok(v_int(-1)));
        assert_eq!(v_int(-1).pow(&v_int(-2)), Ok(v_int(1)));
        assert_eq!(v_int(1).pow(&v_int(-500)), Ok(v_int(1)));
        assert_eq!(v_int(0).pow(&v_int(-1)).unwrap_err().err_type(), E_DIV);
    }

    #[test]
    fn test_division_by_zero() {
        assert_eq!(v_int(1).div(&v_int(0)).unwrap_err().err_type(), E_DIV);
        assert_eq!(v_int(1).modulus(&v_int(0)).unwrap_err().err_type(), E_DIV);
        assert_eq!(v_float(1.).div(&v_float(0.)).unwrap_err().err_type(), E_DIV);
        assert_eq!(
            v_float(1.).modulus(&v_float(0.)).unwrap_err().err_type(),
            E_DIV
        );
        // Type mismatch is raised before the zero-divisor check (LambdaMOO).
        assert_eq!(v_float(1.).div(&v_int(0)).unwrap_err().err_type(), E_TYPE);
        assert_eq!(v_int(1).div(&v_float(0.)).unwrap_err().err_type(), E_TYPE);
    }

    #[test]
    fn test_no_non_real_results() {
        // LambdaMOO: E_FLOAT is raised wherever an infinity or NaN would be computed.
        assert_eq!(
            v_float(1e308).add(&v_float(1e308)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(-1e308).sub(&v_float(1e308)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(1e308).mul(&v_float(10.)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(1e308).div(&v_float(1e-308)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(0.).pow(&v_float(-1.)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(-8.).pow(&v_float(0.5)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(2.).pow(&v_float(2000.)).unwrap_err().err_type(),
            E_FLOAT
        );
        assert_eq!(
            v_float(2.).pow(&v_int(2000)).unwrap_err().err_type(),
            E_FLOAT
        );
    }

    #[test]
    fn test_integer_exponent_exactness() {
        // f64::powf rounds exponents above 2^53 to even, which would flip the
        // sign of (-1.0) ^ (2^53 + 1).
        assert_eq!(
            v_float(-1.0).pow(&v_int(9007199254740993)),
            Ok(v_float(-1.0))
        );
        assert_eq!(
            v_float(-1.0).pow(&v_int(9007199254740992)),
            Ok(v_float(1.0))
        );
        assert_eq!(
            v_float(2.0).pow(&v_int(54)),
            Ok(v_float(18014398509481984.0))
        );
    }

    #[test]
    fn test_negative() {
        assert_eq!(v_int(1).negative(), Ok(v_int(-1)));
        assert_eq!(v_float(1.).negative(), Ok(v_float(-1.0)));
    }

    #[test]
    fn test_eq() {
        assert_eq!(v_int(1), v_int(1));
        assert_eq!(v_float(1.), v_float(1.));
        assert_eq!(v_str("a"), v_str("a"));
        assert_eq!(v_str("a"), v_str("A"));
        assert_eq!(v_list(&[v_int(1), v_int(2)]), v_list(&[v_int(1), v_int(2)]));
        assert_eq!(v_objid(1), v_objid(1));
        assert_eq!(v_err(E_TYPE), v_err(E_TYPE));
    }

    #[test]
    fn test_ne() {
        assert_ne!(v_int(1), v_int(2));
        assert_ne!(v_float(1.), v_float(2.));
        assert_ne!(v_str("a"), v_str("b"));
        assert_ne!(v_list(&[v_int(1), v_int(2)]), v_list(&[v_int(1), v_int(3)]));
        assert_ne!(v_objid(1), v_objid(2));
        assert_ne!(v_err(E_TYPE), v_err(E_RANGE));
    }

    #[test]
    fn test_lt() {
        assert!(v_int(1) < v_int(2));
        assert!(v_float(1.) < v_float(2.));
        assert!(v_str("a") < v_str("b"));
        assert!(v_objid(1) < v_objid(2));
        assert!(v_err(E_TYPE) < v_err(E_RANGE));
    }

    #[test]
    fn test_le() {
        assert!(v_int(1) <= v_int(2));
        assert!(v_float(1.) <= v_float(2.));
        assert!(v_str("a") <= v_str("b"));
        assert!(v_objid(1) <= v_objid(2));
        assert!(v_err(E_TYPE) <= v_err(E_RANGE));
    }

    #[test]
    fn test_gt() {
        assert!(v_int(2) > v_int(1));
        assert!(v_float(2.) > v_float(1.));
        assert!(v_str("b") > v_str("a"));
        assert!(v_objid(2) > v_objid(1));
        assert!(v_err(E_RANGE) > v_err(E_TYPE));
    }

    #[test]
    fn test_ge() {
        assert!(v_int(2) >= v_int(1));
        assert!(v_float(2.) >= v_float(1.));
        assert!(v_str("b") >= v_str("a"));
        assert!(v_objid(2) >= v_objid(1));
        assert!(v_err(E_RANGE) >= v_err(E_TYPE));
    }

    #[test]
    fn test_bitand() {
        assert_eq!(v_int(5).bitand(&v_int(3)), Ok(v_int(1))); // 0101 & 0011 = 0001
        assert_eq!(v_int(12).bitand(&v_int(10)), Ok(v_int(8))); // 1100 & 1010 = 1000
        assert_eq!(v_int(0).bitand(&v_int(15)), Ok(v_int(0))); // 0000 & 1111 = 0000

        // Test with non-integers
        assert!(v_str("test").bitand(&v_int(5)).is_err());
        assert!(v_int(5).bitand(&v_str("test")).is_err());
    }

    #[test]
    fn test_bitor() {
        assert_eq!(v_int(5).bitor(&v_int(3)), Ok(v_int(7))); // 0101 | 0011 = 0111
        assert_eq!(v_int(12).bitor(&v_int(10)), Ok(v_int(14))); // 1100 | 1010 = 1110
        assert_eq!(v_int(0).bitor(&v_int(15)), Ok(v_int(15))); // 0000 | 1111 = 1111

        // Test with non-integers
        assert!(v_str("test").bitor(&v_int(5)).is_err());
        assert!(v_int(5).bitor(&v_str("test")).is_err());
    }

    #[test]
    fn test_bitxor() {
        assert_eq!(v_int(5).bitxor(&v_int(3)), Ok(v_int(6))); // 0101 ^ 0011 = 0110
        assert_eq!(v_int(12).bitxor(&v_int(10)), Ok(v_int(6))); // 1100 ^ 1010 = 0110
        assert_eq!(v_int(15).bitxor(&v_int(15)), Ok(v_int(0))); // 1111 ^ 1111 = 0000

        // Test with non-integers
        assert!(v_str("test").bitxor(&v_int(5)).is_err());
        assert!(v_int(5).bitxor(&v_str("test")).is_err());
    }

    #[test]
    fn test_bitshl() {
        assert_eq!(v_int(1).bitshl(&v_int(2)), Ok(v_int(4))); // 1 << 2 = 4
        assert_eq!(v_int(5).bitshl(&v_int(1)), Ok(v_int(10))); // 5 << 1 = 10
        assert_eq!(v_int(3).bitshl(&v_int(3)), Ok(v_int(24))); // 3 << 3 = 24

        // Bits shifted out are discarded
        assert_eq!(v_int(1).bitshl(&v_int(63)), Ok(v_int(i64::MIN)));

        // Test bounds checking
        assert!(v_int(1).bitshl(&v_int(-1)).is_err()); // Should return error
        assert!(v_int(1).bitshl(&v_int(64)).is_err()); // Should return error

        // Test with non-integers
        assert!(v_str("test").bitshl(&v_int(2)).is_err());
        assert!(v_int(5).bitshl(&v_str("test")).is_err());
    }

    #[test]
    fn test_bitshr() {
        assert_eq!(v_int(8).bitshr(&v_int(2)), Ok(v_int(2))); // 8 >> 2 = 2
        assert_eq!(v_int(10).bitshr(&v_int(1)), Ok(v_int(5))); // 10 >> 1 = 5
        assert_eq!(v_int(24).bitshr(&v_int(3)), Ok(v_int(3))); // 24 >> 3 = 3

        // Test bounds checking
        assert!(v_int(8).bitshr(&v_int(-1)).is_err()); // Should return error
        assert!(v_int(8).bitshr(&v_int(64)).is_err()); // Should return error

        // Test with non-integers
        assert!(v_str("test").bitshr(&v_int(2)).is_err());
        assert!(v_int(5).bitshr(&v_str("test")).is_err());
    }

    #[test]
    fn test_bitnot() {
        assert_eq!(v_int(5).bitnot(), Ok(v_int(!5))); // ~5 = -6 in two's complement
        assert_eq!(v_int(0).bitnot(), Ok(v_int(-1))); // ~0 = -1
        assert_eq!(v_int(-1).bitnot(), Ok(v_int(0))); // ~(-1) = 0
        assert_eq!(v_int(42).bitnot(), Ok(v_int(!42))); // ~42 = -43

        // Test with non-integers
        assert!(v_str("test").bitnot().is_err()); // Should return error
        assert!(v_float(5.0).bitnot().is_err()); // Should return error
    }

    #[test]
    fn test_intertype_snorgling() {
        let f = v_float(10.74107142857142);
        let i = v_int(100);
        assert!(f <= i);
    }

    #[test]
    fn test_operator_compare_type_checks() {
        // As in LambdaMOO, the ordering operators accept only like types.
        assert_eq!(v_int(1).compare(&v_int(2)).unwrap(), Ordering::Less);
        assert_eq!(
            v_float(2.0).compare(&v_float(1.0)).unwrap(),
            Ordering::Greater
        );
        // Strings order case-insensitively, like `==`.
        assert_eq!(v_str("a").compare(&v_str("B")).unwrap(), Ordering::Less);
        assert_eq!(v_objid(1).compare(&v_objid(2)).unwrap(), Ordering::Less);
        // Error values order by error code.
        assert_eq!(
            v_err(E_TYPE).compare(&v_err(E_DIV)).unwrap(),
            Ordering::Less
        );

        // Even int/float pairs are of different types, as for `==`.
        assert_eq!(
            v_int(1).compare(&v_float(2.0)).unwrap_err().err_type(),
            E_TYPE
        );
        assert_eq!(
            v_float(1.0).compare(&v_int(2)).unwrap_err().err_type(),
            E_TYPE
        );
        assert_eq!(
            v_int(1).compare(&v_str("a")).unwrap_err().err_type(),
            E_TYPE
        );
        assert_eq!(
            v_list(&[v_int(1)])
                .compare(&v_list(&[v_int(1)]))
                .unwrap_err()
                .err_type(),
            E_TYPE
        );
    }
}
