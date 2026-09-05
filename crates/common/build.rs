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
    // Docker passes the SHA explicitly to invalidate cached build-script output.
    println!("cargo:rerun-if-env-changed=VERGEN_GIT_SHA");

    let cargo = Cargo::all_cargo();
    let gitcl = Gitcl::builder().sha(true).build();

    Emitter::default()
        .add_instructions(&cargo)?
        .add_instructions(&gitcl)?
        .emit()?;

    Ok(())
}
