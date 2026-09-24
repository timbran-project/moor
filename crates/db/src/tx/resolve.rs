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

use super::check::PotentialConflict;
use crate::tx::{Error, RelationCodomain, RelationDomain};

/// The result of a conflict resolution attempt.
pub enum Resolution<Codomain> {
    /// Accept the proposed operation as-is (continue checking)
    Accept,
    /// Rewrite the proposed operation with a new value
    Rewrite(Codomain),
}

/// Trait for conflict resolution strategies.
///
/// Implement this to provide custom conflict resolution logic. The resolver
/// is called for each detected conflict and can either:
/// - Return `Ok(Resolution::Accept)` to accept/resolve the conflict and continue checking
/// - Return `Ok(Resolution::Rewrite(new_val))` to resolve by changing the written value
/// - Return `Err(Error::Conflict(...))` to abort with that conflict
pub trait ConflictResolver<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    /// Attempt to resolve a conflict.
    ///
    /// Called when a conflict is detected during the check phase.
    fn resolve(
        &mut self,
        conflict: &PotentialConflict<Domain, Codomain>,
    ) -> Result<Resolution<Codomain>, Error>;
}

/// A resolver that always fails on conflict (the default behavior).
pub struct FailOnConflict;

impl<Domain, Codomain> ConflictResolver<Domain, Codomain> for FailOnConflict
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    fn resolve(
        &mut self,
        conflict: &PotentialConflict<Domain, Codomain>,
    ) -> Result<Resolution<Codomain>, Error> {
        Err(Error::Conflict(conflict.info.clone()))
    }
}

/// Implement ConflictResolver for closures for convenience.
impl<Domain, Codomain, F> ConflictResolver<Domain, Codomain> for F
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    F: FnMut(&PotentialConflict<Domain, Codomain>) -> Result<Resolution<Codomain>, Error>,
{
    fn resolve(
        &mut self,
        conflict: &PotentialConflict<Domain, Codomain>,
    ) -> Result<Resolution<Codomain>, Error> {
        self(conflict)
    }
}
