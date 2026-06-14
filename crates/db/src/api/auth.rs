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

//! Database-local authorization predicates.
//!
//! VM `Authority` records the object an activation runs as. `AuthContext` is the DB-side view of
//! that authority after resolving the principal's current object flags, and it owns checks that
//! depend on object, property, or verb metadata.

use moor_common::{
    model::{ObjFlag, PropFlag, PropPerms, VerbFlag, WorldStateError},
    util::BitEnum,
};
use moor_var::Obj;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub(crate) struct DbAuthPrincipal {
    pub(crate) who: Obj,
    pub(crate) flags: BitEnum<ObjFlag>,
}

impl DbAuthPrincipal {
    #[inline]
    pub(crate) fn new(who: Obj, flags: BitEnum<ObjFlag>) -> Self {
        Self { who, flags }
    }
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct AuthContext {
    principal: DbAuthPrincipal,
}

impl AuthContext {
    #[inline]
    pub(crate) fn new(principal: DbAuthPrincipal) -> Self {
        Self { principal }
    }

    #[inline]
    pub(crate) fn is_wizard(&self) -> bool {
        self.principal.flags.contains(ObjFlag::Wizard)
    }

    #[inline]
    pub(crate) fn who(&self) -> Obj {
        self.principal.who
    }

    #[inline]
    pub(crate) fn flags(&self) -> BitEnum<ObjFlag> {
        self.principal.flags
    }

    #[inline]
    pub(crate) fn require_wizard(&self) -> Result<(), WorldStateError> {
        if self.is_wizard() {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    #[inline]
    pub(crate) fn controls_owner(&self, owner: &Obj) -> bool {
        self.is_wizard() || self.principal.who == *owner
    }

    #[inline]
    pub(crate) fn require_owner_or_wizard(&self, owner: &Obj) -> Result<(), WorldStateError> {
        if self.controls_owner(owner) {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    #[inline]
    pub(crate) fn object_allows(
        &self,
        owner: &Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    ) -> bool {
        self.controls_owner(owner) || flags.contains_all(required)
    }

    #[inline]
    pub(crate) fn require_object_allows(
        &self,
        owner: &Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    ) -> Result<(), WorldStateError> {
        if self.object_allows(owner, flags, required) {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    #[inline]
    pub(crate) fn property_allows(&self, propperms: &PropPerms, required: PropFlag) -> bool {
        self.is_wizard()
            || self.principal.who == propperms.owner()
            || propperms.flags().contains(required)
    }

    #[inline]
    pub(crate) fn require_property_allows(
        &self,
        propperms: &PropPerms,
        required: PropFlag,
    ) -> Result<(), WorldStateError> {
        if self.property_allows(propperms, required) {
            return Ok(());
        }
        Err(WorldStateError::PropertyPermissionDenied)
    }

    #[inline]
    pub(crate) fn require_property_owner_unchanged_or_wizard(
        &self,
        current_owner: &Obj,
        requested_owner: &Obj,
    ) -> Result<(), WorldStateError> {
        if self.is_wizard() || requested_owner == current_owner {
            return Ok(());
        }
        Err(WorldStateError::PropertyPermissionDenied)
    }

    #[inline]
    pub(crate) fn require_verb_allows(
        &self,
        verb_owner: &Obj,
        verb_flags: BitEnum<VerbFlag>,
        required: VerbFlag,
    ) -> Result<(), WorldStateError> {
        if self.principal.who == *verb_owner || self.is_wizard() || verb_flags.contains(required) {
            return Ok(());
        }
        Err(WorldStateError::VerbPermissionDenied)
    }

    #[inline]
    pub(crate) fn require_verb_owner_unchanged_or_wizard(
        &self,
        current_owner: &Obj,
        requested_owner: &Obj,
    ) -> Result<(), WorldStateError> {
        if self.is_wizard() || requested_owner == current_owner {
            return Ok(());
        }
        Err(WorldStateError::VerbPermissionDenied)
    }

    #[inline]
    pub(crate) fn require_verb_programmer_or_wizard(&self) -> Result<(), WorldStateError> {
        if self.is_wizard() || self.principal.flags.contains(ObjFlag::Programmer) {
            return Ok(());
        }
        Err(WorldStateError::VerbPermissionDenied)
    }
}
