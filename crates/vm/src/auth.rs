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

use moor_common::{
    model::{ObjFlag, WorldStateError},
    util::BitEnum,
};
use moor_var::Obj;

/// Effective task permissions for a VM activation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TaskPermissions {
    /// The object whose permissions the activation executes under.
    ///
    /// This starts as the resolved verb owner. The MOO-visible `set_task_perms()` builtin changes
    /// this principal for the current task.
    principal: Obj,
    /// Cached flags for the principal, to avoid repeated DB lookups.
    principal_flags: BitEnum<ObjFlag>,
}

impl TaskPermissions {
    /// Build task permissions from a principal and the principal's cached object flags.
    #[inline]
    #[must_use]
    pub fn new(principal: Obj, principal_flags: BitEnum<ObjFlag>) -> Self {
        Self {
            principal,
            principal_flags,
        }
    }

    /// Object whose permissions the activation runs under.
    #[inline]
    #[must_use]
    pub fn principal(&self) -> Obj {
        self.principal
    }

    /// Cached object flags for the permissions principal.
    #[inline]
    #[must_use]
    pub fn principal_flags(&self) -> BitEnum<ObjFlag> {
        self.principal_flags
    }

    /// Whether the permissions principal has the wizard bit.
    #[inline]
    #[must_use]
    pub fn is_wizard(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Wizard)
    }

    /// Require wizard permissions for operations that do not have an owner fallback.
    #[inline]
    pub fn require_wizard(&self) -> Result<(), WorldStateError> {
        if self.is_wizard() {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    /// Whether the permissions principal has the programmer bit.
    #[inline]
    #[must_use]
    pub fn is_programmer(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Programmer)
    }

    /// Require programmer permissions for operations that compile or update executable code.
    #[inline]
    pub fn require_programmer(&self) -> Result<(), WorldStateError> {
        if self.is_programmer() {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    /// Whether these task permissions control an owner-only operation.
    #[inline]
    #[must_use]
    pub fn controls(&self, owner: &Obj) -> bool {
        self.is_wizard() || self.principal == *owner
    }

    /// Require owner-or-wizard permissions.
    #[inline]
    pub fn require_controls(&self, owner: &Obj) -> Result<(), WorldStateError> {
        if self.controls(owner) {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn authority(principal: i32, flags: BitEnum<ObjFlag>) -> TaskPermissions {
        TaskPermissions::new(Obj::mk_id(principal), flags)
    }

    #[test]
    fn wizard_controls_any_owner() {
        let auth = authority(1, BitEnum::new_with(ObjFlag::Wizard));

        assert!(auth.is_wizard());
        assert!(auth.controls(&Obj::mk_id(2)));
        assert!(auth.require_controls(&Obj::mk_id(2)).is_ok());
    }

    #[test]
    fn non_wizard_controls_only_self() {
        let auth = authority(1, BitEnum::new());

        assert!(auth.controls(&Obj::mk_id(1)));
        assert!(!auth.controls(&Obj::mk_id(2)));
        assert!(auth.require_controls(&Obj::mk_id(2)).is_err());
    }

    #[test]
    fn programmer_does_not_imply_wizard() {
        let auth = authority(1, BitEnum::new_with(ObjFlag::Programmer));

        assert!(auth.is_programmer());
        assert!(!auth.is_wizard());
        assert!(auth.require_programmer().is_ok());
        assert!(auth.require_wizard().is_err());
    }
}
