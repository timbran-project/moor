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

//! MOO maps.
//!
//! A map is an immutable value holding entries in key order: every edit yields a new map and
//! leaves the original as it was. Most MOO maps are small records, so a map of up to [`FLAT_MAX`]
//! entries is a single reference-counted block of entries, searched by bisection. A larger map is
//! a persistent B+-tree of such blocks, in which an edited map shares every block it did not
//! touch. Each branch counts the entries under its children, so the entry at a given position is
//! found without walking the ones before it.
//!
//! Keys compare as `Var`s do, so strings that differ only in case are the same key. Setting a key
//! that is already present replaces the stored key as well as its value.
//!
//! A `Map` is one pointer wide. `Var` stores it in its data word.

use crate::{
    Associative, Error,
    block::{Shape, ShapeOwned, ShapeRef},
    error::ErrorCode::{E_RANGE, E_TYPE},
    variant::{OP_HINT_MAP_INSERT, Var},
};
use std::{
    cmp::Ordering,
    fmt::{Debug, Formatter},
    hash::Hash,
};
use triomphe::Arc;

type Entry = (Var, Var);
type Block = crate::block::Block<Entry>;
type Repr<'a> = ShapeRef<'a, Entry, Tree>;
type Owned = ShapeOwned<Entry, Tree>;

/// The most entries a map holds in one block. A larger map is a tree.
const FLAT_MAX: usize = 16;

/// The most entries in a leaf. A map's single block becomes the first leaf of its tree, so this
/// is no less than `FLAT_MAX`.
const LEAF_MAX: usize = FLAT_MAX;

/// The most children of a branch.
const BRANCH_MAX: usize = 16;

/// How full a tree built in one go leaves its nodes, so that the first edits do not split them.
const BUILT_FILL: usize = 12;

/// A node smaller than this after a removal is merged into a neighbor that has room for it.
const MERGE_BELOW: usize = 4;

/// A tree that shrinks to this few entries becomes a single block again. This is well below
/// `FLAT_MAX`, so that a map whose size hovers around `FLAT_MAX` does not change shape on every
/// edit.
const FLAT_AGAIN: usize = FLAT_MAX / 2;

/// The position of `key` among entries in key order, or the position it would be inserted at.
///
/// Comparing keys is the cost of a lookup, so this stops at the first equal key. The standard
/// library's search always runs to the end, which for a record-sized map is one or two more
/// string comparisons on every hit.
#[inline]
fn find(entries: &[Entry], key: &Var) -> Result<usize, usize> {
    let (mut low, mut high) = (0, entries.len());
    while low < high {
        let middle = low + (high - low) / 2;
        match entries[middle].0.cmp(key) {
            Ordering::Less => low = middle + 1,
            Ordering::Greater => high = middle,
            Ordering::Equal => return Ok(middle),
        }
    }
    Err(low)
}

#[derive(Clone)]
enum Node {
    Leaf(Block),
    Branch(Arc<Branch>),
}

/// An inner node. Its children are all leaves or all branches, and none is empty.
#[derive(Clone)]
struct Branch {
    /// For each child, the greatest key under it.
    ///
    /// These are in a block of their own, so that copying a branch to change one child shares
    /// them and does not copy each key.
    last_keys: crate::block::Block<Var>,
    /// For each child, the number of entries under it.
    counts: Vec<usize>,
    children: Vec<Node>,
}

impl Branch {
    fn from_children(children: Vec<Node>) -> Self {
        Self {
            last_keys: children.iter().map(|c| c.last_key().clone()).collect(),
            counts: children.iter().map(Node::len).collect(),
            children,
        }
    }

    /// The child `key` is under if it is present: the first whose greatest key is not less.
    /// One past the last child if `key` is greater than every key here.
    #[inline]
    fn child_for(&self, key: &Var) -> usize {
        self.last_keys
            .as_slice()
            .partition_point(|last| last.cmp(key) == Ordering::Less)
    }

    /// Bring the count and greatest key recorded for a child up to date after a change to it.
    fn refresh(&mut self, index: usize) {
        self.counts[index] = self.children[index].len();
        self.last_keys.as_mut_slice()[index] = self.children[index].last_key().clone();
    }

    fn insert_child(&mut self, index: usize, child: Node) {
        self.last_keys
            .insert(index, child.last_key().clone(), BRANCH_MAX + 1);
        self.counts.insert(index, child.len());
        self.children.insert(index, child);
    }

    fn remove_child(&mut self, index: usize) -> Node {
        self.last_keys.remove(index);
        self.counts.remove(index);
        self.children.remove(index)
    }

    /// Move the children from `at` on into a new branch.
    fn split_off(&mut self, at: usize) -> Self {
        Self {
            last_keys: self.last_keys.split_off(at, 0),
            counts: self.counts.split_off(at),
            children: self.children.split_off(at),
        }
    }

    /// If the child at `index` has become small, merge it with a neighbor when the two fit in
    /// one node. This keeps a tree that entries are removed from reasonably full without the
    /// borrowing between nodes of a strict B-tree.
    fn merge_small(&mut self, index: usize) {
        let size = |node: &Node| match node {
            Node::Leaf(leaf) => leaf.len(),
            Node::Branch(branch) => branch.children.len(),
        };
        if size(&self.children[index]) >= MERGE_BELOW {
            return;
        }
        let limit = match self.children[index] {
            Node::Leaf(_) => LEAF_MAX,
            Node::Branch(_) => BRANCH_MAX,
        };
        // The neighbor after it, or failing that the one before.
        let left = [Some(index), index.checked_sub(1)]
            .into_iter()
            .flatten()
            .find(|left| {
                left + 1 < self.children.len()
                    && size(&self.children[*left]) + size(&self.children[left + 1]) <= limit
            });
        let Some(left) = left else {
            return;
        };
        let right = self.remove_child(left + 1);
        match (&mut self.children[left], right) {
            (Node::Leaf(left), Node::Leaf(right)) => left.append(right, LEAF_MAX),
            (Node::Branch(left), Node::Branch(right)) => {
                let left = Arc::make_mut(left);
                left.last_keys
                    .extend_from_slice(right.last_keys.as_slice(), BRANCH_MAX);
                left.counts.extend(&right.counts);
                left.children.extend(right.children.iter().cloned());
            }
            _ => unreachable!("the children of a branch are all of one kind"),
        }
        self.refresh(left);
    }
}

impl Node {
    fn len(&self) -> usize {
        match self {
            Node::Leaf(leaf) => leaf.len(),
            Node::Branch(branch) => branch.counts.iter().sum(),
        }
    }

    fn is_empty(&self) -> bool {
        match self {
            Node::Leaf(leaf) => leaf.len() == 0,
            Node::Branch(branch) => branch.children.is_empty(),
        }
    }

    /// The greatest key under this node, which must not be empty.
    fn last_key(&self) -> &Var {
        match self {
            Node::Leaf(leaf) => &leaf.as_slice().last().expect("a node is not empty").0,
            Node::Branch(branch) => branch
                .last_keys
                .as_slice()
                .last()
                .expect("a node is not empty"),
        }
    }

    fn get(&self, key: &Var) -> Option<&Entry> {
        let mut node = self;
        loop {
            match node {
                Node::Leaf(leaf) => {
                    let entries = leaf.as_slice();
                    return find(entries, key).ok().map(|index| &entries[index]);
                }
                Node::Branch(branch) => node = branch.children.get(branch.child_for(key))?,
            }
        }
    }

    /// The number of entries whose key is less than `key`.
    fn lower_bound(&self, key: &Var) -> usize {
        let mut node = self;
        let mut before = 0;
        loop {
            match node {
                Node::Leaf(leaf) => {
                    return before + find(leaf.as_slice(), key).unwrap_or_else(|index| index);
                }
                Node::Branch(branch) => {
                    let child = branch.child_for(key);
                    before += branch.counts[..child].iter().sum::<usize>();
                    let Some(child) = branch.children.get(child) else {
                        return before;
                    };
                    node = child;
                }
            }
        }
    }

    /// The leaf holding the entry at position `index`, and the position of its first entry.
    fn chunk_at(&self, index: usize) -> (usize, &[Entry]) {
        let mut node = self;
        let mut start = 0;
        loop {
            match node {
                Node::Leaf(leaf) => return (start, leaf.as_slice()),
                Node::Branch(branch) => {
                    let mut child = 0;
                    while index - start >= branch.counts[child] {
                        start += branch.counts[child];
                        child += 1;
                    }
                    node = &branch.children[child];
                }
            }
        }
    }

    /// Set `key` to `value`. Returns whether that added an entry, and, if this node grew past
    /// its limit, the new node that now follows it with the upper half of what it held.
    fn insert(&mut self, key: Var, value: Var) -> (bool, Option<Node>) {
        match self {
            Node::Leaf(leaf) => match find(leaf.as_slice(), &key) {
                Ok(index) => {
                    leaf.as_mut_slice()[index] = (key, value);
                    (false, None)
                }
                Err(index) if leaf.len() < LEAF_MAX => {
                    leaf.insert(index, (key, value), LEAF_MAX);
                    (true, None)
                }
                Err(index) => {
                    // A key past the end starts the next leaf and leaves this one full, so that
                    // keys added in ascending order fill their leaves. Any other key splits the
                    // leaf in half.
                    let at = if index == leaf.len() {
                        index
                    } else {
                        leaf.len() / 2
                    };
                    let mut right = leaf.split_off(at, LEAF_MAX);
                    if index < at {
                        leaf.insert(index, (key, value), LEAF_MAX);
                    } else {
                        right.insert(index - at, (key, value), LEAF_MAX);
                    }
                    (true, Some(Node::Leaf(right)))
                }
            },
            Node::Branch(branch) => {
                let branch = Arc::make_mut(branch);
                // A key greater than every key here belongs at the end of the last child.
                let found = branch.child_for(&key);
                let child = found.min(branch.children.len() - 1);
                let (added, split) = branch.children[child].insert(key, value);
                match split {
                    Some(right) => {
                        branch.refresh(child);
                        branch.insert_child(child + 1, right);
                    }
                    None => {
                        branch.counts[child] += usize::from(added);
                        // Only a key past every key here changes what a child's greatest is.
                        if found != child {
                            branch.last_keys.as_mut_slice()[child] =
                                branch.children[child].last_key().clone();
                        }
                    }
                }
                if branch.children.len() <= BRANCH_MAX {
                    return (added, None);
                }
                // As with a leaf: a child added at the end starts the next branch.
                let at = if child + 2 == branch.children.len() {
                    branch.children.len() - 1
                } else {
                    branch.children.len() / 2
                };
                let right = branch.split_off(at);
                (added, Some(Node::Branch(Arc::new(right))))
            }
        }
    }

    /// The position of the entry for `key` in key order.
    fn position(&self, key: &Var) -> Option<usize> {
        let mut node = self;
        let mut before = 0;
        loop {
            match node {
                Node::Leaf(leaf) => return find(leaf.as_slice(), key).ok().map(|i| before + i),
                Node::Branch(branch) => {
                    let child = branch.child_for(key);
                    before += branch.counts[..child].iter().sum::<usize>();
                    node = branch.children.get(child)?;
                }
            }
        }
    }

    /// Remove the entry at position `index`, which must be in range, and return its value.
    ///
    /// Going by position finds the way down from the counts, with no key comparisons.
    fn remove_at(&mut self, mut index: usize) -> Var {
        match self {
            Node::Leaf(leaf) => leaf.remove(index).1,
            Node::Branch(branch) => {
                let branch = Arc::make_mut(branch);
                let mut child = 0;
                while index >= branch.counts[child] {
                    index -= branch.counts[child];
                    child += 1;
                }
                let was_last = index + 1 == branch.counts[child];
                let removed = branch.children[child].remove_at(index);
                if branch.children[child].is_empty() {
                    branch.remove_child(child);
                } else {
                    branch.counts[child] -= 1;
                    // Only removing a child's last entry changes what its greatest key is.
                    if was_last {
                        branch.last_keys.as_mut_slice()[child] =
                            branch.children[child].last_key().clone();
                    }
                    branch.merge_small(child);
                }
                removed
            }
        }
    }
}

/// The tree of a map with more than `FLAT_MAX` entries.
#[derive(Clone)]
struct Tree {
    len: usize,
    root: Node,
}

impl Tree {
    /// A tree of the given entries, which must be in key order with no key twice.
    fn from_sorted(entries: Vec<Entry>) -> Self {
        let len = entries.len();
        let mut entries = entries.into_iter();
        let mut nodes = Vec::with_capacity(len.div_ceil(BUILT_FILL));
        while entries.len() > 0 {
            let mut leaf = Block::with_capacity(LEAF_MAX);
            for entry in entries.by_ref().take(BUILT_FILL) {
                leaf.push(entry, LEAF_MAX);
            }
            nodes.push(Node::Leaf(leaf));
        }
        while nodes.len() > 1 {
            let mut below = nodes.into_iter();
            nodes = Vec::with_capacity(below.len().div_ceil(BUILT_FILL));
            while below.len() > 0 {
                let children = below.by_ref().take(BUILT_FILL).collect();
                nodes.push(Node::Branch(Arc::new(Branch::from_children(children))));
            }
        }
        Self {
            len,
            root: nodes
                .pop()
                .unwrap_or_else(|| Node::Leaf(Block::with_capacity(0))),
        }
    }

    /// Set `key` to `value`, and return whether that added an entry.
    fn insert(&mut self, key: Var, value: Var) -> bool {
        let (added, split) = self.root.insert(key, value);
        if let Some(right) = split {
            let left = std::mem::replace(&mut self.root, Node::Leaf(Block::with_capacity(0)));
            self.root = Node::Branch(Arc::new(Branch::from_children(vec![left, right])));
        }
        self.len += usize::from(added);
        added
    }

    /// Remove the entry at position `index`, which must be in range, and return its value.
    fn remove_at(&mut self, index: usize) -> Var {
        let removed = self.root.remove_at(index);
        self.len -= 1;
        // A root left with one child is no longer needed.
        loop {
            let only_child = match &self.root {
                Node::Branch(branch) if branch.children.len() == 1 => branch.children[0].clone(),
                Node::Branch(branch) if branch.children.is_empty() => {
                    Node::Leaf(Block::with_capacity(0))
                }
                _ => break,
            };
            self.root = only_child;
        }
        removed
    }
}

/// A MOO map. See the module documentation.
#[derive(Clone)]
#[repr(transparent)]
pub struct Map(Shape<Entry, Tree>);

impl Map {
    #[inline]
    fn from_block(block: Block) -> Self {
        Self(Shape::from_block(block))
    }

    #[inline]
    fn from_tree(tree: Arc<Tree>) -> Self {
        Self(Shape::from_tree(tree))
    }

    #[inline]
    fn repr(&self) -> Repr<'_> {
        self.0.get()
    }

    /// A map of the given entries, which must be in key order with no key twice.
    fn from_sorted(entries: Vec<Entry>) -> Self {
        if entries.len() <= FLAT_MAX {
            return Self::from_block(entries.into_iter().collect());
        }
        Self::from_tree(Arc::new(Tree::from_sorted(entries)))
    }

    /// A map of the tree's entries: the tree itself, or a single block if it has become small.
    fn from_edited_tree(tree: Arc<Tree>) -> Self {
        if tree.len > FLAT_AGAIN {
            return Self::from_tree(tree);
        }
        if let Node::Leaf(leaf) = &tree.root {
            return Self::from_block(leaf.clone());
        }
        let map = Self::from_tree(tree);
        let mut block = Block::with_capacity(map.len());
        for entry in map.entries_from(0) {
            block.push(entry.clone(), FLAT_MAX);
        }
        Self::from_block(block)
    }

    /// Whether both share the same storage. See `Var::is_identical`.
    pub fn is_identical(&self, other: &Self) -> bool {
        self.0.ptr_eq(&other.0)
    }

    /// Compare keys and values using the storage guarantee of [`Var::eq_exact`].
    pub(crate) fn eq_exact(&self, other: &Self) -> bool {
        if self.0.ptr_eq(&other.0) {
            return true;
        }
        if self.len() != other.len() {
            return false;
        }
        self.iter_ref()
            .zip(other.iter_ref())
            .all(|((ak, av), (bk, bv))| ak.eq_exact(bk) && av.eq_exact(bv))
    }

    // Construct from an Iterator of pairs. A key given more than once keeps its last pair.
    pub(crate) fn build<'a, I: Iterator<Item = &'a (Var, Var)>>(pairs: I) -> Var {
        let mut entries: Vec<Entry> = pairs.cloned().collect();
        // The sort is stable, so pairs with the same key stay in the order given.
        entries.sort_by(|a, b| a.0.cmp(&b.0));
        entries.dedup_by(|later, earlier| {
            let same_key = later.0.cmp(&earlier.0) == Ordering::Equal;
            if same_key {
                std::mem::swap(later, earlier);
            }
            same_key
        });
        Var::from_map(Self::from_sorted(entries))
    }

    pub fn iter(&self) -> impl Iterator<Item = (Var, Var)> + '_ {
        self.entries_from(0).cloned()
    }

    #[inline]
    pub fn iter_ref(&self) -> impl ExactSizeIterator<Item = (&Var, &Var)> + '_ {
        self.entries_from(0).map(|(key, value)| (key, value))
    }

    /// The entries from position `index` on, in key order.
    fn entries_from(&self, index: usize) -> Entries<'_> {
        let len = self.len();
        let index = index.min(len);
        let mut entries = Entries {
            current: [].iter(),
            path: Vec::new(),
            remaining: len - index,
        };
        match self.repr() {
            Repr::Flat(block) => entries.current = block.as_slice()[index..].iter(),
            Repr::Tree(tree) if index < len => entries.seek(&tree.root, index),
            Repr::Tree(_) => {}
        }
        entries
    }

    /// The position of the entry a loop over this map takes after the one for `key`: one past
    /// the first entry whose key is not less than `key`.
    ///
    /// A loop steps by position. A task stored in the middle of one records the key it had
    /// reached, and uses this to find its place again, in case the map's keys do not come back
    /// in the order they were in.
    pub fn position_after(&self, key: &Var) -> usize {
        (self.lower_bound(key) + 1).min(self.len())
    }

    /// The entry at position `index` in key order.
    fn entry_at(&self, index: usize) -> Option<&Entry> {
        match self.repr() {
            Repr::Flat(block) => block.as_slice().get(index),
            Repr::Tree(tree) if index < tree.len => {
                let (start, chunk) = tree.root.chunk_at(index);
                Some(&chunk[index - start])
            }
            Repr::Tree(_) => None,
        }
    }

    /// The entry whose key equals `key`.
    fn entry_for(&self, key: &Var) -> Option<&Entry> {
        match self.repr() {
            Repr::Flat(block) => {
                let entries = block.as_slice();
                find(entries, key).ok().map(|index| &entries[index])
            }
            Repr::Tree(tree) => tree.root.get(key),
        }
    }

    /// The entry whose key is `key` exactly: the same key, and for a string the same case.
    fn entry_for_exact(&self, key: &Var) -> Option<&Entry> {
        self.entry_for(key)
            .filter(|(stored, _)| stored.cmp_case_sensitive(key) == Ordering::Equal)
    }

    /// The number of entries whose key is less than `key`.
    fn lower_bound(&self, key: &Var) -> usize {
        match self.repr() {
            Repr::Flat(block) => find(block.as_slice(), key).unwrap_or_else(|index| index),
            Repr::Tree(tree) => tree.root.lower_bound(key),
        }
    }

    /// This map with `key` set to `value`, and whether that added an entry.
    fn inserted(self, key: Var, value: Var) -> (Self, bool) {
        match self.0.into_owned() {
            Owned::Flat(mut block) => match find(block.as_slice(), &key) {
                Ok(index) => {
                    block.as_mut_slice()[index] = (key, value);
                    (Self::from_block(block), false)
                }
                Err(index) if block.len() < FLAT_MAX => {
                    block.insert(index, (key, value), FLAT_MAX);
                    (Self::from_block(block), true)
                }
                Err(_) => {
                    // The full block becomes the first leaf, which the insert then splits.
                    let mut tree = Tree {
                        len: block.len(),
                        root: Node::Leaf(block),
                    };
                    tree.insert(key, value);
                    (Self::from_tree(Arc::new(tree)), true)
                }
            },
            Owned::Tree(mut tree) => {
                let added = Arc::make_mut(&mut tree).insert(key, value);
                (Self::from_tree(tree), added)
            }
        }
    }

    /// This map without `key`, and the value it had.
    fn removed(self, key: &Var) -> (Self, Option<Var>) {
        match self.0.into_owned() {
            Owned::Flat(mut block) => match find(block.as_slice(), key) {
                Ok(index) => {
                    let (_, value) = block.remove(index);
                    (Self::from_block(block), Some(value))
                }
                Err(_) => (Self::from_block(block), None),
            },
            Owned::Tree(mut tree) => {
                // Find the key first, so that a missing one copies nothing.
                let Some(index) = tree.root.position(key) else {
                    return (Self::from_tree(tree), None);
                };
                let value = Arc::make_mut(&mut tree).remove_at(index);
                (Self::from_edited_tree(tree), Some(value))
            }
        }
    }

    fn validate_key(key: &Var) -> Result<(), Error> {
        // Toast/ToastStunt has a restriction that non-scalars cannot be keys (unless they're strings).
        // So we enforce that here, even though it's not strictly necessary.
        if !key.is_scalar() && !key.is_string() {
            return Err(E_TYPE.with_msg(|| {
                format!(
                    "Key must be a string or scalar, was {}",
                    key.type_code().to_literal()
                )
            }));
        }
        Ok(())
    }

    pub fn set_owned(self, key: &Var, value: &Var) -> Result<Var, Error> {
        self.set_owned_vars(key.clone(), value.clone())
    }

    pub fn set_owned_vars(self, key: Var, value: Var) -> Result<Var, Error> {
        Self::validate_key(&key)?;

        let (map, added) = self.inserted(key, value);
        let hint = if added { OP_HINT_MAP_INSERT } else { 0 };
        Ok(Var::from_map_with_hint(map, hint))
    }

    #[inline]
    pub fn remove_key(&self, key: &Var) -> (Var, Option<Var>) {
        self.clone().remove_owned_key(key)
    }

    #[inline]
    pub fn remove_owned_key(self, key: &Var) -> (Var, Option<Var>) {
        let (map, removed_value) = self.removed(key);
        (Var::from_map(map), removed_value)
    }

    pub fn remove_owned(self, key: &Var, case_sensitive: bool) -> (Var, Option<Var>) {
        // Only the entry found without regard to case can be the one that matches exactly.
        if case_sensitive && self.entry_for_exact(key).is_none() {
            return (Var::from_map(self), None);
        }
        self.remove_owned_key(key)
    }
}

/// The entries of a map, in key order.
#[derive(Clone)]
struct Entries<'a> {
    /// What is left of the block being read.
    current: std::slice::Iter<'a, Entry>,
    /// For a tree, the branches above that block, each with the index of the child the walk is
    /// in. The next block is found from here, without going back to the root.
    path: Vec<(&'a Branch, usize)>,
    remaining: usize,
}

impl<'a> Entries<'a> {
    /// Start reading at the entry at position `index` under `node`, which must be in range.
    fn seek(&mut self, mut node: &'a Node, mut index: usize) {
        loop {
            match node {
                Node::Leaf(leaf) => {
                    self.current = leaf.as_slice()[index..].iter();
                    return;
                }
                Node::Branch(branch) => {
                    let mut child = 0;
                    while index >= branch.counts[child] {
                        index -= branch.counts[child];
                        child += 1;
                    }
                    self.path.push((branch, child));
                    node = &branch.children[child];
                }
            }
        }
    }

    /// Start reading the block after the one just finished. Returns whether there is one.
    fn next_block(&mut self) -> bool {
        // Up to the nearest branch with a child still to visit, then down its leftmost side.
        let mut node = loop {
            let Some((branch, child)) = self.path.last_mut() else {
                return false;
            };
            *child += 1;
            if let Some(next) = branch.children.get(*child) {
                break next;
            }
            self.path.pop();
        };
        loop {
            match node {
                Node::Leaf(leaf) => {
                    self.current = leaf.as_slice().iter();
                    return true;
                }
                Node::Branch(branch) => {
                    self.path.push((branch, 0));
                    node = &branch.children[0];
                }
            }
        }
    }
}

impl<'a> Iterator for Entries<'a> {
    type Item = &'a Entry;

    #[inline]
    fn next(&mut self) -> Option<&'a Entry> {
        loop {
            if let Some(entry) = self.current.next() {
                self.remaining -= 1;
                return Some(entry);
            }
            if self.remaining == 0 || !self.next_block() {
                return None;
            }
        }
    }

    #[inline]
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}

impl ExactSizeIterator for Entries<'_> {}

impl Debug for Map {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_map().entries(self.iter_ref()).finish()
    }
}

impl PartialEq for Map {
    fn eq(&self, other: &Self) -> bool {
        if self.0.ptr_eq(&other.0) {
            return true;
        }
        if self.len() != other.len() {
            return false;
        }

        // elements comparison using iterator
        for ((a_k, a_v), (b_k, b_v)) in self.iter_ref().zip(other.iter_ref()) {
            if a_k != b_k || a_v != b_v {
                return false;
            }
        }

        true
    }
}

impl Associative for Map {
    fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn len(&self) -> usize {
        match self.repr() {
            Repr::Flat(block) => block.len(),
            Repr::Tree(tree) => tree.len,
        }
    }

    fn index_in(&self, key: &Var, case_sensitive: bool) -> Result<Option<usize>, Error> {
        // Check the common in the key-value pairs and return the index of the first match.
        // Linear O(N) operation.
        let pos = self.iter_ref().position(|(_, v)| {
            if case_sensitive {
                v.cmp_case_sensitive(key) == Ordering::Equal
            } else {
                v == key
            }
        });
        Ok(pos)
    }

    fn get(&self, key: &Var) -> Result<Var, Error> {
        match self.entry_for(key) {
            Some((_, value)) => Ok(value.clone()),
            None => Err(E_RANGE.with_msg(|| format!("Key not found: {key:?}"))),
        }
    }

    fn set(&self, key: &Var, value: &Var) -> Result<Var, Error> {
        self.clone().set_owned_vars(key.clone(), value.clone())
    }

    fn index(&self, index: usize) -> Result<(Var, Var), Error> {
        match self.entry_at(index) {
            Some((k, v)) => Ok((k.clone(), v.clone())),
            None => Err(E_RANGE.with_msg(|| {
                format!(
                    "Index {} out of bounds for map of length {}",
                    index,
                    self.len()
                )
            })),
        }
    }

    /// Return the range of key-value pairs between the two keys.
    fn range(&self, from: &Var, to: &Var) -> Result<Var, Error> {
        // Check if the from key exists
        if self.entry_for(from).is_none() {
            return Err(E_RANGE.with_msg(|| format!("Key not found: {from:?}")));
        }

        // The entries with keys from `from` up to but not including `to`.
        let entries: Vec<Entry> = self
            .entries_from(self.lower_bound(from))
            .take_while(|(k, _)| k.cmp(to) == Ordering::Less)
            .cloned()
            .collect();

        Ok(Var::from_map(Self::from_sorted(entries)))
    }

    fn range_set(&self, _from: &Var, _to: &Var, _with: &Var) -> Result<Var, Error> {
        Err(E_TYPE.msg("Range assignment not supported on maps"))
    }

    fn keys(&self) -> Vec<Var> {
        self.iter_ref().map(|(k, _)| k.clone()).collect::<Vec<_>>()
    }

    fn values(&self) -> Vec<Var> {
        self.iter_ref().map(|(_, v)| v.clone()).collect::<Vec<_>>()
    }

    fn contains_key(&self, key: &Var, case_sensitive: bool) -> Result<bool, Error> {
        if case_sensitive {
            Ok(self.entry_for_exact(key).is_some())
        } else {
            Ok(self.entry_for(key).is_some())
        }
    }

    /// Return this map with the key/value pair removed.
    /// Return the new map and the value that was removed, if any
    fn remove(&self, key: &Var, case_sensitive: bool) -> (Var, Option<Var>) {
        self.clone().remove_owned(key, case_sensitive)
    }

    fn first(&self) -> Result<(Var, Var), Error> {
        // Return first k/v pair or Err(E_RANGE) if none
        let Some((k, v)) = self.entry_at(0) else {
            return Err(E_RANGE.into());
        };
        Ok((k.clone(), v.clone()))
    }

    fn next_after(&self, key: &Var, case_sensitive: bool) -> Result<(Var, Var), Error> {
        // The entries from the first whose key is not less than `key`.
        let mut entries = self.entries_from(self.lower_bound(key));
        if case_sensitive {
            // The map orders keys without regard to case, so look for the key that matches
            // exactly, then return the entry after it.
            let mut found = false;
            for (k, v) in entries {
                if found {
                    return Ok((k.clone(), v.clone()));
                }
                if k.cmp_case_sensitive(key) == Ordering::Equal {
                    found = true;
                }
            }
            Err(E_RANGE.msg("No key after"))
        } else {
            // Skip the first of them, whether or not it is `key` itself, and take the next.
            entries.next();
            entries
                .next()
                .map(|(k, v)| (k.clone(), v.clone()))
                .ok_or_else(|| E_RANGE.msg("No key after"))
        }
    }
}

impl Eq for Map {}

impl PartialOrd for Map {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Map {
    fn cmp(&self, other: &Self) -> Ordering {
        if self.len() != other.len() {
            return self.len().cmp(&other.len());
        }

        // elements comparison
        for ((a_k, a_v), (b_k, b_v)) in self.iter_ref().zip(other.iter_ref()) {
            match a_k.cmp(b_k) {
                Ordering::Equal => {}
                x => return x,
            }
            match a_v.cmp(b_v) {
                Ordering::Equal => continue,
                x => return x,
            }
        }

        Ordering::Equal
    }
}

impl Hash for Map {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        for (k, v) in self.iter_ref() {
            k.hash(state);
            v.hash(state);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        Associative, IndexMode, v_bool_int, v_float, v_int, v_str,
        variant::{Var, Variant},
    };

    #[test]
    fn test_map_pack_unpack_index() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        match m.variant() {
            Variant::Map(m) => {
                assert_eq!(m.len(), 3);
            }
            _ => panic!("Expected map"),
        }

        let key = Var::mk_str("a");
        let value = m.get(&key, IndexMode::ZeroBased).unwrap();
        match value.variant() {
            Variant::Int(i) => assert_eq!(i, 1),
            _ => panic!("Expected integer"),
        }
    }

    #[test]
    fn test_map_is_funcs() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        assert!(m.is_true());
        assert!(!m.is_sequence());
        assert!(m.is_associative());
        assert!(!m.is_scalar());
        assert_eq!(m.len().unwrap(), 3);
        assert!(!m.is_empty().unwrap());

        let m = Var::mk_map(&[]);
        assert!(!m.is_true());
        assert!(!m.is_sequence());
        assert!(m.is_associative());
        assert!(!m.is_scalar());
        assert_eq!(m.len().unwrap(), 0);
        assert!(m.is_empty().unwrap());
    }

    #[test]
    fn test_map_equality_inequality() {
        let m1 = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        let m2 = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        let m3 = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("d")),
        ]);

        let m4 = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
        ]);

        let m5 = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
            (Var::mk_integer(4), Var::mk_str("d")),
        ]);

        assert_eq!(m1, m2);
        assert_ne!(m1, m3);
        assert_ne!(m1, m4);
        assert_ne!(m1, m5);
    }

    #[test]
    fn test_map_get() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        let key = Var::mk_str("b");
        let value = m.get(&key, IndexMode::OneBased).unwrap();
        match value.variant() {
            Variant::Int(i) => assert_eq!(i, 2),
            _ => panic!("Expected integer"),
        }
    }

    #[test]
    fn test_map_set() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        let r = m
            .set(&Var::mk_str("b"), &Var::mk_integer(42), IndexMode::OneBased)
            .unwrap();
        let r = r.variant();
        match r {
            Variant::Map(m) => {
                let r = m.get(&Var::mk_str("b")).unwrap();
                match r.variant() {
                    Variant::Int(i) => assert_eq!(i, 42),
                    _ => panic!("Expected integer, got {r:?}"),
                }
            }
            _ => panic!("Expected map, got {r:?}"),
        }

        // Insert new item
        let r = m
            .set(&Var::mk_str("d"), &Var::mk_integer(42), IndexMode::OneBased)
            .unwrap();
        let r = r.variant();
        match r {
            Variant::Map(m) => {
                let r = m.get(&Var::mk_str("d")).unwrap();
                match r.variant() {
                    Variant::Int(i) => assert_eq!(i, 42),
                    _ => panic!("Expected integer, got {r:?}"),
                }
            }
            _ => panic!("Expected map, got {r:?}"),
        }
    }

    #[test]
    fn test_map_keys_values() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_integer(3), Var::mk_str("c")),
        ]);

        let m = match m.variant() {
            Variant::Map(m) => m,
            _ => panic!("Expected map"),
        };

        // The keys come out in sorted order.
        let keys = m.keys();
        assert_eq!(keys.len(), 3);
        assert_eq!(keys[0], Var::mk_integer(3));
        assert_eq!(keys[1], Var::mk_str("a"));
        assert_eq!(keys[2], Var::mk_str("b"));

        let values = m.values();
        assert_eq!(values.len(), 3);
        assert_eq!(values[0], Var::mk_str("c"));
        assert_eq!(values[1], Var::mk_integer(1));
        assert_eq!(values[2], Var::mk_integer(2));
    }

    #[test]
    fn test_map_range() {
        let m = Var::mk_map(&[
            (Var::mk_integer(0), Var::mk_integer(1)),
            (Var::mk_integer(1), Var::mk_integer(2)),
            (Var::mk_integer(2), Var::mk_integer(3)),
            (Var::mk_integer(3), Var::mk_integer(4)),
        ]);

        let r = m
            .range(
                &Var::mk_integer(1),
                &Var::mk_integer(3),
                IndexMode::OneBased,
            )
            .unwrap();
        let r = match r.variant() {
            Variant::Map(m) => m,
            _ => panic!("Expected map"),
        };

        let key_value_results = r.iter().collect::<Vec<_>>();
        assert_eq!(
            key_value_results,
            vec![(v_int(1), v_int(2)), (v_int(2), v_int(3))]
        );
    }

    #[test]
    // Disable because range_set is stubbed out in our impl
    #[ignore]
    fn test_map_range_set() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_str("c"), Var::mk_integer(3)),
            (Var::mk_str("d"), Var::mk_integer(4)),
            (Var::mk_str("e"), Var::mk_integer(5)),
        ]);

        // Now replace b, c, d with x, y
        let r = m
            .range_set(
                &Var::mk_str("b"),
                &Var::mk_str("d"),
                &Var::mk_map(&[
                    (Var::mk_str("x"), Var::mk_integer(42)),
                    (Var::mk_str("y"), Var::mk_integer(43)),
                ]),
                IndexMode::ZeroBased,
            )
            .unwrap();

        let r = match r.variant() {
            Variant::Map(m) => m,
            _ => panic!("Expected map"),
        };

        assert_eq!(r.len(), 4);
        let keys = r.keys();
        assert_eq!(keys.len(), 4);
        assert_eq!(keys[0], Var::mk_str("a"));
        assert_eq!(keys[1], Var::mk_str("e"));
        assert_eq!(keys[2], Var::mk_str("x"));
        assert_eq!(keys[3], Var::mk_str("y"));
    }

    #[test]
    fn test_map_contains_key() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_str("c"), Var::mk_integer(3)),
        ]);

        let key = Var::mk_str("B");
        let not_key = Var::mk_str("d");

        // Case-insensitive
        assert_eq!(m.contains(&key, false).unwrap(), v_bool_int(true));
        assert_eq!(m.contains(&not_key, true).unwrap(), v_bool_int(false));

        // Case sensitive
        assert_eq!(m.contains(&key, true).unwrap(), v_bool_int(false));
        assert_eq!(m.contains(&not_key, false).unwrap(), v_bool_int(false));
    }

    #[test]
    fn test_map_remove_key() {
        let m = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_integer(1)),
            (Var::mk_str("b"), Var::mk_integer(2)),
            (Var::mk_str("c"), Var::mk_integer(3)),
        ]);

        let key = Var::mk_str("b");
        let not_key = Var::mk_str("d");

        let (r, removed) = m.remove(&key, false).expect("remove failed");
        assert_eq!(r.len().unwrap(), 2);
        assert_eq!(removed.unwrap(), Var::mk_integer(2));

        let (r, removed) = m.remove(&not_key, false).expect("remove failed");
        assert_eq!(r.len().unwrap(), 3);
        assert_eq!(removed, None);

        // Case sensitive
        let not_key = Var::mk_str("B");
        let (r, removed) = m.remove(&not_key, true).expect("remove failed");
        assert_eq!(r.len().unwrap(), 3);
        assert_eq!(removed, None);

        let (r, removed) = m.remove(&key, true).expect("remove failed");
        assert_eq!(r.len().unwrap(), 2);
        assert_eq!(removed.unwrap(), Var::mk_integer(2));
    }

    #[test]
    /// Verify that sort order is preserved after insertion
    fn test_map_insertion_ordering() {
        let m = Var::mk_map(&[
            (Var::mk_integer(3), Var::mk_integer(3)),
            (Var::mk_integer(1), Var::mk_integer(1)),
            (Var::mk_integer(4), Var::mk_integer(4)),
            (Var::mk_integer(5), Var::mk_integer(5)),
            (Var::mk_integer(9), Var::mk_integer(9)),
            (Var::mk_integer(2), Var::mk_integer(2)),
        ]);

        let m = m
            .set(&Var::mk_str("a"), &Var::mk_str("a"), IndexMode::OneBased)
            .unwrap();
        let m = m
            .set(
                &Var::mk_integer(6),
                &Var::mk_integer(6),
                IndexMode::OneBased,
            )
            .unwrap();

        let m = match m.variant() {
            Variant::Map(m) => m,
            _ => panic!("Expected map"),
        };

        let pairs = m.iter().collect::<Vec<_>>();
        assert_eq!(
            pairs,
            vec![
                (v_int(1), v_int(1)),
                (v_int(2), v_int(2)),
                (v_int(3), v_int(3)),
                (v_int(4), v_int(4)),
                (v_int(5), v_int(5)),
                (v_int(6), v_int(6)),
                (v_int(9), v_int(9)),
                (v_str("a"), v_str("a")),
            ]
        );
    }

    #[test]
    fn test_index_in() {
        // ["3" -> "3", "1" -> "1", "4" -> "4", "5" -> "5", "9" -> "9", "2" -> "2"];
        let m = Var::mk_map(&[
            (Var::mk_str("3"), Var::mk_str("3")),
            (Var::mk_str("1"), Var::mk_str("1")),
            (Var::mk_str("4"), Var::mk_str("4")),
            (Var::mk_str("5"), Var::mk_str("5")),
            (Var::mk_str("9"), Var::mk_str("9")),
            (Var::mk_str("2"), Var::mk_str("2")),
        ]);
        // "2" -> 2nd position
        let key = Var::mk_str("2");
        let pos = m.index_in(&key, false, IndexMode::OneBased).unwrap();
        assert_eq!(pos, v_int(2));
    }

    #[test]
    fn test_case_sensitive_compare() {
        let m_a = Var::mk_map(&[
            (Var::mk_str("a"), Var::mk_str("a")),
            (Var::mk_str("b"), Var::mk_str("b")),
            (Var::mk_str("c"), Var::mk_str("c")),
        ]);

        let m_b = Var::mk_map(&[
            (Var::mk_str("A"), Var::mk_str("A")),
            (Var::mk_str("B"), Var::mk_str("B")),
            (Var::mk_str("C"), Var::mk_str("C")),
        ]);

        assert!(!m_a.eq_case_sensitive(&m_b));
        assert!(m_a.eq(&m_b));
    }

    #[test]
    fn test_contains_index() {
        // ; $tmp = ["FOO" -> "BAR"];
        // ; return "bar" in $tmp;
        let m = Var::mk_map(&[(Var::mk_str("FOO"), Var::mk_str("BAR"))]);
        let key = Var::mk_str("bar");

        let result = m.index_in(&key, false, IndexMode::OneBased).unwrap();
        assert_eq!(result, v_bool_int(true));
    }

    #[test]
    fn test_signed_zero_is_one_key() {
        // -0.0 == 0.0, so a map must treat them as the same key.
        use std::hash::{BuildHasher, RandomState};
        let positive = v_float(0.0);
        let negative = v_float(-0.0);
        assert_eq!(positive, negative);
        assert_eq!(positive.cmp(&negative), std::cmp::Ordering::Equal);
        let hasher = RandomState::new();
        assert_eq!(hasher.hash_one(&positive), hasher.hash_one(&negative));

        let m = Var::mk_map(&[(positive.clone(), v_str("pos"))]);
        let Variant::Map(map) = m.variant() else {
            panic!("not a map");
        };
        assert_eq!(map.get(&negative).unwrap(), v_str("pos"));
        assert!(map.contains_key(&negative, false).unwrap());

        // Built from both, as a literal or a stored map is, the later entry wins.
        let both = Var::mk_map(&[(negative, v_int(1)), (positive, v_int(2))]);
        let Variant::Map(both) = both.variant() else {
            panic!("not a map");
        };
        assert_eq!(both.len(), 1);
        assert_eq!(both.get(&v_float(0.0)).unwrap(), v_int(2));
    }

    #[test]
    fn test_int_and_float_are_different_keys() {
        // 1 == 1.0 is false, so a map must keep them apart.
        assert_ne!(v_int(1), v_float(1.0));
        assert_ne!(v_int(1).cmp(&v_float(1.0)), std::cmp::Ordering::Equal);

        let m = Var::mk_map(&[(v_int(1), v_str("int"))]);
        let Variant::Map(map) = m.variant() else {
            panic!("not a map");
        };
        assert!(map.get(&v_float(1.0)).is_err());
        assert!(!map.contains_key(&v_float(1.0), false).unwrap());

        let both = Var::mk_map(&[(v_int(1), v_str("int")), (v_float(1.0), v_str("float"))]);
        let Variant::Map(both) = both.variant() else {
            panic!("not a map");
        };
        assert_eq!(both.len(), 2);
        assert_eq!(both.get(&v_float(1.0)).unwrap(), v_str("float"));

        // Mixed numbers still sort by value, the int first on a tie.
        let mut sorted = vec![v_float(2.5), v_int(1), v_float(1.0), v_int(-3)];
        sorted.sort();
        assert_eq!(
            sorted,
            vec![v_int(-3), v_int(1), v_float(1.0), v_float(2.5)]
        );
    }

    #[test]
    fn test_equal_lambdas_hash_alike() {
        // Lambdas compare by structure, so two equal ones in separate allocations, as a value
        // loaded twice from the database is, must hash alike for hash lookups to find each other.
        use crate::program::{labels::Label, opcode::ScatterArgs, program::Program};
        use std::hash::{BuildHasher, RandomState};
        let lambda = || {
            Var::mk_lambda(
                ScatterArgs {
                    labels: vec![],
                    done: Label(0),
                },
                Program::new(),
                vec![],
                None,
            )
        };
        let (first, second) = (lambda(), lambda());
        assert_eq!(first, second);
        let hasher = RandomState::new();
        assert_eq!(hasher.hash_one(&first), hasher.hash_one(&second));
    }

    #[test]
    fn test_errors_order_as_they_compare() {
        // == compares an error's code and value, never its message; ordering must agree.
        use crate::{E_DIV, E_PERM, E_TYPE, v_err, v_error};
        let bare = v_err(E_PERM);
        let explained = v_error(E_PERM.msg("not yours"));
        assert_eq!(bare, explained);
        assert_eq!(bare.cmp(&explained), std::cmp::Ordering::Equal);

        let m = Var::mk_map(&[(bare, v_str("denied"))]);
        let Variant::Map(map) = m.variant() else {
            panic!("not a map");
        };
        assert_eq!(map.get(&explained).unwrap(), v_str("denied"));

        // A message no longer moves an error past later codes: E_TYPE comes before E_DIV.
        assert!(E_TYPE < E_DIV);
        let type_error = v_error(E_TYPE.msg("not a number"));
        assert_eq!(type_error.cmp(&v_err(E_DIV)), std::cmp::Ordering::Less);
    }
}

/// Tests of the map's own structure: the single block, the tree, and sharing between copies.
#[cfg(test)]
mod structure_tests {
    use super::{
        BRANCH_MAX, BUILT_FILL, Entry, FLAT_AGAIN, FLAT_MAX, LEAF_MAX, MERGE_BELOW, Map, Node,
        Repr, find,
    };
    use crate::{Associative, Var, v_int, v_str};
    use proptest::prelude::*;
    use std::cmp::Ordering;

    /// A map kept as a sorted `Vec`, to compare against.
    #[derive(Clone, Default)]
    struct Model(Vec<Entry>);

    impl Model {
        fn set(&mut self, key: Var, value: Var) -> bool {
            match find(&self.0, &key) {
                Ok(index) => {
                    self.0[index] = (key, value);
                    false
                }
                Err(index) => {
                    self.0.insert(index, (key, value));
                    true
                }
            }
        }

        fn remove(&mut self, key: &Var) -> Option<Var> {
            find(&self.0, key).ok().map(|index| self.0.remove(index).1)
        }
    }

    fn ints(len: usize) -> Vec<Entry> {
        (0..len as i64).map(|i| (v_int(i * 2), v_int(-i))).collect()
    }

    fn assert_matches(map: &Map, model: &Model) {
        let model = &model.0;
        assert_eq!(map.len(), model.len());
        assert!(map.entries_from(0).eq(model.iter()));
        assert_eq!(map.entries_from(0).len(), model.len());
        assert_eq!(map.first().ok(), model.first().cloned());
        let step = model.len() / 61 + 1;
        for index in (0..model.len()).step_by(step) {
            let (key, value) = &model[index];
            assert_eq!(map.entry_at(index), Some(&model[index]));
            assert_eq!(map.get(key).as_ref(), Ok(value));
            assert_eq!(map.lower_bound(key), index);
            assert!(map.entries_from(index).eq(model[index..].iter()));
            assert_eq!(
                map.next_after(key, false).ok(),
                model.get(index + 1).cloned()
            );
            assert_eq!(
                map.next_after(key, true).ok(),
                model.get(index + 1).cloned()
            );
        }
        assert_eq!(map.entry_at(model.len()), None);
        assert!(map.entries_from(model.len() + 5).next().is_none());
        check_tree(map);
    }

    /// The sizes of a map's leaves, in order. Checks on the way that each branch's counts and
    /// greatest keys describe its children, that no node is empty, and that every leaf is at
    /// the same depth.
    fn check_tree(map: &Map) -> Vec<usize> {
        fn walk(node: &Node, depth: usize, leaves: &mut Vec<(usize, usize)>) {
            assert!(!node.is_empty() || depth == 0);
            match node {
                Node::Leaf(leaf) => leaves.push((depth, leaf.len())),
                Node::Branch(branch) => {
                    assert_eq!(branch.children.len(), branch.counts.len());
                    assert_eq!(branch.children.len(), branch.last_keys.len());
                    assert!(branch.children.len() <= BRANCH_MAX);
                    for (index, child) in branch.children.iter().enumerate() {
                        assert_eq!(branch.counts[index], child.len());
                        assert_eq!(
                            branch.last_keys.as_slice()[index].cmp(child.last_key()),
                            Ordering::Equal
                        );
                        walk(child, depth + 1, leaves);
                    }
                }
            }
        }
        let mut leaves = vec![];
        match map.repr() {
            Repr::Flat(block) => leaves.push((0, block.len())),
            Repr::Tree(tree) => {
                assert_eq!(tree.len, tree.root.len());
                walk(&tree.root, 0, &mut leaves);
            }
        }
        assert!(leaves.iter().all(|(depth, _)| *depth == leaves[0].0));
        leaves.into_iter().map(|(_, len)| len).collect()
    }

    /// Sizes on both sides of each change of shape: empty, a full block, the first split, a
    /// second level of branches, and beyond.
    fn sizes() -> Vec<usize> {
        let mut sizes = vec![0, 1, 2, FLAT_MAX - 1, FLAT_MAX, FLAT_MAX + 1, 100];
        sizes.extend([FLAT_MAX * BRANCH_MAX, FLAT_MAX * BRANCH_MAX + 1]);
        if !cfg!(miri) {
            sizes.extend([5000, 40_000]);
        }
        sizes
    }

    #[test]
    fn built_maps_hold_their_entries_at_every_shape() {
        for len in sizes() {
            let model = Model(ints(len));
            assert_matches(&Map::from_sorted(model.0.clone()), &model);
        }
    }

    #[test]
    fn setting_keys_one_at_a_time_matches_building_at_once() {
        let sizes = sizes();
        let limit = if cfg!(miri) { 400 } else { 6000 };
        // Ascending, descending, and scattered.
        for order in 0..3 {
            let mut map = Map::from_sorted(vec![]);
            let mut model = Model::default();
            for step in 0..limit as i64 {
                let key = match order {
                    0 => step,
                    1 => -step,
                    _ => (step * 7919) % limit as i64,
                };
                let (next, added) = map.inserted(v_int(key), v_int(step));
                assert_eq!(added, model.set(v_int(key), v_int(step)));
                map = next;
                if sizes.contains(&model.0.len()) {
                    assert_matches(&map, &model);
                }
            }
            assert_matches(&map, &model);
        }
    }

    #[test]
    fn removing_every_key_empties_the_map_in_any_order() {
        let len = if cfg!(miri) { 300 } else { 5000 };
        for order in 0..3 {
            let mut model = Model(ints(len));
            let mut map = Map::from_sorted(model.0.clone());
            let original = map.clone();
            for step in 0..len {
                let index = match order {
                    0 => 0,
                    1 => model.0.len() - 1,
                    _ => (step * 7919) % model.0.len(),
                };
                let key = model.0[index].0.clone();
                let (next, removed) = map.removed(&key);
                assert_eq!(removed, model.remove(&key));
                map = next;
                if step % 97 == 0 {
                    assert_matches(&map, &model);
                }
            }
            assert_eq!(map.len(), 0);
            assert_matches(&original, &Model(ints(len)));
        }
    }

    #[test]
    fn edits_leave_other_copies_unchanged() {
        for len in sizes().into_iter().filter(|len| *len > 0) {
            let model = Model(ints(len));
            let original = Map::from_sorted(model.0.clone());
            for index in [0, len / 2, len - 1] {
                let key = model.0[index].0.clone();

                let (changed, added) = original.clone().inserted(key.clone(), v_int(7));
                assert!(!added);
                let mut expected = model.clone();
                expected.set(key.clone(), v_int(7));
                assert_matches(&changed, &expected);

                let (removed, value) = original.clone().removed(&key);
                let mut expected = model.clone();
                assert_eq!(value, expected.remove(&key));
                assert_matches(&removed, &expected);

                // An odd key is between two of the even ones.
                let between = v_int(index as i64 * 2 + 1);
                let (grown, added) = original.clone().inserted(between.clone(), v_int(8));
                assert!(added);
                let mut expected = model.clone();
                expected.set(between, v_int(8));
                assert_matches(&grown, &expected);
            }
            let (missing, value) = original.clone().removed(&v_int(-1));
            assert_eq!(value, None);
            assert!(missing.is_identical(&original));
            assert_matches(&original, &model);
        }
    }

    #[test]
    fn a_large_map_shares_untouched_blocks_with_its_edit() {
        let model = Model(ints(5000));
        let original = Map::from_sorted(model.0.clone());
        let (edited, _) = original.clone().inserted(v_int(8000), v_int(1));
        assert!(std::ptr::eq(
            original.entry_at(10).unwrap(),
            edited.entry_at(10).unwrap()
        ));
        assert!(!std::ptr::eq(
            original.entry_at(4000).unwrap(),
            edited.entry_at(4000).unwrap()
        ));
        assert_eq!(original.get(&v_int(8000)), Ok(v_int(-4000)));
    }

    #[test]
    fn a_map_around_the_block_limit_does_not_change_shape_on_every_edit() {
        let model = Model(ints(FLAT_MAX));
        let mut map = Map::from_sorted(model.0.clone());
        assert!(!map.0.is_tree());
        let extra = v_int(-1);
        for _ in 0..3 {
            map = map.inserted(extra.clone(), v_int(0)).0;
            assert!(map.0.is_tree());
            map = map.removed(&extra).0;
            // Back to the block's size, but still a tree: it has not shrunk far enough.
            assert!(map.0.is_tree());
            assert_matches(&map, &model);
        }
        // Removing entries down to the lower limit makes it a block again.
        let mut model = model;
        while model.0.len() > FLAT_AGAIN {
            let key = model.0[0].0.clone();
            model.remove(&key);
            map = map.removed(&key).0;
        }
        assert!(!map.0.is_tree());
        assert_matches(&map, &model);
    }

    #[test]
    fn keys_added_in_ascending_order_fill_their_leaves() {
        let len = 40 * LEAF_MAX;
        let mut map = Map::from_sorted(vec![]);
        for i in 0..len as i64 {
            map = map.inserted(v_int(i), v_int(i)).0;
        }
        let leaves = check_tree(&map);
        assert!(
            leaves[..leaves.len() - 1]
                .iter()
                .all(|leaf| *leaf == LEAF_MAX)
        );
        assert_eq!(leaves.len(), len.div_ceil(LEAF_MAX));
    }

    #[test]
    fn a_small_leaf_merges_with_either_neighbor() {
        // Built as three leaves, then the last filled up.
        let built = BUILT_FILL as i64;
        let mut model = Model(ints(3 * BUILT_FILL));
        let mut map = Map::from_sorted(model.0.clone());
        for i in 3 * built..2 * built + LEAF_MAX as i64 {
            model.set(v_int(i * 2), v_int(0));
            map = map.inserted(v_int(i * 2), v_int(0)).0;
        }
        assert_eq!(check_tree(&map), [BUILT_FILL, BUILT_FILL, LEAF_MAX]);
        // Empty the middle leaf to one entry short of small. The last leaf has no room for
        // what is left, but the first does.
        let left = MERGE_BELOW - 1;
        for i in built..2 * built - left as i64 {
            assert!(model.remove(&v_int(i * 2)).is_some());
            map = map.removed(&v_int(i * 2)).0;
        }
        assert_eq!(check_tree(&map), [BUILT_FILL + left, LEAF_MAX]);
        assert_matches(&map, &model);
    }

    #[test]
    fn the_position_after_a_key_is_where_a_loop_resumes() {
        let map = Map::from_sorted(ints(100));
        assert_eq!(map.position_after(&v_int(0)), 1);
        assert_eq!(map.position_after(&v_int(20)), 11);
        // An absent key counts as the entry that follows it, as `next_after` treats it.
        assert_eq!(map.position_after(&v_int(21)), 12);
        assert_eq!(map.position_after(&v_int(-5)), 1);
        assert_eq!(map.position_after(&v_int(198)), 100);
        assert_eq!(map.position_after(&v_int(500)), 100);
        assert_eq!(Map::from_sorted(vec![]).position_after(&v_int(1)), 0);
        for (key, _) in ints(100) {
            let after = map.position_after(&key);
            assert_eq!(
                map.entry_at(after).cloned(),
                map.next_after(&key, false).ok()
            );
        }
    }

    // Through `Var` and with string keys, so not under Miri, which rejects `Var`'s storage of
    // pointers as integers.
    #[test]
    #[cfg_attr(miri, ignore)]
    fn a_key_given_again_replaces_the_stored_key() {
        let built = Var::mk_map(&[
            (v_str("Name"), v_int(1)),
            (v_int(3), v_int(2)),
            (v_str("name"), v_int(4)),
        ]);
        let map = built.as_map().unwrap();
        assert_eq!(map.len(), 2);
        assert_eq!(map.keys(), vec![v_int(3), v_str("name")]);
        assert!(map.keys()[1].eq_case_sensitive(&v_str("name")));
        assert_eq!(map.get(&v_str("NAME")), Ok(v_int(4)));

        let (set, added) = map.clone().inserted(v_str("NAME"), v_int(5));
        assert!(!added);
        assert!(set.keys()[1].eq_case_sensitive(&v_str("NAME")));
        assert_eq!(map.contains_key(&v_str("NAME"), true), Ok(false));
        assert_eq!(map.contains_key(&v_str("NAME"), false), Ok(true));
        assert_eq!(map.clone().remove_owned(&v_str("NAME"), true).1, None);
        assert_eq!(
            map.clone().remove_owned(&v_str("name"), true).1,
            Some(v_int(4))
        );
        assert_eq!(
            map.clone().remove_owned(&v_str("NAME"), false).1,
            Some(v_int(4))
        );
    }

    #[derive(Clone, Debug)]
    enum Edit {
        Set(i64, bool),
        Remove(i64),
        RemoveExact(i64, bool),
        Range(i64, i64),
        Rebuild(usize),
        KeepCopy,
    }

    fn edit() -> impl Strategy<Value = Edit> {
        let key = -20i64..600;
        prop_oneof![
            8 => (key.clone(), any::<bool>()).prop_map(|(k, upper)| Edit::Set(k, upper)),
            4 => key.clone().prop_map(Edit::Remove),
            1 => (key.clone(), any::<bool>()).prop_map(|(k, upper)| Edit::RemoveExact(k, upper)),
            1 => (key.clone(), key).prop_map(|(a, b)| Edit::Range(a, b)),
            1 => (0usize..if cfg!(miri) { 120 } else { 1500 }).prop_map(Edit::Rebuild),
            2 => Just(Edit::KeepCopy),
        ]
    }

    /// Even numbers are integer keys. Odd ones are string keys in either case, which are one key.
    /// Miri cannot follow a string `Var`, so under it every key is an integer.
    fn key(number: i64, upper: bool) -> Var {
        if cfg!(miri) || number % 2 == 0 {
            v_int(number)
        } else if upper {
            v_str(&format!("KEY{number}"))
        } else {
            v_str(&format!("key{number}"))
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(if cfg!(miri) { 4 } else { 200 }))]

        /// Any run of edits leaves the map equal to a sorted `Vec` given the same edits, and
        /// leaves every earlier copy as it was.
        #[test]
        fn edits_match_a_sorted_vec(edits in prop::collection::vec(edit(), 1..if cfg!(miri) { 60 } else { 150 })) {
            let mut map = Map::from_sorted(vec![]);
            let mut model = Model::default();
            let mut copies: Vec<(Map, Model)> = vec![];
            for (step, edit) in edits.into_iter().enumerate() {
                match edit {
                    Edit::Set(number, upper) => {
                        let (next, added) = map.inserted(key(number, upper), v_int(step as i64));
                        prop_assert_eq!(added, model.set(key(number, upper), v_int(step as i64)));
                        map = next;
                        let stored = &map.entry_for(&key(number, upper)).unwrap().0;
                        prop_assert!(stored.eq_case_sensitive(&key(number, upper)));
                    }
                    Edit::Remove(number) => {
                        let (next, removed) = map.removed(&key(number, false));
                        prop_assert_eq!(removed, model.remove(&key(number, false)));
                        map = next;
                    }
                    Edit::RemoveExact(number, upper) if !cfg!(miri) => {
                        let wanted = key(number, upper);
                        let exact = model.0.iter().any(|(k, _)| k.eq_case_sensitive(&wanted));
                        prop_assert_eq!(map.contains_key(&wanted, true), Ok(exact));
                        let (next, removed) = map.remove_owned(&wanted, true);
                        let expected = if exact { model.remove(&wanted) } else { None };
                        prop_assert_eq!(removed, expected);
                        map = next.as_map().unwrap().clone();
                    }
                    Edit::Range(a, b) if !cfg!(miri) => {
                        let (from, to) = (key(a, false), key(b, false));
                        let expected: Option<Vec<Entry>> = find(&model.0, &from).ok().map(|at| {
                            model.0[at..]
                                .iter()
                                .take_while(|(k, _)| k.cmp(&to) == Ordering::Less)
                                .cloned()
                                .collect()
                        });
                        let range = map.range(&from, &to).ok();
                        let range = range.as_ref().map(|r| r.as_map().unwrap());
                        prop_assert_eq!(range.is_some(), expected.is_some());
                        if let (Some(range), Some(expected)) = (range, expected) {
                            assert_matches(range, &Model(expected));
                        }
                    }
                    Edit::Rebuild(len) => {
                        model = Model(ints(len));
                        map = Map::from_sorted(model.0.clone());
                    }
                    Edit::KeepCopy => copies.push((map.clone(), model.clone())),
                    Edit::RemoveExact(..) | Edit::Range(..) => {}
                }
                assert_matches(&map, &model);
            }
            for (copy, model) in &copies {
                assert_matches(copy, model);
            }
        }
    }
}
