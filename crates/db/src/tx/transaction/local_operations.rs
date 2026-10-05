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

use super::{Op, OpType};
use crate::tx::{RelationCodomain, RelationDomain};
use ahash::AHasher;
use std::{cell::RefCell, collections::HashMap, hash::BuildHasherDefault, ops::Deref};

type OperationMap<D, C> = HashMap<D, Op<C>, BuildHasherDefault<AHasher>>;
type CodomainCache<D, C> = RefCell<Option<Vec<(C, Vec<D>)>>>;

/// All mutable access invalidates the derived index before returning a borrow.
/// The map has no DerefMut implementation, so callers cannot bypass invalidation.
pub(super) struct LocalOperations<D, C: RelationCodomain> {
    entries: OperationMap<D, C>,
    codomains: CodomainCache<D, C>,
}

impl<D: RelationDomain, C: RelationCodomain> LocalOperations<D, C> {
    pub(super) fn new() -> Self {
        Self {
            entries: HashMap::default(),
            codomains: RefCell::new(None),
        }
    }

    pub(super) fn insert(&mut self, domain: D, op: Op<C>) {
        self.codomains.get_mut().take();
        self.entries.insert(domain, op);
    }

    pub(super) fn get_mut(&mut self, domain: &D) -> Option<&mut Op<C>> {
        let entry = self.entries.get_mut(domain)?;
        self.codomains.get_mut().take();
        Some(entry)
    }

    pub(super) fn into_map(self) -> OperationMap<D, C> {
        self.entries
    }

    pub(super) fn for_each_by_codomain(&self, codomain: &C, mut f: impl FnMut(&D)) {
        if self.codomains.borrow().is_none() {
            let mut buckets: Vec<(C, Vec<D>)> = Vec::new();
            for (domain, op) in &self.entries {
                if let OpType::Insert(value) | OpType::Update(value) = &op.operation {
                    if let Some((_, domains)) = buckets.iter_mut().find(|(c, _)| c == value) {
                        domains.push(domain.clone());
                    } else {
                        buckets.push((value.clone(), vec![domain.clone()]));
                    }
                }
            }
            *self.codomains.borrow_mut() = Some(buckets);
        }
        let cache = self.codomains.borrow();
        if let Some((_, domains)) = cache
            .as_ref()
            .and_then(|cache| cache.iter().find(|(c, _)| c == codomain))
        {
            for domain in domains {
                f(domain);
            }
        }
    }
}

impl<D, C: RelationCodomain> Deref for LocalOperations<D, C> {
    type Target = OperationMap<D, C>;
    fn deref(&self) -> &Self::Target {
        &self.entries
    }
}
