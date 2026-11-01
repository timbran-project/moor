// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! A native verb library with one function, `sum`, which adds its integer arguments.
//!
//! cargo build -p moor-native-verb --example sum_library
//!
//! Then start the daemon with `--native-library target/debug/examples/libsum_library.so`, and as
//! a wizard: `set_verb_native(obj, "sum", "example", "sum")`.

use moor_native_verb::{Call, Done, Result};

fn sum(call: &Call) -> Result<Done> {
    let mut total: i64 = 0;
    for arg in call.arg_values()? {
        total = total.saturating_add(arg.int(call)?);
    }
    Ok(call.ret(total))
}

moor_native_verb::native_verb_library! {
    name: "example",
    version: "1.0.0",
    functions: { "sum" => sum },
}
