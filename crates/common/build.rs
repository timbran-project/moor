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

use vergen::{Cargo, Emitter};
use vergen_gitcl::Gitcl;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Emit cargo version info with idempotent mode to prevent constant rebuilds
    let cargo = Cargo::all_cargo();

    // Emit git SHA with idempotent mode.
    let gitcl = Gitcl::builder().sha(true).build();

    Emitter::default()
        .idempotent()
        .add_instructions(&cargo)?
        .add_instructions(&gitcl)?
        .emit()?;

    Ok(())
}
