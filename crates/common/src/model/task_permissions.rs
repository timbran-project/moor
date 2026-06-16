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

use std::sync::Arc;

use crate::{model::ObjFlag, util::BitEnum};
use moor_var::{Obj, Symbol};
use uuid::Uuid;

/// A normalized runtime capability grant.
///
/// These are additive rights attached to task permissions after trusted code has validated a
/// higher-level capability artifact. They are not bearer tokens and do not encode revocation or
/// expiration policy themselves.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CapabilityGrant {
    ObjectRead(Obj),
    ObjectWrite(Obj),
    ObjectRename(Obj),
    ObjectMove(Obj),
    ObjectRecycle(Obj),
    ObjectChparent(Obj),
    PropertyRead { obj: Obj, prop: Symbol },
    PropertyWrite { obj: Obj, prop: Symbol },
    PropertyDefine(Obj),
    PropertyDelete { obj: Obj, prop: Symbol },
    VerbRead { obj: Obj, verb: Uuid },
    VerbWrite { obj: Obj, verb: Uuid },
    VerbProgram { obj: Obj, verb: Uuid },
    VerbAdd(Obj),
    VerbCall { obj: Obj, verb: Uuid },
    ObjectList,
    BuiltinCall(Symbol),
}

/// Additive runtime capability grants attached to an activation's task permissions.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CapabilityGrants {
    grants: Arc<[CapabilityGrant]>,
}

impl CapabilityGrants {
    #[inline]
    #[must_use]
    pub fn empty() -> Self {
        Self::default()
    }

    #[inline]
    #[must_use]
    pub fn from_vec(grants: Vec<CapabilityGrant>) -> Self {
        Self {
            grants: Arc::from(grants.into_boxed_slice()),
        }
    }

    #[inline]
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.grants.is_empty()
    }

    #[inline]
    pub fn iter(&self) -> impl Iterator<Item = CapabilityGrant> + '_ {
        self.grants.iter().copied()
    }
}

/// Effective task permissions for a VM activation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskPermissions {
    /// The object whose permissions the activation executes under.
    ///
    /// This starts as the resolved verb owner. The MOO-visible `set_task_perms()` builtin changes
    /// this principal for the current task.
    principal: Obj,
    /// Cached flags for the principal, to avoid repeated DB lookups in VM-local checks.
    principal_flags: BitEnum<ObjFlag>,
    /// Runtime capability grants active for this activation.
    grants: CapabilityGrants,
}

impl TaskPermissions {
    /// Build task permissions from a principal and the principal's cached object flags.
    #[inline]
    #[must_use]
    pub fn new(principal: Obj, principal_flags: BitEnum<ObjFlag>) -> Self {
        Self::with_grants(principal, principal_flags, CapabilityGrants::empty())
    }

    /// Build task permissions with additive runtime capability grants.
    #[inline]
    #[must_use]
    pub fn with_grants(
        principal: Obj,
        principal_flags: BitEnum<ObjFlag>,
        grants: CapabilityGrants,
    ) -> Self {
        Self {
            principal,
            principal_flags,
            grants,
        }
    }

    /// Return these permissions with refreshed principal flags and the same grants.
    #[inline]
    #[must_use]
    pub fn with_principal_flags(&self, principal_flags: BitEnum<ObjFlag>) -> Self {
        Self {
            principal: self.principal,
            principal_flags,
            grants: self.grants.clone(),
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

    /// Additive runtime capability grants active for this activation.
    #[inline]
    #[must_use]
    pub fn grants(&self) -> &CapabilityGrants {
        &self.grants
    }

    /// Whether these task permissions include an explicit grant to call a builtin.
    #[inline]
    #[must_use]
    pub fn can_call_builtin(&self, builtin: Symbol) -> bool {
        self.grants
            .iter()
            .any(|grant| matches!(grant, CapabilityGrant::BuiltinCall(grant) if grant == builtin))
    }

    /// Whether these task permissions include an explicit grant to enumerate all objects.
    #[inline]
    #[must_use]
    pub fn can_list_objects(&self) -> bool {
        self.grants
            .iter()
            .any(|grant| matches!(grant, CapabilityGrant::ObjectList))
    }

    /// Whether the permissions principal has the wizard bit.
    #[inline]
    #[must_use]
    pub fn is_wizard(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Wizard)
    }

    /// Require wizard permissions for operations that do not have an owner fallback.
    #[inline]
    pub fn require_wizard(&self) -> Result<(), crate::model::WorldStateError> {
        if self.is_wizard() {
            return Ok(());
        }
        Err(crate::model::WorldStateError::ObjectPermissionDenied)
    }

    /// Whether the permissions principal has the programmer bit.
    #[inline]
    #[must_use]
    pub fn is_programmer(&self) -> bool {
        self.principal_flags.contains(ObjFlag::Programmer)
    }

    /// Require programmer permissions for operations that compile or update executable code.
    #[inline]
    pub fn require_programmer(&self) -> Result<(), crate::model::WorldStateError> {
        if self.is_programmer() {
            return Ok(());
        }
        Err(crate::model::WorldStateError::ObjectPermissionDenied)
    }

    /// Whether these task permissions control an owner-only operation.
    #[inline]
    #[must_use]
    pub fn controls(&self, owner: &Obj) -> bool {
        self.is_wizard() || self.principal == *owner
    }

    /// Require owner-or-wizard permissions.
    #[inline]
    pub fn require_controls(&self, owner: &Obj) -> Result<(), crate::model::WorldStateError> {
        if self.controls(owner) {
            return Ok(());
        }
        Err(crate::model::WorldStateError::ObjectPermissionDenied)
    }
}
