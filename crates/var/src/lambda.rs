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
    Var,
    program::{opcode::ScatterArgs, program::Program},
};
use triomphe::Arc;

/// Lambda function value containing parameter specification, compiled body, and captured environment
#[derive(Clone, Debug, PartialEq)]
#[repr(transparent)]
pub struct Lambda(pub Arc<LambdaInner>);

#[derive(Clone, Debug, PartialEq)]
pub struct LambdaInner {
    /// Parameter specification (reuses scatter assignment structure)
    pub params: ScatterArgs,
    /// The lambda body as standalone executable program
    /// Compiled at compile-time into a complete, self-contained Program
    pub body: Program,
    /// Captured variable environment from lambda creation site
    pub captured_env: Vec<Vec<Var>>,
    /// Optional self-reference variable name for recursive lambdas
    pub self_var: Option<crate::program::names::Name>,
}

impl Lambda {
    /// Create a new lambda value
    pub fn new(
        params: ScatterArgs,
        body: Program,
        captured_env: Vec<Vec<Var>>,
        self_var: Option<crate::program::names::Name>,
    ) -> Self {
        Self(Arc::new(LambdaInner {
            params,
            body,
            captured_env,
            self_var,
        }))
    }

    /// Create a deep copy of this lambda for self-reference to avoid cycles.
    ///
    /// TODO: If we ever get a cycle-collecting or full tracing GC, we can safely back this out
    ///   and allow true cycles since they would be properly collected.
    pub fn for_self_reference(&self) -> Self {
        Self(Arc::new(LambdaInner {
            params: self.0.params.clone(),
            body: self.0.body.clone(),
            captured_env: self.0.captured_env.clone(),
            self_var: self.0.self_var,
        }))
    }
}
