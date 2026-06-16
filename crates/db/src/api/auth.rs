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
//! VM `TaskPermissions` records the object an activation runs as and any additive runtime
//! capability grants. `AuthContext` is the DB-side view of those permissions after resolving the
//! principal's current object flags, and it owns checks that depend on object, property, or verb
//! metadata.

use moor_common::{
    model::{
        CapabilityGrant, CapabilityGrants, ObjFlag, PropFlag, PropPerms, VerbFlag, WorldStateError,
    },
    util::BitEnum,
};
use moor_var::{Obj, Symbol};
use uuid::Uuid;

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

/// Resolved DB authorization facts for one operation.
///
/// `AuthContext` contains the current task authority principal and that object's flags as read from
/// the transaction at the point of the check. It deliberately does not know which builtin or
/// `WorldState` method is being executed; callers provide an `AuthRule` built from already-resolved
/// object, property, or verb metadata.
#[derive(Debug, Clone)]
pub(super) struct AuthContext {
    principal: DbAuthPrincipal,
    grants: CapabilityGrants,
}

/// A storage-layer authorization rule evaluated against a resolved DB principal.
///
/// These rules intentionally describe the authorization shape, not the operation name. WorldState
/// call sites should pass the owner, flags, or metadata they have already resolved and let
/// `AuthContext` choose the matching denial error:
///
/// - object-domain rules deny with `WorldStateError::ObjectPermissionDenied`
/// - property-domain rules deny with `WorldStateError::PropertyPermissionDenied`
/// - verb-domain rules deny with `WorldStateError::VerbPermissionDenied`
#[derive(Debug, Clone, Copy)]
pub(super) enum AuthRule<'a> {
    /// Principal must have the wizard bit for an object-domain operation.
    ObjectWizard,
    /// Principal must own an object-domain resource or have the wizard bit.
    ObjectOwnerOrWizard { owner: &'a Obj },
    /// Principal may move the given object.
    ObjectMove { obj: &'a Obj, owner: &'a Obj },
    /// Principal may recycle the given object.
    ObjectRecycle { obj: &'a Obj, owner: &'a Obj },
    /// Principal may change the given object's parent.
    ObjectChparent { obj: &'a Obj, owner: &'a Obj },
    /// Object owner, wizard bit, or all requested object flags authorize access.
    ///
    /// When more than one object flag is requested, public access requires every requested flag.
    ObjectAllows {
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    },
    /// Property owner, wizard bit, or the requested property flag authorizes access.
    PropertyAllows {
        obj: &'a Obj,
        prop: Symbol,
        property_perms: &'a PropPerms,
        required: PropFlag,
    },
    /// Principal may define a property on the given object.
    PropertyDefine {
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    },
    /// Principal may delete the named property from the given object.
    PropertyDelete {
        obj: &'a Obj,
        prop: Symbol,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    },
    /// Principal must have the wizard bit for a property operation.
    PropertyWizard,
    /// Principal must be the requested property owner or have the wizard bit.
    PropertyOwnerOrWizard { owner: &'a Obj },
    /// Non-wizards may not change property ownership to a different object.
    PropertyOwnerUnchangedOrWizard {
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    },
    /// Verb owner, wizard bit, or the requested verb flag authorizes access.
    VerbAllows {
        obj: &'a Obj,
        verb: Uuid,
        owner: &'a Obj,
        flags: BitEnum<VerbFlag>,
        required: VerbFlag,
    },
    /// Principal may add a verb to the given object.
    VerbAdd {
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    },
    /// Principal must be the requested verb owner or have the wizard bit.
    VerbOwnerOrWizard { owner: &'a Obj },
    /// Non-wizards may not change verb ownership to a different object.
    VerbOwnerUnchangedOrWizard {
        current_owner: &'a Obj,
        requested_owner: &'a Obj,
    },
    /// Principal may update code for the named verb.
    VerbProgram { obj: &'a Obj, verb: Uuid },
}

impl AuthRule<'_> {
    /// Principal must be a wizard for an object-domain operation.
    #[inline]
    pub(super) fn object_wizard() -> Self {
        Self::ObjectWizard
    }

    /// Principal must own an object-domain resource or be a wizard.
    #[inline]
    pub(super) fn object_owner_or_wizard(owner: &Obj) -> AuthRule<'_> {
        AuthRule::ObjectOwnerOrWizard { owner }
    }

    /// Principal must control the object or hold a move grant for it.
    #[inline]
    pub(super) fn object_move<'a>(obj: &'a Obj, owner: &'a Obj) -> AuthRule<'a> {
        AuthRule::ObjectMove { obj, owner }
    }

    /// Principal must control the object or hold a recycle grant for it.
    #[inline]
    pub(super) fn object_recycle<'a>(obj: &'a Obj, owner: &'a Obj) -> AuthRule<'a> {
        AuthRule::ObjectRecycle { obj, owner }
    }

    /// Principal must control the object or hold a chparent grant for it.
    #[inline]
    pub(super) fn object_chparent<'a>(obj: &'a Obj, owner: &'a Obj) -> AuthRule<'a> {
        AuthRule::ObjectChparent { obj, owner }
    }

    /// Principal must control the object owner or the object must expose all required flags.
    #[inline]
    pub(super) fn object_allows<'a>(
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
        required: BitEnum<ObjFlag>,
    ) -> AuthRule<'a> {
        AuthRule::ObjectAllows {
            obj,
            owner,
            flags,
            required,
        }
    }

    /// Principal must control the property owner or the property must expose the required flag.
    #[inline]
    pub(super) fn property_allows<'a>(
        obj: &'a Obj,
        prop: Symbol,
        property_perms: &'a PropPerms,
        required: PropFlag,
    ) -> AuthRule<'a> {
        AuthRule::PropertyAllows {
            obj,
            prop,
            property_perms,
            required,
        }
    }

    /// Principal must be able to define properties on the object.
    #[inline]
    pub(super) fn property_define<'a>(
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    ) -> AuthRule<'a> {
        AuthRule::PropertyDefine { obj, owner, flags }
    }

    /// Principal must be able to delete the named property from the object.
    #[inline]
    pub(super) fn property_delete<'a>(
        obj: &'a Obj,
        prop: Symbol,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    ) -> AuthRule<'a> {
        AuthRule::PropertyDelete {
            obj,
            prop,
            owner,
            flags,
        }
    }

    /// Principal must be a wizard for a property operation.
    #[inline]
    pub(super) fn property_wizard() -> Self {
        Self::PropertyWizard
    }

    /// Principal must be the requested property owner or a wizard.
    #[inline]
    pub(super) fn property_owner_or_wizard(owner: &Obj) -> AuthRule<'_> {
        AuthRule::PropertyOwnerOrWizard { owner }
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

    /// Principal must be the requested verb owner or a wizard.
    #[inline]
    pub(super) fn verb_owner_or_wizard(owner: &Obj) -> AuthRule<'_> {
        AuthRule::VerbOwnerOrWizard { owner }
    }

    /// Principal must control the verb owner or the verb must expose the required flag.
    #[inline]
    pub(super) fn verb_allows<'a>(
        obj: &'a Obj,
        verb: Uuid,
        owner: &'a Obj,
        flags: BitEnum<VerbFlag>,
        required: VerbFlag,
    ) -> AuthRule<'a> {
        AuthRule::VerbAllows {
            obj,
            verb,
            owner,
            flags,
            required,
        }
    }

    /// Principal must be able to add verbs to the object.
    #[inline]
    pub(super) fn verb_add<'a>(
        obj: &'a Obj,
        owner: &'a Obj,
        flags: BitEnum<ObjFlag>,
    ) -> AuthRule<'a> {
        AuthRule::VerbAdd { obj, owner, flags }
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

    /// Principal must be able to update code for the named verb.
    #[inline]
    pub(super) fn verb_program(obj: &Obj, verb: Uuid) -> AuthRule<'_> {
        AuthRule::VerbProgram { obj, verb }
    }

    #[inline]
    fn denial(self) -> WorldStateError {
        match self {
            Self::PropertyAllows { .. }
            | Self::PropertyDefine { .. }
            | Self::PropertyDelete { .. }
            | Self::PropertyWizard
            | Self::PropertyOwnerOrWizard { .. }
            | Self::PropertyOwnerUnchangedOrWizard { .. } => {
                WorldStateError::PropertyPermissionDenied
            }
            Self::VerbAllows { .. }
            | Self::VerbAdd { .. }
            | Self::VerbOwnerOrWizard { .. }
            | Self::VerbOwnerUnchangedOrWizard { .. }
            | Self::VerbProgram { .. } => WorldStateError::VerbPermissionDenied,
            Self::ObjectWizard
            | Self::ObjectOwnerOrWizard { .. }
            | Self::ObjectMove { .. }
            | Self::ObjectRecycle { .. }
            | Self::ObjectChparent { .. }
            | Self::ObjectAllows { .. } => WorldStateError::ObjectPermissionDenied,
        }
    }
}

impl AuthContext {
    /// Build DB-local authorization context from a resolved principal and its current flags.
    #[inline]
    pub(super) fn new(
        principal: Obj,
        principal_flags: BitEnum<ObjFlag>,
        grants: CapabilityGrants,
    ) -> Self {
        Self {
            principal: DbAuthPrincipal::new(principal, principal_flags),
            grants,
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

    #[inline]
    fn has_grant(&self, expected: CapabilityGrant) -> bool {
        self.grants.iter().any(|grant| grant == expected)
    }

    #[inline]
    fn has_object_grant(&self, obj: &Obj, required: BitEnum<ObjFlag>) -> bool {
        self.grants.iter().any(|grant| match grant {
            CapabilityGrant::ObjectRead(grant_obj) => {
                grant_obj == *obj && required == ObjFlag::Read.into()
            }
            CapabilityGrant::ObjectWrite(grant_obj) => {
                grant_obj == *obj && required == ObjFlag::Write.into()
            }
            _ => false,
        })
    }

    #[inline]
    fn has_property_grant(&self, obj: &Obj, prop: Symbol, required: PropFlag) -> bool {
        self.grants.iter().any(|grant| match grant {
            CapabilityGrant::PropertyRead {
                obj: grant_obj,
                prop: grant_prop,
            } => grant_obj == *obj && grant_prop == prop && required == PropFlag::Read,
            CapabilityGrant::PropertyWrite {
                obj: grant_obj,
                prop: grant_prop,
            } => grant_obj == *obj && grant_prop == prop && required == PropFlag::Write,
            _ => false,
        })
    }

    #[inline]
    fn has_verb_grant(&self, obj: &Obj, verb: Uuid, required: VerbFlag) -> bool {
        self.grants.iter().any(|grant| match grant {
            CapabilityGrant::VerbRead {
                obj: grant_obj,
                verb: grant_verb,
            } => grant_obj == *obj && grant_verb == verb && required == VerbFlag::Read,
            CapabilityGrant::VerbWrite {
                obj: grant_obj,
                verb: grant_verb,
            } => grant_obj == *obj && grant_verb == verb && required == VerbFlag::Write,
            CapabilityGrant::VerbCall {
                obj: grant_obj,
                verb: grant_verb,
            } => grant_obj == *obj && grant_verb == verb && required == VerbFlag::Exec,
            _ => false,
        })
    }

    #[inline]
    pub(super) fn has_verb_call_grant(&self, obj: &Obj, verb: Uuid) -> bool {
        self.has_grant(CapabilityGrant::VerbCall { obj: *obj, verb })
    }

    /// Evaluate a rule without mapping failure to an error.
    #[inline]
    pub(super) fn allows(&self, rule: AuthRule<'_>) -> bool {
        match rule {
            AuthRule::ObjectWizard => self.is_wizard(),
            AuthRule::ObjectOwnerOrWizard { owner } => self.controls_owner(owner),
            AuthRule::ObjectMove { obj, owner } => {
                self.controls_owner(owner) || self.has_grant(CapabilityGrant::ObjectMove(*obj))
            }
            AuthRule::ObjectRecycle { obj, owner } => {
                self.controls_owner(owner) || self.has_grant(CapabilityGrant::ObjectRecycle(*obj))
            }
            AuthRule::ObjectChparent { obj, owner } => {
                self.controls_owner(owner) || self.has_grant(CapabilityGrant::ObjectChparent(*obj))
            }
            AuthRule::ObjectAllows {
                obj,
                owner,
                flags,
                required,
            } => {
                self.controls_owner(owner)
                    || flags.contains_all(required)
                    || self.has_object_grant(obj, required)
            }
            AuthRule::PropertyDefine { obj, owner, flags } => {
                self.controls_owner(owner)
                    || flags.contains(ObjFlag::Write)
                    || self.has_object_grant(obj, ObjFlag::Write.into())
                    || self.has_grant(CapabilityGrant::PropertyDefine(*obj))
            }
            AuthRule::PropertyDelete {
                obj,
                prop,
                owner,
                flags,
            } => {
                self.controls_owner(owner)
                    || flags.contains(ObjFlag::Write)
                    || self.has_object_grant(obj, ObjFlag::Write.into())
                    || self.has_grant(CapabilityGrant::PropertyDelete { obj: *obj, prop })
            }
            AuthRule::PropertyAllows {
                obj,
                prop,
                property_perms,
                required,
            } => {
                self.is_wizard()
                    || self.principal.who == property_perms.owner()
                    || property_perms.flags().contains(required)
                    || self.has_property_grant(obj, prop, required)
            }
            AuthRule::PropertyWizard => self.is_wizard(),
            AuthRule::PropertyOwnerOrWizard { owner } => self.controls_owner(owner),
            AuthRule::PropertyOwnerUnchangedOrWizard {
                current_owner,
                requested_owner,
            } => self.is_wizard() || requested_owner == current_owner,
            AuthRule::VerbAllows {
                obj,
                verb,
                owner,
                flags,
                required,
            } => {
                self.principal.who == *owner
                    || self.is_wizard()
                    || flags.contains(required)
                    || self.has_verb_grant(obj, verb, required)
            }
            AuthRule::VerbAdd { obj, owner, flags } => {
                self.controls_owner(owner)
                    || flags.contains(ObjFlag::Write)
                    || self.has_object_grant(obj, ObjFlag::Write.into())
                    || self.has_grant(CapabilityGrant::VerbAdd(*obj))
            }
            AuthRule::VerbOwnerOrWizard { owner } => self.controls_owner(owner),
            AuthRule::VerbOwnerUnchangedOrWizard {
                current_owner,
                requested_owner,
            } => self.is_wizard() || requested_owner == current_owner,
            AuthRule::VerbProgram { obj, verb } => {
                self.is_wizard()
                    || self.principal.flags.contains(ObjFlag::Programmer)
                    || self.has_grant(CapabilityGrant::VerbProgram { obj: *obj, verb })
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
        AuthContext::new(Obj::mk_id(principal), flags, CapabilityGrants::empty())
    }

    fn context_with_grants(
        principal: i32,
        flags: BitEnum<ObjFlag>,
        grants: Vec<CapabilityGrant>,
    ) -> AuthContext {
        AuthContext::new(
            Obj::mk_id(principal),
            flags,
            CapabilityGrants::from_vec(grants),
        )
    }

    #[test]
    fn context_exposes_resolved_principal_facts() {
        let flags = BitEnum::new_with(ObjFlag::Wizard) | ObjFlag::Programmer;
        let auth = context(1, flags);

        assert_eq!(auth.principal(), Obj::mk_id(1));
        assert_eq!(auth.principal_flags(), flags);
        assert!(auth.allows(AuthRule::object_wizard()));
    }

    #[test]
    fn object_allows_owner_wizard_or_object_flag() {
        let obj = Obj::mk_id(10);
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);
        let public_read = BitEnum::new_with(ObjFlag::Read);
        let public_read_write = BitEnum::new_with(ObjFlag::Read) | ObjFlag::Write;

        assert!(context(1, BitEnum::new()).allows(AuthRule::object_allows(
            &obj,
            &owner,
            BitEnum::new(),
            ObjFlag::Read.into()
        )));
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard)).allows(AuthRule::object_allows(
                &obj,
                &owner,
                BitEnum::new(),
                ObjFlag::Read.into()
            ))
        );
        assert!(context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &obj,
            &owner,
            public_read,
            ObjFlag::Read.into()
        )));
        assert!(!context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &obj,
            &owner,
            BitEnum::new(),
            ObjFlag::Read.into()
        )));
        assert!(!context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &obj,
            &owner,
            public_read,
            public_read_write
        )));
        assert!(context(2, BitEnum::new()).allows(AuthRule::object_allows(
            &obj,
            &owner,
            public_read_write,
            public_read_write
        )));
        assert!(
            context(2, BitEnum::new())
                .require(AuthRule::object_owner_or_wizard(&other))
                .is_ok()
        );
    }

    #[test]
    fn property_allows_owner_wizard_or_property_flag() {
        let obj = Obj::mk_id(10);
        let prop = Symbol::mk("p");
        let propperms = PropPerms::new(Obj::mk_id(1), BitEnum::new_with(PropFlag::Read));

        assert!(context(1, BitEnum::new()).allows(AuthRule::property_allows(
            &obj,
            prop,
            &propperms,
            PropFlag::Write
        )));
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard)).allows(AuthRule::property_allows(
                &obj,
                prop,
                &propperms,
                PropFlag::Write
            ))
        );
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::property_wizard())
                .is_ok()
        );
        assert!(context(2, BitEnum::new()).allows(AuthRule::property_allows(
            &obj,
            prop,
            &propperms,
            PropFlag::Read
        )));
        assert!(
            !context(2, BitEnum::new()).allows(AuthRule::property_allows(
                &obj,
                prop,
                &propperms,
                PropFlag::Write
            ))
        );
        assert!(
            context(2, BitEnum::new())
                .require(AuthRule::property_allows(
                    &obj,
                    prop,
                    &propperms,
                    PropFlag::Write
                ))
                .is_err()
        );
    }

    #[test]
    fn property_owner_rules_allow_self_or_wizard_and_reject_transfer() {
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);

        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::property_owner_or_wizard(&owner))
                .is_ok()
        );
        assert!(
            context(3, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::property_owner_or_wizard(&owner))
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::property_owner_unchanged_or_wizard(&owner, &owner))
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::property_owner_unchanged_or_wizard(&owner, &other))
                .is_err()
        );
        assert!(
            context(3, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::property_owner_unchanged_or_wizard(&owner, &other))
                .is_ok()
        );
    }

    #[test]
    fn verb_allows_owner_wizard_or_verb_flag() {
        let obj = Obj::mk_id(10);
        let verb = Uuid::from_u128(1);
        let owner = Obj::mk_id(1);
        let readable = BitEnum::new_with(VerbFlag::Read);

        assert!(context(1, BitEnum::new()).allows(AuthRule::verb_allows(
            &obj,
            verb,
            &owner,
            BitEnum::new(),
            VerbFlag::Write
        )));
        assert!(
            context(2, BitEnum::new_with(ObjFlag::Wizard)).allows(AuthRule::verb_allows(
                &obj,
                verb,
                &owner,
                BitEnum::new(),
                VerbFlag::Write
            ))
        );
        assert!(context(2, BitEnum::new()).allows(AuthRule::verb_allows(
            &obj,
            verb,
            &owner,
            readable,
            VerbFlag::Read
        )));
        assert!(!context(2, BitEnum::new()).allows(AuthRule::verb_allows(
            &obj,
            verb,
            &owner,
            readable,
            VerbFlag::Write
        )));
    }

    #[test]
    fn verb_owner_rules_allow_self_or_wizard_and_reject_transfer() {
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);

        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::verb_owner_or_wizard(&owner))
                .is_ok()
        );
        assert!(
            context(3, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::verb_owner_or_wizard(&owner))
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::verb_owner_unchanged_or_wizard(&owner, &owner))
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::verb_owner_unchanged_or_wizard(&owner, &other))
                .is_err()
        );
        assert!(
            context(3, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::verb_owner_unchanged_or_wizard(&owner, &other))
                .is_ok()
        );
    }

    #[test]
    fn verb_program_allows_programmer_wizard_or_grant() {
        let obj = Obj::mk_id(10);
        let verb = Uuid::from_u128(2);

        assert!(
            context(1, BitEnum::new_with(ObjFlag::Programmer))
                .require(AuthRule::verb_program(&obj, verb))
                .is_ok()
        );
        assert!(
            context(1, BitEnum::new_with(ObjFlag::Wizard))
                .require(AuthRule::verb_program(&obj, verb))
                .is_ok()
        );
        assert!(
            context_with_grants(
                1,
                BitEnum::new(),
                vec![CapabilityGrant::VerbProgram { obj, verb }]
            )
            .require(AuthRule::verb_program(&obj, verb))
            .is_ok()
        );
        assert!(
            context(1, BitEnum::new())
                .require(AuthRule::verb_program(&obj, verb))
                .is_err()
        );
    }

    #[test]
    fn require_returns_domain_specific_denial() {
        let obj = Obj::mk_id(10);
        let prop = Symbol::mk("p");
        let verb = Uuid::from_u128(3);
        let owner = Obj::mk_id(1);
        let other = Obj::mk_id(2);
        let propperms = PropPerms::new(owner, BitEnum::new());

        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::object_wizard()),
            Err(WorldStateError::ObjectPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::object_owner_or_wizard(&owner)),
            Err(WorldStateError::ObjectPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::object_move(&obj, &owner)),
            Err(WorldStateError::ObjectPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::property_allows(
                &obj,
                prop,
                &propperms,
                PropFlag::Write
            )),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::property_owner_or_wizard(&owner)),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::property_wizard()),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::property_delete(
                &obj,
                prop,
                &owner,
                BitEnum::new()
            )),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new())
                .require(AuthRule::property_owner_unchanged_or_wizard(&owner, &other)),
            Err(WorldStateError::PropertyPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::verb_allows(
                &obj,
                verb,
                &owner,
                BitEnum::new(),
                VerbFlag::Write
            )),
            Err(WorldStateError::VerbPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::verb_owner_or_wizard(&owner)),
            Err(WorldStateError::VerbPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new()).require(AuthRule::verb_program(&obj, verb)),
            Err(WorldStateError::VerbPermissionDenied)
        ));
        assert!(matches!(
            context(3, BitEnum::new())
                .require(AuthRule::verb_owner_unchanged_or_wizard(&owner, &other)),
            Err(WorldStateError::VerbPermissionDenied)
        ));
    }

    #[test]
    fn grants_add_object_property_and_verb_access() {
        let obj = Obj::mk_id(10);
        let owner = Obj::mk_id(1);
        let prop = Symbol::mk("p");
        let verb = Uuid::from_u128(4);
        let propperms = PropPerms::new(owner, BitEnum::new());

        assert!(
            context_with_grants(2, BitEnum::new(), vec![CapabilityGrant::ObjectRead(obj)]).allows(
                AuthRule::object_allows(&obj, &owner, BitEnum::new(), ObjFlag::Read.into())
            )
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::PropertyWrite { obj, prop }]
            )
            .allows(AuthRule::property_allows(
                &obj,
                prop,
                &propperms,
                PropFlag::Write
            ))
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::VerbRead { obj, verb }]
            )
            .allows(AuthRule::verb_allows(
                &obj,
                verb,
                &owner,
                BitEnum::new(),
                VerbFlag::Read
            ))
        );
    }

    #[test]
    fn grants_add_object_operation_access() {
        let obj = Obj::mk_id(10);
        let owner = Obj::mk_id(1);

        assert!(
            !context(2, BitEnum::new()).allows(AuthRule::object_move(&obj, &owner)),
            "move should not be granted by default"
        );
        assert!(
            context_with_grants(2, BitEnum::new(), vec![CapabilityGrant::ObjectMove(obj)])
                .allows(AuthRule::object_move(&obj, &owner))
        );
        assert!(
            context_with_grants(2, BitEnum::new(), vec![CapabilityGrant::ObjectRecycle(obj)])
                .allows(AuthRule::object_recycle(&obj, &owner))
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::ObjectChparent(obj)]
            )
            .allows(AuthRule::object_chparent(&obj, &owner))
        );
        assert!(
            !context_with_grants(2, BitEnum::new(), vec![CapabilityGrant::ObjectWrite(obj)])
                .allows(AuthRule::object_recycle(&obj, &owner)),
            "object_write should not authorize owner-only recycle"
        );
    }

    #[test]
    fn grants_add_property_operation_access() {
        let obj = Obj::mk_id(10);
        let owner = Obj::mk_id(1);
        let prop = Symbol::mk("p");

        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::PropertyDefine(obj)]
            )
            .allows(AuthRule::property_define(&obj, &owner, BitEnum::new()))
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::PropertyDelete { obj, prop }]
            )
            .allows(AuthRule::property_delete(
                &obj,
                prop,
                &owner,
                BitEnum::new()
            ))
        );
        assert!(
            context(2, BitEnum::new()).allows(AuthRule::property_define(
                &obj,
                &owner,
                BitEnum::new_with(ObjFlag::Write)
            )),
            "public object write still authorizes property definition"
        );
        assert!(
            !context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::PropertyDefine(obj)]
            )
            .allows(AuthRule::property_delete(
                &obj,
                prop,
                &owner,
                BitEnum::new()
            )),
            "property_define should not authorize property_delete"
        );
    }

    #[test]
    fn grants_add_verb_operation_access() {
        let obj = Obj::mk_id(10);
        let owner = Obj::mk_id(1);
        let verb = Uuid::from_u128(5);

        assert!(
            context_with_grants(2, BitEnum::new(), vec![CapabilityGrant::VerbAdd(obj)])
                .allows(AuthRule::verb_add(&obj, &owner, BitEnum::new()))
        );
        assert!(
            context(2, BitEnum::new()).allows(AuthRule::verb_add(
                &obj,
                &owner,
                BitEnum::new_with(ObjFlag::Write)
            )),
            "public object write still authorizes verb addition"
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::VerbProgram { obj, verb }]
            )
            .allows(AuthRule::verb_program(&obj, verb))
        );
        assert!(
            context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::VerbCall { obj, verb }]
            )
            .allows(AuthRule::verb_allows(
                &obj,
                verb,
                &owner,
                BitEnum::new(),
                VerbFlag::Exec
            ))
        );
        assert!(
            !context_with_grants(
                2,
                BitEnum::new(),
                vec![CapabilityGrant::VerbCall { obj, verb }]
            )
            .allows(AuthRule::verb_allows(
                &obj,
                verb,
                &owner,
                BitEnum::new(),
                VerbFlag::Read
            )),
            "verb_call should not authorize verb read"
        );
    }
}
