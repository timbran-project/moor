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
    Symbol,
    program::{names::Variable, program::Program},
};

pub mod labels;
pub mod names;
pub mod opcode;
pub mod stored_program;

#[allow(clippy::module_inception)]
pub mod program;

#[derive(Debug, Clone, PartialEq)]
pub enum ProgramType {
    MooR(Program),
    /// A verb whose body is a function in a native library the daemon loaded at startup.
    Native(NativeProgram),
}

/// A native verb's binding: a function in a native library the daemon loads at startup. Both
/// are the names the library declares for itself, never file names or linker symbols, so a
/// database moves between machines that install the same libraries.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct NativeProgram {
    pub library: Symbol,
    pub function: Symbol,
}

impl ProgramType {
    pub fn is_empty(&self) -> bool {
        match self {
            ProgramType::MooR(p) => p.main_vector().is_empty(),
            ProgramType::Native(_) => false,
        }
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum DeclType {
    Global,
    Let,
    Assign,
    For,
    Unknown,
    Register,
    Except,
    WhileLabel,
    ForkLabel,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct Decl {
    /// The type of declaration, how was it declared?
    pub decl_type: DeclType,
    /// The name of the variable (or register id if a register).
    pub identifier: Variable,
    /// What scope the variable was declared in.
    pub depth: usize,
    /// Is this a constant? Reject subsequent assignments.
    pub constant: bool,
    /// The scope id of the variable.
    /// This is used to determine the scope of the variable when binding (or rebinding at decompile)
    pub scope_id: u16,
}
