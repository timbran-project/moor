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

use crate::cache::VERB_CACHE_STATS;
use crate::cache::stats::{CacheStats, LocalCacheStats};
use ahash::AHasher;
use moor_common::{
    model::{
        BUILTIN_PROXY_CACHE_WORDS, BuiltinProxyCacheBits, ResolvedVerb, VerbArgsSpec, VerbFlag,
    },
    util::BitEnum,
};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, program::opcode::BuiltinId};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet, hash_map::Entry},
    hash::BuildHasherDefault,
    sync::Arc,
};

/// A lookup result is valid only for the argument and flag constraints that selected it.
#[derive(Clone, Copy, Eq, PartialEq, Hash)]
struct VerbCacheKey {
    object: u64,
    name: u32,
    constraints: u64,
}

fn make_cache_key(
    obj: &Obj,
    symbol: &Symbol,
    args: Option<VerbArgsSpec>,
    flags: Option<BitEnum<VerbFlag>>,
) -> VerbCacheKey {
    // Keep the encoded arguments and flags in separate fields, with presence bits so
    // an unconstrained lookup differs from an explicitly empty flag requirement.
    let args_bits = args.map_or(0, |args| {
        (1_u64 << 48)
            | u64::from(VerbArgsSpec::try_write(args).expect("valid verb argument specification"))
    });
    let flag_bits = flags.map_or(0, |flags| (1_u64 << 49) | (u64::from(flags.to_u16()) << 32));
    VerbCacheKey {
        object: obj.as_u64(),
        name: symbol.compare_id(),
        constraints: args_bits | flag_bits,
    }
}

fn remove_entries_for_objects(
    entries: &mut HashMap<VerbCacheKey, Option<ResolvedVerb>, BuildHasherDefault<AHasher>>,
    obj_ids: &HashSet<u64>,
) -> usize {
    let before = entries.len();
    entries.retain(|key, _| !obj_ids.contains(&key.object));
    before - entries.len()
}

struct VerbCacheStatsTls(LocalCacheStats);

impl VerbCacheStatsTls {
    #[inline]
    fn new() -> Self {
        Self(LocalCacheStats::default())
    }

    #[inline]
    fn flush_local(&mut self) {
        VERB_CACHE_STATS.add_hits(self.0.hits as isize);
        VERB_CACHE_STATS.add_negative_hits(self.0.negative_hits as isize);
        VERB_CACHE_STATS.add_misses(self.0.misses as isize);
        self.0 = LocalCacheStats::default();
    }
}

impl Drop for VerbCacheStatsTls {
    fn drop(&mut self) {
        self.flush_local();
    }
}

thread_local! {
    static VERB_CACHE_STATS_TLS: RefCell<VerbCacheStatsTls> = RefCell::new(VerbCacheStatsTls::new());
}

#[inline]
fn verb_cache_hit() {
    VERB_CACHE_STATS_TLS.with(|tls| {
        let mut tls = tls.borrow_mut();
        tls.0.hits += 1;
        if tls.0.should_flush() {
            tls.flush_local();
        }
    });
}

#[inline]
fn verb_cache_negative_hit() {
    VERB_CACHE_STATS_TLS.with(|tls| {
        let mut tls = tls.borrow_mut();
        tls.0.negative_hits += 1;
        if tls.0.should_flush() {
            tls.flush_local();
        }
    });
}

#[inline]
fn verb_cache_miss() {
    VERB_CACHE_STATS_TLS.with(|tls| {
        let mut tls = tls.borrow_mut();
        tls.0.misses += 1;
        if tls.0.should_flush() {
            tls.flush_local();
        }
    });
}

pub struct VerbResolutionCache {
    inner: Inner,
    stats: &'static CacheStats,
}

const BITS_PER_WORD: usize = u64::BITS as usize;

impl Default for VerbResolutionCache {
    fn default() -> Self {
        Self::new()
    }
}

impl VerbResolutionCache {
    pub fn new() -> Self {
        Self {
            inner: Inner {
                version: 0,
                guard_version: 0,
                orig_version: 0,
                flushed: false,
                entries: Arc::new(HashMap::default()),
                first_parent_with_verbs_cache: Arc::new(HashMap::default()),
                builtin_proxy_absent: [0; BUILTIN_PROXY_CACHE_WORDS],
            },
            stats: &VERB_CACHE_STATS,
        }
    }
}

#[derive(Clone)]
struct Inner {
    orig_version: i64,
    version: i64,
    guard_version: i64,
    flushed: bool,

    entries: Arc<HashMap<VerbCacheKey, Option<ResolvedVerb>, BuildHasherDefault<AHasher>>>,
    first_parent_with_verbs_cache: Arc<HashMap<Obj, Option<Obj>, BuildHasherDefault<AHasher>>>,
    builtin_proxy_absent: BuiltinProxyCacheBits,
}

impl Inner {
    /// Get a mutable reference to entries, cloning if necessary (copy-on-write)
    fn entries_mut(
        &mut self,
    ) -> &mut HashMap<VerbCacheKey, Option<ResolvedVerb>, BuildHasherDefault<AHasher>> {
        Arc::make_mut(&mut self.entries)
    }

    /// Get a mutable reference to first_parent_with_verbs_cache, cloning if necessary (copy-on-write)
    fn first_parent_cache_mut(
        &mut self,
    ) -> &mut HashMap<Obj, Option<Obj>, BuildHasherDefault<AHasher>> {
        Arc::make_mut(&mut self.first_parent_with_verbs_cache)
    }
}

impl VerbResolutionCache {
    pub fn fork(&self) -> Self {
        let mut forked_inner = self.inner.clone();
        forked_inner.orig_version = self.inner.version;
        forked_inner.flushed = false;
        Self {
            inner: forked_inner,
            stats: self.stats,
        }
    }

    pub fn has_changed(&self) -> bool {
        self.inner.version > self.inner.orig_version
    }

    #[inline]
    pub fn version(&self) -> i64 {
        self.inner.version
    }

    #[inline]
    pub fn guard_version(&self) -> i64 {
        self.inner.guard_version
    }

    pub(crate) fn lookup_first_parent_with_verbs(&self, obj: &Obj) -> Option<Option<Obj>> {
        self.inner.first_parent_with_verbs_cache.get(obj).cloned()
    }

    pub(crate) fn fill_first_parent_with_verbs(&mut self, obj: &Obj, parent: Option<Obj>) {
        self.inner.version += 1;
        self.inner.first_parent_cache_mut().insert(*obj, parent);
    }

    /// Look up an unconstrained name search.
    pub fn lookup(&self, obj: &Obj, verb: &Symbol) -> Option<Option<ResolvedVerb>> {
        self.lookup_spec(obj, verb, None, None)
    }

    /// Look up a result for exactly these argument and flag constraints.
    pub fn lookup_spec(
        &self,
        obj: &Obj,
        verb: &Symbol,
        args: Option<VerbArgsSpec>,
        flags: Option<BitEnum<VerbFlag>>,
    ) -> Option<Option<ResolvedVerb>> {
        let key = make_cache_key(obj, verb, args, flags);
        let result = self.inner.entries.get(&key).cloned();

        match &result {
            Some(Some(_)) => verb_cache_hit(),
            Some(None) => verb_cache_negative_hit(),
            None => verb_cache_miss(),
        }

        result
    }

    pub fn builtin_proxy_cache_snapshot(&self) -> BuiltinProxyCacheBits {
        self.inner.builtin_proxy_absent
    }

    pub fn mark_builtin_proxy_absent(&mut self, builtin: BuiltinId) {
        let bit = usize::from(builtin.0);
        let word = bit / BITS_PER_WORD;
        if word >= self.inner.builtin_proxy_absent.len() {
            return;
        }

        let mask = 1 << (bit % BITS_PER_WORD);
        if self.inner.builtin_proxy_absent[word] & mask != 0 {
            return;
        }

        self.inner.builtin_proxy_absent[word] |= mask;
        self.inner.version += 1;
    }

    fn clear_builtin_proxy_absences(&mut self) -> bool {
        if self
            .inner
            .builtin_proxy_absent
            .iter()
            .all(|word| *word == 0)
        {
            return false;
        }
        self.inner.builtin_proxy_absent = [0; BUILTIN_PROXY_CACHE_WORDS];
        true
    }

    pub fn flush(&mut self) {
        let entries_count = self.inner.entries.len() as isize;
        self.clear_builtin_proxy_absences();
        self.inner.flushed = true;
        self.inner.version += 1;
        self.inner.guard_version += 1;
        self.inner.entries_mut().clear();
        self.inner.first_parent_cache_mut().clear();
        self.stats.flush();
        self.stats.remove_entries(entries_count);
    }

    pub fn fill_hit(&mut self, obj: &Obj, verb: &Symbol, verbdef: ResolvedVerb) {
        self.fill_hit_spec(obj, verb, None, None, verbdef);
    }

    /// Cache the first matching definition for a constrained query.
    pub fn fill_hit_spec(
        &mut self,
        obj: &Obj,
        verb: &Symbol,
        args: Option<VerbArgsSpec>,
        flags: Option<BitEnum<VerbFlag>>,
        verbdef: ResolvedVerb,
    ) {
        let key = make_cache_key(obj, verb, args, flags);
        self.inner.version += 1;
        let is_new_entry = match self.inner.entries_mut().entry(key) {
            Entry::Occupied(mut occupied) => {
                occupied.insert(Some(verbdef));
                false
            }
            Entry::Vacant(vacant) => {
                vacant.insert(Some(verbdef));
                true
            }
        };
        if is_new_entry {
            self.stats.add_entry();
        }
    }

    pub fn fill_miss(&mut self, obj: &Obj, verb: &Symbol) {
        self.fill_miss_spec(obj, verb, None, None);
    }

    /// Cache a miss without affecting other argument forms or method lookups.
    pub fn fill_miss_spec(
        &mut self,
        obj: &Obj,
        verb: &Symbol,
        args: Option<VerbArgsSpec>,
        flags: Option<BitEnum<VerbFlag>>,
    ) {
        let key = make_cache_key(obj, verb, args, flags);
        self.inner.version += 1;
        let is_new_entry = match self.inner.entries_mut().entry(key) {
            Entry::Occupied(mut occupied) => {
                occupied.insert(None);
                false
            }
            Entry::Vacant(vacant) => {
                vacant.insert(None);
                true
            }
        };
        if is_new_entry {
            self.stats.add_entry();
        }
    }

    pub fn invalidate_objects(&mut self, objects: &[Obj]) {
        if objects.is_empty() {
            return;
        }
        let obj_ids: HashSet<u64> = objects.iter().map(|o| o.as_u64()).collect();
        let mut changed = false;
        let removed = remove_entries_for_objects(self.inner.entries_mut(), &obj_ids);
        if removed > 0 {
            changed = true;
        }

        let first_parent_cache = self.inner.first_parent_cache_mut();
        let before = first_parent_cache.len();
        first_parent_cache.retain(|obj, _| !obj_ids.contains(&obj.as_u64()));
        if before != first_parent_cache.len() {
            changed = true;
        }

        if objects.contains(&SYSTEM_OBJECT) && self.clear_builtin_proxy_absences() {
            changed = true;
        }

        if changed {
            self.inner.version += 1;
            self.inner.guard_version += 1;
        }

        if removed > 0 {
            self.stats.remove_entries(removed as isize);
        }
    }
}
