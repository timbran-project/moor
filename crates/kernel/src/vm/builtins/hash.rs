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

use crate::vm::builtins::BfErr;
use md5::Digest;
use moor_var::{E_INVARG, Var, Variant, v_binary, v_str};
use ripemd::Ripemd160;
use sha1::Sha1;
use sha2::{Sha224, Sha256, Sha384, Sha512};

pub fn hash_bytes(algo: &str, bytes: &[u8]) -> Result<Vec<u8>, BfErr> {
    let digest = match algo.to_ascii_lowercase().as_str() {
        "md5" => md5::Md5::digest(bytes).to_vec(),
        "sha1" => Sha1::digest(bytes).to_vec(),
        "sha224" => Sha224::digest(bytes).to_vec(),
        "sha256" => Sha256::digest(bytes).to_vec(),
        "sha384" => Sha384::digest(bytes).to_vec(),
        "sha512" => Sha512::digest(bytes).to_vec(),
        "ripemd160" => Ripemd160::digest(bytes).to_vec(),
        _ => return Err(BfErr::ErrValue(E_INVARG.msg("unsupported hash algorithm"))),
    };
    Ok(digest)
}

pub fn hash_output(digest: Vec<u8>, binary: bool) -> Var {
    if binary {
        return v_binary(digest);
    }

    v_str(&uppercase_hex(&digest))
}

pub fn hash_algorithm_arg(value: &Var) -> Result<String, BfErr> {
    match value.variant() {
        Variant::Str(s) => Ok(s.as_str().to_string()),
        Variant::Sym(s) => Ok(s.as_str().to_string()),
        _ => Err(BfErr::Code(E_INVARG)),
    }
}

pub fn uppercase_hex(bytes: &[u8]) -> String {
    let mut hex = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        write!(&mut hex, "{byte:02X}").expect("writing to String cannot fail");
    }
    hex
}
