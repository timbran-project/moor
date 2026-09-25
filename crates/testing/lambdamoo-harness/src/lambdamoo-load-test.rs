// Copyright (C) 2025 Ryan Daum <ryan.daum@gmail.com> This program is free
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

//! Entry point for the optional embedded LambdaMOO benchmark.

#[cfg(lambdamoo_available)]
mod load_test;

#[cfg(lambdamoo_available)]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    load_test::run()
}

#[cfg(not(lambdamoo_available))]
fn main() -> std::process::ExitCode {
    eprintln!(
        "LambdaMOO is disabled. Set LAMBDAMOO_SRC_DIR to a configured source directory and rebuild with --features embedded-lambdamoo. See crates/testing/lambdamoo-harness/README.md."
    );
    std::process::ExitCode::FAILURE
}
