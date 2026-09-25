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

//! General-purpose test macros for parser testing

/// Assert that a parse operation succeeds
#[macro_export]
macro_rules! assert_parse_ok {
    ($code:expr) => {
        match $crate::compile($code, $crate::CompileOptions::default()) {
            Ok(_) => {}
            Err(e) => panic!("Parse failed for code '{}': {:?}", $code, e),
        }
    };
    ($code:expr, $msg:expr) => {
        match $crate::compile($code, $crate::CompileOptions::default()) {
            Ok(_) => {}
            Err(e) => panic!("{}: Parse failed for code '{}': {:?}", $msg, $code, e),
        }
    };
}

/// Assert that a parse operation fails
#[macro_export]
macro_rules! assert_parse_fails {
    ($code:expr) => {
        match $crate::compile($code, $crate::CompileOptions::default()) {
            Ok(_) => panic!("Parse unexpectedly succeeded for code '{}'", $code),
            Err(_) => {}
        }
    };
    ($code:expr, $msg:expr) => {
        match $crate::compile($code, $crate::CompileOptions::default()) {
            Ok(_) => panic!(
                "{}: Parse unexpectedly succeeded for code '{}'",
                $msg, $code
            ),
            Err(_) => {}
        }
    };
}

/// Assert that parsing produces a specific error
#[macro_export]
macro_rules! assert_parse_error {
    ($code:expr, $expected_error:pat) => {
        match $crate::compile($code, $crate::CompileOptions::default()) {
            Ok(_) => panic!("Parse unexpectedly succeeded for code '{}'", $code),
            Err(e) => match e {
                $expected_error => {}
                _ => panic!(
                    "Expected error pattern {} but got {:?}",
                    stringify!($expected_error),
                    e
                ),
            },
        }
    };
}
