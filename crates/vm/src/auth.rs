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

/// Compact execution authority facts for a VM activation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Authority {
    /// The object whose authority the activation executes under.
    ///
    /// This is the "task perms" object. It starts as the resolved verb owner and can be changed by
    /// `set_task_perms()`.
    pub principal: Obj,
    /// Cached flags for the principal, to avoid repeated DB lookups.
    pub principal_flags: BitEnum<ObjFlag>,
}

impl Authority {
    #[inline]
    #[must_use]
    pub fn new(principal: Obj, principal_flags: BitEnum<ObjFlag>) -> Self {
        Self {
            principal,
            principal_flags,
        }
    }

    #[inline]
    #[must_use]
    pub fn is_wizard(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Wizard)
    }

    #[inline]
    pub fn require_wizard(&self) -> Result<(), WorldStateError> {
        if self.is_wizard() {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    #[inline]
    #[must_use]
    pub fn is_programmer(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Programmer)
    }

    #[inline]
    pub fn require_programmer(&self) -> Result<(), WorldStateError> {
        if self.is_programmer() {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }

    #[inline]
    #[must_use]
    pub fn controls(&self, owner: &Obj) -> bool {
        self.is_wizard() || self.principal == *owner
    }

    #[inline]
    pub fn require_controls(&self, owner: &Obj) -> Result<(), WorldStateError> {
        if self.controls(owner) {
            return Ok(());
        }
        Err(WorldStateError::ObjectPermissionDenied)
    }
}
