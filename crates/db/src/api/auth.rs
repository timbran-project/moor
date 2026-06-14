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
struct DbAuthPrincipal {
    who: Obj,
    flags: BitEnum<ObjFlag>,
}

impl DbAuthPrincipal {
    #[inline]
    fn new(who: Obj, flags: BitEnum<ObjFlag>) -> Self {
        Self { who, flags }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) struct AuthContext {
    principal: DbAuthPrincipal,
}

/// A storage-layer authorization rule evaluated against a resolved DB principal.
///
/// These rules intentionally describe the authorization shape, not the operation name. WorldState
/// call sites should pass the owner, flags, or metadata they have already resolved and let
/// `AuthContext` choose the matching denial error.
#[derive(Debug, Clone, Copy)]
pub(super) enum AuthRule<'a> {
    /// Principal must have the wizard bit.
    Wizard,
    /// Principal must be the owner or have the wizard bit.
    OwnerOrWizard { owner: &'a Obj },
    /// Object owner, wizard bit, or all requested object flags authorize access.
    ObjectAllows {
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    },
    /// Property owner, wizard bit, or the requested property flag authorizes access.
    PropertyAllows {
        perms: &'a PropPerms,
        required: PropFlag,
    },
    /// Principal must have the wizard bit for a property operation.
    PropertyWizard,
    /// Non-wizards may not change property ownership to a different object.
    PropertyOwnerUnchangedOrWizard {
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    },
    /// Verb owner, wizard bit, or the requested verb flag authorizes access.
    VerbAllows {
        owner: &'a Obj,
        flags: BitEnum<VerbFlag>,
        required: VerbFlag,
    },
    /// Non-wizards may not change verb ownership to a different object.
    VerbOwnerUnchangedOrWizard {
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    },
    /// Updating verb code requires programmer or wizard authority.
    VerbProgrammerOrWizard,
}

impl AuthRule<'_> {
    /// Principal must be a wizard.
    #[inline]
    pub(super) fn wizard() -> Self {
        Self::Wizard
    }

    /// Principal must be the owner or a wizard.
    #[inline]
    pub(super) fn owner_or_wizard(owner: &Obj) -> AuthRule<'_> {
        AuthRule::OwnerOrWizard { owner }
    }

    /// Principal must control the object owner or the object must expose all required flags.
    #[inline]
    pub(super) fn object_allows(
        owner: &Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    ) -> AuthRule<'_> {
        AuthRule::ObjectAllows {
            owner,
            flags,
            required,
        }
    }

    /// Principal must control the property owner or the property must expose the required flag.
    #[inline]
    pub(super) fn property_allows(perms: &PropPerms, required: PropFlag) -> AuthRule<'_> {
        AuthRule::PropertyAllows { perms, required }
    }

    /// Principal must be a wizard for a property operation.
    #[inline]
    pub(super) fn property_wizard() -> Self {
        Self::PropertyWizard
    }

    /// Principal may leave the property owner unchanged; only wizards may change it.
    #[inline]
    pub(super) fn property_owner_unchanged_or_wizard<'a>(
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    ) -> AuthRule<'a> {
        AuthRule::PropertyOwnerUnchangedOrWizard {
            current_owner,
            requested_owner,
        }
    }

    /// Principal must control the verb owner or the verb must expose the required flag.
    #[inline]
    pub(super) fn verb_allows(
        owner: &Obj,
        flags: BitEnum<VerbFlag>,
        required: VerbFlag,
    ) -> AuthRule<'_> {
        AuthRule::VerbAllows {
            owner,
            flags,
            required,
        }
    }

    /// Principal may leave the verb owner unchanged; only wizards may change it.
    #[inline]
    pub(super) fn verb_owner_unchanged_or_wizard<'a>(
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    ) -> AuthRule<'a> {
        AuthRule::VerbOwnerUnchangedOrWizard {
            current_owner,
            requested_owner,
        }
    }

    /// Principal must be a programmer or wizard.
    #[inline]
    pub(super) fn verb_programmer_or_wizard() -> Self {
        Self::VerbProgrammerOrWizard
    }

    #[inline]
    fn denial(self) -> WorldStateError {
        match self {
            Self::PropertyAllows { .. }
            | Self::PropertyWizard
            | Self::PropertyOwnerUnchangedOrWizard { .. } => {
                WorldStateError::PropertyPermissionDenied
            }
            Self::VerbAllows { .. }
            | Self::VerbOwnerUnchangedOrWizard { .. }
            | Self::VerbProgrammerOrWizard => WorldStateError::VerbPermissionDenied,
            Self::Wizard | Self::OwnerOrWizard { .. } | Self::ObjectAllows { .. } => {
                WorldStateError::ObjectPermissionDenied
            }
        }
    }
}

impl AuthContext {
    /// Build DB-local authorization context from a resolved principal and its current flags.
    #[inline]
    pub(super) fn new(principal: Obj, principal_flags: BitEnum<ObjFlag>) -> Self {
        Self {
            principal: DbAuthPrincipal::new(principal, principal_flags),
        }
    }

    #[inline]
    fn is_wizard(&self) -> bool {
        self.principal.flags.contains(ObjFlag::Wizard)
    }

    /// Principal object this context evaluates rules against.
    #[inline]
    pub(super) fn principal(&self) -> Obj {
        self.principal.who
    }

    /// Current flags for the principal object.
    #[inline]
    pub(super) fn principal_flags(&self) -> BitEnum<ObjFlag> {
        self.principal.flags
    }

    #[inline]
    fn controls_owner(&self, owner: &Obj) -> bool {
        self.is_wizard() || self.principal.who == *owner
    }

    /// Evaluate a rule without mapping failure to an error.
    #[inline]
    pub(super) fn allows(&self, rule: AuthRule<'_>) -> bool {
        match rule {
            AuthRule::Wizard => self.is_wizard(),
            AuthRule::OwnerOrWizard { owner } => self.controls_owner(owner),
            AuthRule::ObjectAllows {
                owner,
                flags,
                required,
            } => self.controls_owner(owner) || flags.contains_all(required),
            AuthRule::PropertyAllows { perms, required } => {
                self.is_wizard()
                    || self.principal.who == perms.owner()
                    || perms.flags().contains(required)
            }
            AuthRule::PropertyWizard => self.is_wizard(),
            AuthRule::PropertyOwnerUnchangedOrWizard {
                current_owner,
                requested_owner,
            } => self.is_wizard() || requested_owner == current_owner,
            AuthRule::VerbAllows {
                owner,
                flags,
                required,
            } => self.principal.who == *owner || self.is_wizard() || flags.contains(required),
            AuthRule::VerbOwnerUnchangedOrWizard {
                current_owner,
                requested_owner,
            } => self.is_wizard() || requested_owner == current_owner,
            AuthRule::VerbProgrammerOrWizard => {
                self.is_wizard() || self.principal.flags.contains(ObjFlag::Programmer)
            }
        }
    }

    /// Require a rule and return the permission error matching its object/property/verb domain.
    #[inline]
    pub(super) fn require(&self, rule: AuthRule<'_>) -> Result<(), WorldStateError> {
        if self.allows(rule) {
            return Ok(());
        }
        Err(rule.denial())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context(principal: i32, flags: BitEnum<ObjFlag>) -> AuthContext {
        AuthContext::new(Obj::mk_id(principal), flags)
    }

    #[test]
    fn context_exposes_resolved_principal_facts() {
        let flags = BitEnum::new_with(ObjFlag::Wizard) | ObjFlag::Programmer;
        let auth = context(1, flags);

        assert_eq!(auth.principal(), Obj::mk_id(1));
        assert_eq!(auth.principal_flags(), flags);
        assert!(auth.allows(AuthRule::wizard()));
    }

    #[test]
    fn object_allows_owner_wizard_or_object_flag() {
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);
        let public_read = BitEnum::new_with(ObjFlag::Read);

        assert!(context(1, BitEnum::new()).allows(AuthRule::object_allows(
            &owner,
            BitEnum::new(),
            ObjFlag::Read.into()
        )));
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard)).allows(AuthRule::object_allows(
                &owner,
                BitEnum::new(),
                ObjFlag::Read.into()
            ))
        );
        assert!(context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &owner,
            public_read,
            ObjFlag::Read.into()
        )));
        assert!(!context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &owner,
            BitEnum::new(),
            ObjFlag::Read.into()
        )));
        assert!(
            context(2, BitEnum::new())
                .require(AuthRule::owner_or_wizard(&other))
                .is_ok()
        );
    }

    #[test]
    fn property_allows_owner_wizard_or_property_flag() {
        let propperms = PropPerms::new(Obj::mk_id(1), BitEnum::new_with(PropFlag::Read));

        assert!(
            context(1, BitEnum::new())
                .allows(AuthRule::property_allows(&propperms, PropFlag::Write))
        );
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard))
                .allows(AuthRule::property_allows(&propperms, PropFlag::Write))
        );
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::property_wizard())
                .is_ok()
        );
        assert!(
            context(2, BitEnum::new())
                .allows(AuthRule::property_allows(&propperms, PropFlag::Read))
        );
        assert!(
            !context(2, BitEnum::new())
                .allows(AuthRule::property_allows(&propperms, PropFlag::Write))
        );
        assert!(
            context(2, BitEnum::new())
                .require(AuthRule::property_allows(&propperms, PropFlag::Write))
                .is_err()
        );
    }

    #[test]
    fn verb_code_write_requires_programmer_or_wizard() {
        assert!(
            context(1, BitEnum::new_with(ObjFlag::Programmer))
                .require(AuthRule::verb_programmer_or_wizard())
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::verb_programmer_or_wizard())
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::verb_programmer_or_wizard())
                .is_err()
        );
    }

    #[test]
    fn require_returns_domain_specific_denial() {
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);
        let propperms = PropPerms::new(owner, BitEnum::new());

        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::owner_or_wizard(&owner)),
            Err(WorldStateError::ObjectPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new())
                .require(AuthRule::property_allows(&propperms, PropFlag::Write)),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::property_wizard()),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new())
                .require(AuthRule::property_owner_unchanged_or_wizard(&owner, &other)),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::verb_allows(
                &owner,
                BitEnum::new(),
                VerbFlag::Write
            )),
            Err(WorldStateError::VerbPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new())
                .require(AuthRule::verb_owner_unchanged_or_wizard(&owner, &other)),
            Err(WorldStateError::VerbPermissionDenied)
        ));
    }
}
