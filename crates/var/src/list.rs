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

//! MOO lists.
//!
//! A list is an immutable value: every edit yields a new list and leaves the original as it was.
//! Most MOO lists are short and are built once, so a list of up to [`FLAT_MAX`] items is a single
//! reference-counted block holding the items. A longer list is a persistent tree of such blocks,
//! in which an edited list shares every block it did not touch with the list it came from.
//!
//! A `List` is one pointer wide. `Var` stores it in its data word.

use crate::{
    Error, Sequence, Var,
    block::{Shape, ShapeOwned, ShapeRef},
    error::ErrorCode::{E_RANGE, E_TYPE},
    v_none,
    variant::OP_HINT_LIST_APPEND,
};
use std::{
    cmp::{max, min},
    fmt::{Debug, Formatter},
    hash::Hash,
    ops::Index,
};
use triomphe::Arc;

type Block = crate::block::Block<Var>;
type Repr<'a> = ShapeRef<'a, Var, Tree>;
type Owned = ShapeOwned<Var, Tree>;

/// The most items a list holds in one block. A longer list is a tree.
///
/// The database compares up to this many items of an appended list against its base without the
/// help of shared storage; see `append_suffix`.
const FLAT_MAX: usize = 64;

/// Each tree node has up to `1 << LEAF_BITS` children, and each leaf that many items.
const LEAF_BITS: u32 = 5;
const LEAF_WIDTH: usize = 1 << LEAF_BITS;
const LEAF_MASK: usize = LEAF_WIDTH - 1;

#[derive(Clone)]
enum Node {
    Branch(Arc<Branch>),
    /// A full block of `LEAF_WIDTH` items.
    Leaf(Block),
    /// Slots before the start of the list, whose items have been released.
    Dropped,
}

#[derive(Clone)]
struct Branch {
    children: Vec<Node>,
}

impl Branch {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            children: Vec::with_capacity(LEAF_WIDTH),
        })
    }
}

/// A persistent vector for lists longer than `FLAT_MAX`.
///
/// Items sit in numbered slots. The slots up to `end` are filled, and the list is those from
/// `start` on, so dropping items from the front moves `start` and releases what the dropped slots
/// held. The last slots, at most
/// `LEAF_WIDTH` of them, are in `tail`. The slots before them are in full leaves under `root`,
/// found by taking `LEAF_BITS` of the slot number at each level, starting at `shift`. The children
/// of a branch at level `LEAF_BITS` are leaves, and those of a higher branch are branches.
///
/// Two trees can share a leaf only where it covers the same slots modulo `LEAF_WIDTH` in both, so
/// a tree built from part of another starts at a slot chosen to line the two up.
#[derive(Clone)]
struct Tree {
    start: usize,
    end: usize,
    shift: u32,
    root: Arc<Branch>,
    tail: Block,
}

/// A run of consecutive items held in one block.
struct Chunk<'a> {
    /// The list index of the first item.
    start: usize,
    items: &'a [Var],
    /// The block, if it is a full tree leaf and `items` is all of it.
    leaf: Option<&'a Block>,
}

/// A tree is rebuilt without its dropped slots once it has this many, if they outnumber its items.
const COMPACT_MIN_DROPPED: usize = 8 * LEAF_WIDTH;

impl Tree {
    fn new() -> Self {
        Self::with_padding(0)
    }

    /// An empty tree whose first item will go in slot `padding`.
    fn with_padding(padding: usize) -> Self {
        assert!(padding < LEAF_WIDTH);
        let mut tail = Block::with_capacity(LEAF_WIDTH);
        for _ in 0..padding {
            // SAFETY: the block is new, so unshared, and `padding` is less than its capacity.
            unsafe { tail.push_unchecked(v_none()) };
        }
        Self {
            start: padding,
            end: padding,
            shift: LEAF_BITS,
            root: Branch::new(),
            tail,
        }
    }

    #[inline]
    fn len(&self) -> usize {
        self.end - self.start
    }

    /// The first slot of the tail.
    #[inline]
    fn tail_start(&self) -> usize {
        self.end - self.tail.len()
    }

    /// The leaf holding `slot`, which must come before the tail.
    fn leaf_at(&self, slot: usize) -> &Block {
        let mut branch = &*self.root;
        let mut level = self.shift;
        loop {
            match &branch.children[(slot >> level) & LEAF_MASK] {
                Node::Leaf(leaf) => return leaf,
                Node::Branch(child) => {
                    branch = child;
                    level -= LEAF_BITS;
                }
                Node::Dropped => unreachable!("slot before the start of the list"),
            }
        }
    }

    /// The items from `index` back to the start of their block, or of the list, and on to the
    /// block's end.
    fn chunk_at(&self, index: usize) -> Chunk<'_> {
        let slot = self.start + index;
        let tail_start = self.tail_start();
        let (first_slot, block, leaf) = if slot >= tail_start {
            (tail_start, &self.tail, None)
        } else {
            let leaf = self.leaf_at(slot);
            (slot & !LEAF_MASK, leaf, Some(leaf))
        };
        let dropped = self.start.saturating_sub(first_slot);
        Chunk {
            start: first_slot + dropped - self.start,
            items: &block.as_slice()[dropped..],
            leaf: leaf.filter(|_| dropped == 0),
        }
    }

    #[inline]
    fn get(&self, index: usize) -> &Var {
        let chunk = self.chunk_at(index);
        &chunk.items[index - chunk.start]
    }

    fn set(&mut self, index: usize, value: Var) {
        let slot = self.start + index;
        let tail_start = self.tail_start();
        if slot >= tail_start {
            self.tail.as_mut_slice()[slot - tail_start] = value;
            return;
        }
        let mut branch = Arc::make_mut(&mut self.root);
        let mut level = self.shift;
        loop {
            match &mut branch.children[(slot >> level) & LEAF_MASK] {
                Node::Leaf(leaf) => {
                    leaf.as_mut_slice()[slot & LEAF_MASK] = value;
                    return;
                }
                Node::Branch(child) => {
                    branch = Arc::make_mut(child);
                    level -= LEAF_BITS;
                }
                Node::Dropped => unreachable!("slot before the start of the list"),
            }
        }
    }

    /// Move a full tail into the tree and start an empty one.
    fn rotate_full_tail(&mut self) {
        if self.tail.len() == LEAF_WIDTH {
            let full = std::mem::replace(&mut self.tail, Block::with_capacity(LEAF_WIDTH));
            self.push_leaf(full);
        }
    }

    fn push(&mut self, value: Var) {
        self.rotate_full_tail();
        self.tail.push(value, LEAF_WIDTH);
        self.end += 1;
    }

    /// Add copies of `values` at the end, a block at a time.
    fn extend_from_slice(&mut self, mut values: &[Var]) {
        while !values.is_empty() {
            self.rotate_full_tail();
            let room = LEAF_WIDTH - self.tail.len();
            let (now, later) = values.split_at(room.min(values.len()));
            self.tail.extend_from_slice(now, LEAF_WIDTH);
            self.end += now.len();
            values = later;
        }
    }

    /// Add the items from index `from` up to `to` of a list, read through `chunk_at`, at the end.
    ///
    /// A full leaf of the list is shared, not copied, when it lands on a leaf boundary here.
    fn extend_from<'a>(&mut self, chunk_at: impl Fn(usize) -> Chunk<'a>, from: usize, to: usize) {
        let mut index = from;
        while index < to {
            let chunk = chunk_at(index);
            let end = to.min(chunk.start + chunk.items.len());
            assert!(index < end, "list range out of bounds");
            self.rotate_full_tail();
            if let Some(leaf) = chunk.leaf
                && self.tail.len() == 0
                && index == chunk.start
                && end == chunk.start + LEAF_WIDTH
            {
                self.end += LEAF_WIDTH;
                self.push_leaf(leaf.clone());
            } else {
                self.extend_from_slice(&chunk.items[index - chunk.start..end - chunk.start]);
            }
            index = end;
        }
    }

    /// Add a full leaf to the tree as its last. The tail must be empty, and `end` must already
    /// count the leaf's items.
    fn push_leaf(&mut self, leaf: Block) {
        debug_assert_eq!(leaf.len(), LEAF_WIDTH);
        debug_assert_eq!(self.tail.len(), 0);
        let leaf_start = self.end - LEAF_WIDTH;
        // A root at level `shift` holds `LEAF_WIDTH << shift` slots. When it is full, it becomes
        // the first child of a new root one level up.
        if leaf_start == LEAF_WIDTH << self.shift {
            let full_root = std::mem::replace(&mut self.root, Branch::new());
            Arc::get_mut(&mut self.root)
                .expect("new root is unshared")
                .children
                .push(Node::Branch(full_root));
            self.shift += LEAF_BITS;
        }
        Self::insert_leaf(&mut self.root, self.shift, leaf_start, leaf);
    }

    fn insert_leaf(branch: &mut Arc<Branch>, level: u32, leaf_start: usize, leaf: Block) {
        let branch = Arc::make_mut(branch);
        if level == LEAF_BITS {
            branch.children.push(Node::Leaf(leaf));
            return;
        }
        let slot = (leaf_start >> level) & LEAF_MASK;
        if slot == branch.children.len() {
            branch.children.push(Node::Branch(Branch::new()));
        }
        let Node::Branch(child) = &mut branch.children[slot] else {
            unreachable!("a branch above the lowest level holds branches");
        };
        Self::insert_leaf(child, level - LEAF_BITS, leaf_start, leaf);
    }

    /// Take the last leaf out of the tree, removing any branch that leaves empty.
    fn remove_last_leaf(branch: &mut Arc<Branch>, level: u32) -> Block {
        let branch = Arc::make_mut(branch);
        if level == LEAF_BITS {
            let Some(Node::Leaf(leaf)) = branch.children.pop() else {
                unreachable!("the lowest branches hold leaves, and a leaf is there to take");
            };
            return leaf;
        }
        let Some(Node::Branch(child)) = branch.children.last_mut() else {
            unreachable!("a branch above the lowest level holds branches");
        };
        let leaf = Self::remove_last_leaf(child, level - LEAF_BITS);
        if child.children.is_empty() {
            branch.children.pop();
        }
        leaf
    }

    /// Drop items from the end until `len` are left.
    fn truncate(&mut self, len: usize) {
        let end = self.start + len;
        while self.end > end {
            if self.tail.len() == 0 {
                self.tail = Self::remove_last_leaf(&mut self.root, self.shift);
            }
            let cut = (self.end - end).min(self.tail.len());
            self.tail.truncate(self.tail.len() - cut, LEAF_WIDTH);
            self.end -= cut;
        }
    }

    /// Drop `count` items from the front.
    fn drop_front(&mut self, count: usize) {
        assert!(count <= self.len());
        let (from, to) = (self.start, self.start + count);
        self.start = to;
        // Slot numbers only grow. Once the dropped slots are the larger part of the tree, start
        // again from a low slot. The new tree lines up with this one, so it shares the leaves.
        if self.start >= COMPACT_MIN_DROPPED && self.start > self.len() {
            let mut compact = Self::with_padding(self.start & LEAF_MASK);
            compact.extend_from(|index| self.chunk_at(index), 0, self.len());
            *self = compact;
            return;
        }
        if count == 1 {
            self.release_one(from);
        } else {
            self.release(from, to);
        }
    }

    /// `release` for the single slot `slot`, as when a queue gives up its first item.
    fn release_one(&mut self, slot: usize) {
        let tail_start = self.tail_start();
        if slot >= tail_start {
            self.tail.as_mut_slice()[slot - tail_start] = v_none();
            return;
        }
        let mut branch = Arc::make_mut(&mut self.root);
        let mut level = self.shift;
        while level > LEAF_BITS {
            let Node::Branch(child) = &mut branch.children[(slot >> level) & LEAF_MASK] else {
                unreachable!("a branch above the lowest level that holds a kept slot");
            };
            branch = Arc::make_mut(child);
            level -= LEAF_BITS;
        }
        match &mut branch.children[(slot >> LEAF_BITS) & LEAF_MASK] {
            Node::Leaf(leaf) if slot & LEAF_MASK != LEAF_MASK => {
                leaf.as_mut_slice()[slot & LEAF_MASK] = v_none();
            }
            // The last slot of its leaf, so the whole leaf is gone.
            leaf => *leaf = Node::Dropped,
        }
    }

    /// Let go of the items in slots `from` up to `to`, which the list no longer includes, so
    /// that this tree does not keep them alive.
    fn release(&mut self, from: usize, to: usize) {
        let tail_start = self.tail_start();
        if to > tail_start {
            let first = from.max(tail_start) - tail_start;
            self.tail.as_mut_slice()[first..to - tail_start].fill(v_none());
        }
        let to = to.min(tail_start);
        if from < to {
            Self::release_in(&mut self.root, self.shift, 0, from, to);
        }
    }

    /// `release` for the part of the range under `branch`, whose first slot is `base`.
    fn release_in(branch: &mut Arc<Branch>, level: u32, base: usize, from: usize, to: usize) {
        let branch = Arc::make_mut(branch);
        let first = (from - base) >> level;
        for (index, child) in branch.children.iter_mut().enumerate().skip(first) {
            let child_base = base + (index << level);
            if child_base >= to {
                break;
            }
            // Everything below `to` is dropped, so a child that ends there or before is all gone.
            if child_base + (1 << level) <= to {
                *child = Node::Dropped;
                continue;
            }
            let from = from.max(child_base);
            match child {
                Node::Branch(child) => {
                    Self::release_in(child, level - LEAF_BITS, child_base, from, to);
                }
                Node::Leaf(leaf) => {
                    leaf.as_mut_slice()[from - child_base..to - child_base].fill(v_none());
                }
                Node::Dropped => {}
            }
        }
    }
}

/// A MOO list. See the module documentation.
#[derive(Clone)]
#[repr(transparent)]
pub struct List(Shape<Var, Tree>);

/// Why a list is not its base with items appended. See [`List::append_suffix`].
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ListAppendError {
    /// The candidate does not add elements.
    NotLonger,
    /// The existing list is not a prefix of the candidate.
    PrefixMismatch,
    /// Prefix validation needs more element comparisons than the caller permits.
    ComparisonBudgetExceeded,
}

impl List {
    #[inline]
    fn from_block(block: Block) -> Self {
        Self(Shape::from_block(block))
    }

    #[inline]
    fn from_tree(tree: Arc<Tree>) -> Self {
        Self(Shape::from_tree(tree))
    }

    /// A list of the tree's items: the tree itself, or a single block if it has become short.
    fn from_edited_tree(tree: Arc<Tree>) -> Self {
        let list = Self::from_tree(tree);
        if list.len() > FLAT_MAX {
            return list;
        }
        list.iter_ref().cloned().collect()
    }

    #[inline]
    fn is_tree(&self) -> bool {
        self.0.is_tree()
    }

    #[inline]
    fn repr(&self) -> Repr<'_> {
        self.0.get()
    }

    #[inline]
    fn into_owned(self) -> Owned {
        self.0.into_owned()
    }

    /// Whether both share the same storage, or are small lists of identical items: never true
    /// for lists that differ. See `Var::is_identical`.
    pub fn is_identical(&self, other: &Self) -> bool {
        if self.0.ptr_eq(&other.0) {
            return true;
        }
        // Small lists are cheap to build afresh, so their few items decide.
        const SMALL: usize = 3;
        self.len() <= SMALL
            && self.len() == other.len()
            && self
                .iter_ref()
                .zip(other.iter_ref())
                .all(|(a, b)| a.is_identical(b))
    }

    /// Compare list elements using the storage guarantee of [`Var::eq_exact`].
    pub(crate) fn eq_exact(&self, other: &Self) -> bool {
        if self.0.ptr_eq(&other.0) {
            return true;
        }
        if self.len() != other.len() {
            return false;
        }
        self.iter_ref()
            .zip(other.iter_ref())
            .all(|(a, b)| a.eq_exact(b))
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    #[inline]
    pub fn len(&self) -> usize {
        match self.repr() {
            Repr::Flat(block) => block.len(),
            Repr::Tree(tree) => tree.len(),
        }
    }

    #[inline]
    fn get(&self, index: usize) -> &Var {
        match self.repr() {
            Repr::Flat(block) => &block.as_slice()[index],
            Repr::Tree(tree) => tree.get(index),
        }
    }

    /// The items from `index` back to the start of their block, or of the list, and on to the
    /// block's end.
    fn chunk_at(&self, index: usize) -> Chunk<'_> {
        match self.repr() {
            Repr::Flat(block) => Chunk {
                start: 0,
                items: block.as_slice(),
                leaf: None,
            },
            Repr::Tree(tree) => tree.chunk_at(index),
        }
    }

    /// The slot of the first item, by which a tree built from this list lines up with it.
    fn first_slot(&self) -> usize {
        match self.repr() {
            Repr::Flat(_) => 0,
            Repr::Tree(tree) => tree.start,
        }
    }

    pub fn build(values: &[Var]) -> Var {
        Var::from_list(Self::mk_list(values))
    }

    pub fn mk_list(values: &[Var]) -> List {
        if values.len() <= FLAT_MAX {
            return Self::from_block(Block::from_slice(values));
        }
        values.iter().cloned().collect()
    }

    pub fn iter(&self) -> impl Iterator<Item = Var> + '_ {
        self.iter_ref().cloned()
    }

    pub fn iter_ref(&self) -> Iter<'_> {
        let (current, tree) = match self.repr() {
            Repr::Flat(block) => (block.as_slice(), None),
            Repr::Tree(tree) => (&[][..], Some(tree)),
        };
        Iter {
            current: current.iter(),
            tree,
            next_chunk: 0,
            remaining: self.len(),
        }
    }

    /// Return the suffix added to this list after a bounded prefix comparison.
    ///
    /// Blocks the two lists share need no element comparisons. The comparison budget limits work
    /// on changed or independently constructed blocks, and unshared elements must match in stored
    /// representation (case-sensitive strings and symbols, error messages, and float bits).
    pub fn append_suffix(
        &self,
        candidate: &Self,
        mut comparison_budget: usize,
    ) -> Result<Self, ListAppendError> {
        let prefix_len = self.len();
        if candidate.len() <= prefix_len {
            return Err(ListAppendError::NotLonger);
        }

        let mut index = 0;
        while index < prefix_len {
            let prefix = self.chunk_at(index);
            let candidate = candidate.chunk_at(index);
            let end = prefix_len
                .min(prefix.start + prefix.items.len())
                .min(candidate.start + candidate.items.len());
            let prefix_slice = &prefix.items[index - prefix.start..end - prefix.start];
            let candidate_slice = &candidate.items[index - candidate.start..end - candidate.start];

            let chunks_are_shared = std::ptr::eq(prefix_slice.as_ptr(), candidate_slice.as_ptr());
            if !chunks_are_shared {
                let comparisons = end - index;
                if comparisons > comparison_budget {
                    return Err(ListAppendError::ComparisonBudgetExceeded);
                }
                comparison_budget -= comparisons;
                if !prefix_slice
                    .iter()
                    .zip(candidate_slice)
                    .all(|(a, b)| a.eq_exact(b))
                {
                    return Err(ListAppendError::PrefixMismatch);
                }
            }
            index = end;
        }

        Ok(candidate.slice(prefix_len, candidate.len()))
    }

    #[inline]
    pub fn into_vec(self) -> Vec<Var> {
        self.iter().collect()
    }

    /// This list with `value` added at the end.
    fn pushed(self, value: Var) -> Self {
        match self.into_owned() {
            Owned::Flat(mut block) if block.len() < FLAT_MAX => {
                block.push(value, FLAT_MAX);
                Self::from_block(block)
            }
            Owned::Flat(block) => {
                let mut tree = Tree::new();
                tree.extend_from_slice(block.as_slice());
                tree.push(value);
                Self::from_tree(Arc::new(tree))
            }
            Owned::Tree(mut tree) => {
                Arc::make_mut(&mut tree).push(value);
                Self::from_tree(tree)
            }
        }
    }

    /// The items before `index`, then `insert`, then the items from `index + skip` on.
    ///
    /// A long result is a new tree that shares this list's leaves on the longer side of the edit
    /// and copies the items on the shorter side.
    fn spliced(&self, index: usize, skip: usize, insert: Option<Var>) -> Self {
        let len = self.len();
        assert!(index + skip <= len, "list index out of bounds");
        let (before, after) = (index, len - index - skip);
        let inserted = usize::from(insert.is_some());
        if before + inserted + after <= FLAT_MAX {
            let before = self.iter_ref().take(index).cloned();
            let after = self.iter_ref().skip(index + skip).cloned();
            return before.chain(insert).chain(after).collect();
        }
        // Item `i` of this list is in slot `first_slot + i`. Start the new tree at the slot that
        // keeps the longer side in slots congruent to its own.
        let first_slot = if !self.is_tree() {
            0
        } else if before >= after {
            self.first_slot()
        } else {
            self.first_slot() + skip + LEAF_WIDTH - inserted
        };
        let mut tree = Tree::with_padding(first_slot & LEAF_MASK);
        tree.extend_from(|index| self.chunk_at(index), 0, index);
        if let Some(value) = insert {
            tree.push(value);
        }
        tree.extend_from(|index| self.chunk_at(index), index + skip, len);
        Self::from_tree(Arc::new(tree))
    }

    /// This list with `value` inserted before `index`.
    fn inserted(self, index: usize, value: Var) -> Self {
        let len = self.len();
        assert!(index <= len, "list index out of bounds");
        if index == len {
            return self.pushed(value);
        }
        match self.into_owned() {
            Owned::Flat(mut block) if block.len() < FLAT_MAX => {
                block.insert(index, value, FLAT_MAX);
                Self::from_block(block)
            }
            Owned::Flat(block) => Self::from_block(block).spliced(index, 0, Some(value)),
            Owned::Tree(tree) => Self::from_tree(tree).spliced(index, 0, Some(value)),
        }
    }

    /// This list without the item at `index`.
    fn removed(self, index: usize) -> Self {
        let len = self.len();
        assert!(index < len, "list index out of bounds");
        match self.into_owned() {
            Owned::Flat(mut block) => {
                block.remove(index);
                Self::from_block(block)
            }
            Owned::Tree(mut tree) if index == 0 => {
                Arc::make_mut(&mut tree).drop_front(1);
                Self::from_edited_tree(tree)
            }
            Owned::Tree(mut tree) if index == len - 1 => {
                Arc::make_mut(&mut tree).truncate(len - 1);
                Self::from_edited_tree(tree)
            }
            Owned::Tree(tree) => Self::from_tree(tree).spliced(index, 1, None),
        }
    }

    /// This list with the item at `index` replaced.
    fn replaced(self, index: usize, value: Var) -> Self {
        match self.into_owned() {
            Owned::Flat(mut block) => {
                block.as_mut_slice()[index] = value;
                Self::from_block(block)
            }
            Owned::Tree(mut tree) => {
                Arc::make_mut(&mut tree).set(index, value);
                Self::from_tree(tree)
            }
        }
    }

    /// The items from index `from` up to `to`. A long slice of a long list shares its leaves.
    fn slice(&self, from: usize, to: usize) -> Self {
        assert!(from <= to && to <= self.len(), "list range out of bounds");
        let len = to - from;
        if len <= FLAT_MAX || !self.is_tree() {
            return self.iter_ref().skip(from).take(len).cloned().collect();
        }
        // Cutting the end off a copy of the tree costs a step per leaf cut. Building a tree from
        // the wanted leaves costs a step per leaf kept. Take the cheaper.
        if self.len() - to > len {
            let mut tree = Tree::with_padding((self.first_slot() + from) & LEAF_MASK);
            tree.extend_from(|index| self.chunk_at(index), from, to);
            return Self::from_tree(Arc::new(tree));
        }
        let Owned::Tree(mut tree) = self.clone().into_owned() else {
            unreachable!("checked above");
        };
        let edit = Arc::make_mut(&mut tree);
        edit.truncate(to);
        edit.drop_front(from);
        Self::from_tree(tree)
    }

    /// This list followed by the items of `other`.
    ///
    /// A long list keeps its own leaves and takes copies of `other`'s items, so that the result
    /// is recognizably this list with a suffix; see `append_suffix`. A short list is copied onto
    /// the front of a long `other`, which keeps its leaves.
    fn appended(self, other: &Self) -> Self {
        let (len, other_len) = (self.len(), other.len());
        if other_len == 0 {
            return self;
        }
        if other.is_tree() && !self.is_tree() {
            // Start at the slot that puts `other`'s items in slots congruent to their own.
            let first_slot = other.first_slot() + LEAF_WIDTH - (len & LEAF_MASK);
            let mut tree = Tree::with_padding(first_slot & LEAF_MASK);
            tree.extend_from(|index| self.chunk_at(index), 0, len);
            tree.extend_from(|index| other.chunk_at(index), 0, other_len);
            return Self::from_tree(Arc::new(tree));
        }
        match self.into_owned() {
            Owned::Flat(mut block) if len + other_len <= FLAT_MAX && !other.is_tree() => {
                block.extend_from_slice(other.chunk_at(0).items, FLAT_MAX);
                Self::from_block(block)
            }
            Owned::Flat(block) => {
                let mut tree = Tree::new();
                tree.extend_from_slice(block.as_slice());
                tree.extend_from(|index| other.chunk_at(index), 0, other_len);
                Self::from_tree(Arc::new(tree))
            }
            Owned::Tree(mut tree) => {
                Arc::make_mut(&mut tree).extend_from(|index| other.chunk_at(index), 0, other_len);
                Self::from_tree(tree)
            }
        }
    }

    #[inline]
    pub fn push_owned(self, value: &Var) -> Var {
        Var::from_list_with_hint(self.pushed(value.clone()), OP_HINT_LIST_APPEND)
    }

    /// Insert `value` before `index`, which must not be past the end.
    #[inline]
    pub fn insert_owned(self, index: usize, value: &Var) -> Var {
        Var::from_list(self.inserted(index, value.clone()))
    }

    pub fn index_set_owned(self, index: usize, value: &Var) -> Result<Var, Error> {
        if index >= self.len() {
            return Err(E_RANGE.with_msg(|| {
                format!(
                    "attempt to set index {} in list of length {}",
                    index + 1,
                    self.len()
                )
            }));
        }

        Ok(Var::from_list(self.replaced(index, value.clone())))
    }

    pub fn append_owned(self, other: &Var) -> Result<Var, Error> {
        let Some(other) = other.as_list() else {
            return Err(E_TYPE.msg("attempt to append non-list"));
        };
        Ok(Var::from_list_with_hint(
            self.appended(other),
            OP_HINT_LIST_APPEND,
        ))
    }

    pub fn remove_at_owned(self, index: usize) -> Result<Var, Error> {
        if index >= self.len() {
            return Err(E_RANGE.with_msg(|| {
                format!(
                    "attempt to remove index {} in list of length {}",
                    index + 1,
                    self.len()
                )
            }));
        }

        Ok(Var::from_list(self.removed(index)))
    }

    pub fn range_set_owned(self, from: isize, to: isize, with: &Var) -> Result<Var, Error> {
        let Some(with_val) = with.as_list() else {
            return Err(E_TYPE.msg("attempt to set range with non-list"));
        };

        let base_len = self.len();
        if from < 0 {
            return Err(
                E_RANGE.with_msg(|| format!("attempt to set range with negative index {from}"))
            );
        }

        // 1..0 is a "special" MOO-ism for front insertion.
        if from == 0 && to == -1 {
            return Ok(Var::from_list(with_val.clone().appended(&self)));
        }

        let from = usize::try_from(from).unwrap_or(0);
        let to = usize::try_from(to).unwrap_or(0);

        if from > base_len + 1 {
            return Err(E_RANGE.with_msg(|| {
                format!(
                    "attempt to set range with index {} in list of length {base_len}",
                    from + 1
                )
            }));
        }

        let to = if base_len == 0 {
            0
        } else if to + 1 > base_len {
            base_len - 1
        } else {
            to
        };

        // Replacing one item keeps the rest of the list, as an indexed set does. A one-item input
        // must have its own case, since `to == from` alone also covers removing one item.
        if from == to && from < base_len && with_val.len() == 1 {
            return Ok(Var::from_list(self.replaced(from, with_val[0].clone())));
        }

        let kept_from = min(to + 1, base_len);
        Ok(Var::from_list(
            self.spliced_range(from, kept_from, with_val),
        ))
    }

    /// This list with the items from `from` up to `to` replaced by those of `with`, where `to` is
    /// the `to` of `range_set_owned` plus one.
    ///
    /// Bounds are already checked, so the prefix and the suffix can be empty. `from` can be
    /// `base_len + 1`, which appends to the end. The items from `kept_from` on are the suffix,
    /// which is what follows the replaced items unless the bounds are reversed. A reversed pair,
    /// as in a one-based `[4..1]`, has `to <= from`; the result then keeps the prefix before `from`
    /// and the suffix after `to`, and the items between the bounds appear twice.
    fn spliced_range(self, from: usize, kept_from: usize, with: &Self) -> Self {
        let (len, with_len) = (self.len(), with.len());
        let before = min(from, len);
        let after = len - kept_from;
        if before + with_len + after <= FLAT_MAX {
            let before = self.iter_ref().take(before).cloned();
            let after = self.iter_ref().skip(kept_from).cloned();
            return before
                .chain(with.iter_ref().cloned())
                .chain(after)
                .collect();
        }
        // Read the kept items through `chunk_at`, which shares a full leaf that lands on a leaf
        // boundary. Start the new tree at the slot that keeps the longer side in slots congruent
        // to its own. On the prefix side that is this list's own start. On the suffix side item
        // `i` of the source lands at slot `self.first_slot() + kept_from + i`, so item `i` of the
        // result keeps its slot when the suffix starts at slot `padding + before + with_len`.
        let pad = if before >= after {
            self.first_slot() & LEAF_MASK
        } else {
            let source_slot = (self.first_slot() + kept_from) as isize;
            let dest_slot = (before + with_len) as isize;
            (source_slot - dest_slot).rem_euclid(LEAF_WIDTH as isize) as usize
        };
        let mut tree = Tree::with_padding(pad);
        // A reversed pair keeps nothing between the bounds, so `from` and `kept_from` only select
        // the two sides.
        tree.extend_from(|index| self.chunk_at(index), 0, before);
        tree.extend_from(|index| with.chunk_at(index), 0, with_len);
        tree.extend_from(|index| self.chunk_at(index), kept_from, len);
        debug_assert_eq!(tree.len(), before + with_len + after);
        Self::from_edited_tree(Arc::new(tree))
    }

    /// Remove the first found instance of `item` from the list.
    pub fn set_remove(&self, item: &Var) -> Result<Var, Error> {
        let result = match self.iter_ref().position(|v| *v == *item) {
            Some(index) => self.clone().removed(index),
            None => self.clone(),
        };
        Ok(Var::from_list(result))
    }

    /// Add `item` to the list but only if it's not already there.
    pub fn set_add(&self, item: &Var) -> Result<Var, Error> {
        // Is the item already in the list? If so, just clone self
        if self.iter_ref().any(|v| v == item) {
            return Ok(Var::from_list(self.clone()));
        }
        Ok(Var::from_list(self.clone().pushed(item.clone())))
    }

    pub fn pop_front(&self) -> Result<(Var, Var), Error> {
        if self.is_empty() {
            return Err(E_RANGE.msg("attempt to pop from empty list"));
        }
        let first = self.get(0).clone();
        Ok((first, Var::from_list(self.clone().removed(0))))
    }
}

/// The items of a list, in order.
#[derive(Clone)]
pub struct Iter<'a> {
    /// What is left of the block being read.
    current: std::slice::Iter<'a, Var>,
    tree: Option<&'a Tree>,
    /// The index of the first item after `current`'s block.
    next_chunk: usize,
    remaining: usize,
}

impl<'a> Iter<'a> {
    /// Start reading the block that holds the item at `index`, from that item.
    fn seek(&mut self, tree: &'a Tree, index: usize) {
        let chunk = tree.chunk_at(index);
        self.current = chunk.items[index - chunk.start..].iter();
        self.next_chunk = chunk.start + chunk.items.len();
    }
}

impl<'a> Iterator for Iter<'a> {
    type Item = &'a Var;

    #[inline]
    fn next(&mut self) -> Option<&'a Var> {
        if let Some(value) = self.current.next() {
            self.remaining -= 1;
            return Some(value);
        }
        if self.remaining == 0 {
            return None;
        }
        let tree = self.tree?;
        self.seek(tree, self.next_chunk);
        self.remaining -= 1;
        self.current.next()
    }

    fn nth(&mut self, n: usize) -> Option<&'a Var> {
        if n >= self.remaining {
            self.current = [].iter();
            self.remaining = 0;
            return None;
        }
        if n >= self.current.len()
            && let Some(tree) = self.tree
        {
            self.seek(tree, tree.len() - self.remaining + n);
            self.remaining -= n + 1;
            return self.current.next();
        }
        self.remaining -= n + 1;
        self.current.nth(n)
    }

    #[inline]
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}

impl ExactSizeIterator for Iter<'_> {}

impl Debug for List {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_list().entries(self.iter_ref()).finish()
    }
}
impl Sequence for List {
    fn is_empty(&self) -> bool {
        List::is_empty(self)
    }

    fn len(&self) -> usize {
        List::len(self)
    }

    fn index_in(&self, value: &Var, case_sensitive: bool) -> Result<Option<usize>, Error> {
        for (i, v) in self.iter_ref().enumerate() {
            if case_sensitive {
                if v.eq_case_sensitive(value) {
                    return Ok(Some(i));
                }
            } else if v == value {
                return Ok(Some(i));
            }
        }
        Ok(None)
    }
    fn contains(&self, value: &Var, case_sensitive: bool) -> Result<bool, Error> {
        for v in self.iter_ref() {
            if case_sensitive {
                if v.eq_case_sensitive(value) {
                    return Ok(true);
                }
            } else if v == value {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn index(&self, index: usize) -> Result<Var, Error> {
        if index >= self.len() {
            return Err(E_RANGE.with_msg(|| {
                format!(
                    "attempt to index {} in list of length {}",
                    // We adjust this for 1-indexing because we don't actually know the indexing mode and 1 is our most common.
                    // Here and below.
                    index + 1,
                    self.len()
                )
            }));
        }
        Ok(self.get(index).clone())
    }

    fn index_set(&self, index: usize, value: &Var) -> Result<Var, Error> {
        self.clone().index_set_owned(index, value)
    }

    fn push(&self, value: &Var) -> Result<Var, Error> {
        Ok(self.clone().push_owned(value))
    }

    fn insert(&self, index: usize, value: &Var) -> Result<Var, Error> {
        let index = min(index, self.len());
        Ok(self.clone().insert_owned(index, value))
    }

    fn range(&self, from: isize, to: isize) -> Result<Var, Error> {
        let len = self.len() as isize;
        if to < from {
            return Ok(Var::mk_list(&[]));
        }
        if from > len + 1 || to > len {
            return Err(E_RANGE.with_msg(|| {
                let (from, to) = (from + 1, to + 1);
                format!(
                    "attempt to access out of bounds range {from}..{to} in list of length {len}"
                )
            }));
        }
        let end = min(to as usize + 1, self.len());
        let from = min(max(from, 0) as usize, end);
        Ok(Var::from_list(self.slice(from, end)))
    }

    fn range_set(&self, from: isize, to: isize, with: &Var) -> Result<Var, Error> {
        self.clone().range_set_owned(from, to, with)
    }

    fn append(&self, other: &Var) -> Result<Var, Error> {
        self.clone().append_owned(other)
    }

    fn remove_at(&self, index: usize) -> Result<Var, Error> {
        self.clone().remove_at_owned(index)
    }
}

impl From<List> for Var {
    fn from(val: List) -> Self {
        Var::from_list(val)
    }
}

impl Index<usize> for List {
    type Output = Var;

    fn index(&self, index: usize) -> &Self::Output {
        assert!(index < self.len(), "list index out of bounds");
        self.get(index)
    }
}
impl PartialEq for List {
    fn eq(&self, other: &Self) -> bool {
        if self.0.ptr_eq(&other.0) {
            return true;
        }
        if self.len() != other.len() {
            return false;
        }

        for (a, b) in self.iter_ref().zip(other.iter_ref()) {
            if a != b {
                return false;
            }
        }

        true
    }
}

impl Eq for List {}

impl PartialOrd for List {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for List {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        if self.len() != other.len() {
            return self.len().cmp(&other.len());
        }

        for (a, b) in self.iter_ref().zip(other.iter_ref()) {
            match a.cmp(b) {
                std::cmp::Ordering::Equal => continue,
                x => return x,
            }
        }

        std::cmp::Ordering::Equal
    }
}

impl Hash for List {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        for item in self.iter_ref() {
            item.hash(state);
        }
    }
}

impl FromIterator<Var> for Var {
    fn from_iter<T: IntoIterator<Item = Var>>(iter: T) -> Self {
        Var::from_list(List::from_iter(iter))
    }
}

impl std::iter::FromIterator<Var> for List {
    fn from_iter<T: IntoIterator<Item = Var>>(iter: T) -> Self {
        let mut iter = iter.into_iter();
        let mut block = Block::with_capacity(iter.size_hint().0.min(FLAT_MAX));
        while block.len() < FLAT_MAX {
            let Some(value) = iter.next() else {
                return List::from_block(block);
            };
            if block.len() == block.capacity() {
                block.reserve_one(FLAT_MAX);
            }
            // SAFETY: the block is new, so unshared, and has spare capacity.
            unsafe { block.push_unchecked(value) };
        }
        let mut list = List::from_block(block);
        for value in iter {
            list = list.pushed(value);
        }
        list
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        Error, IndexMode, List, ListAppendError, Sequence,
        error::ErrorCode::{E_RANGE, E_TYPE},
        v_bool_int,
        variant::Variant,
        variant::{Var, v_empty_list, v_int, v_list, v_str},
    };

    #[test]
    fn test_list_pack_unpack_index() {
        let l = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);

        match l.variant() {
            Variant::List(l) => {
                assert_eq!(l.len(), 3);
            }
            _ => panic!("Expected list, got {:?}", l.variant()),
        }
        eprintln!("List: {:?}", l.variant());
        let r = l.index(&Var::mk_integer(1), IndexMode::ZeroBased).unwrap();
        let r = r.variant();
        match r {
            Variant::Int(i) => assert_eq!(i, 2),
            _ => panic!("Expected integer, got {r:?}"),
        }
    }

    #[test]
    fn test_list_equality_inequality() {
        let l1 = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);
        let l2 = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);
        let l3 = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(4)]);
        let l4 = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2)]);
        let l5 = Var::mk_list(&[
            Var::mk_integer(1),
            Var::mk_integer(2),
            Var::mk_integer(3),
            Var::mk_integer(4),
        ]);

        assert_eq!(l1, l2);
        assert_ne!(l1, l3);
        assert_ne!(l1, l4);
        assert_ne!(l1, l5);
    }

    #[test]
    fn append_suffix_uses_shared_chunks() {
        let base = (0..4096).map(Var::mk_integer).collect::<List>();
        let candidate = base.clone().push_owned(&Var::mk_integer(4096));
        let candidate = candidate.as_list().unwrap();

        let suffix = base.append_suffix(candidate, 128).unwrap();

        assert_eq!(suffix.len(), 1);
        assert_eq!(suffix[0], Var::mk_integer(4096));
    }

    #[test]
    fn append_suffix_uses_shared_chunks_for_small_list_append() {
        let base = (0..4096).map(Var::mk_integer).collect::<List>();
        let suffix = (4096..4100).map(Var::mk_integer).collect::<List>();
        let candidate = base.clone().append_owned(&Var::from(suffix)).unwrap();
        let candidate = candidate.as_list().unwrap();

        let suffix = base.append_suffix(candidate, 128).unwrap();

        assert_eq!(suffix.len(), 4);
        assert_eq!(suffix[0], Var::mk_integer(4096));
        assert_eq!(suffix[3], Var::mk_integer(4099));
    }

    #[test]
    fn append_suffix_accepts_small_independent_lists() {
        let base = (0..8).map(Var::mk_integer).collect::<List>();
        let candidate = (0..9).map(Var::mk_integer).collect::<List>();

        let suffix = base.append_suffix(&candidate, 8).unwrap();

        assert_eq!(suffix.len(), 1);
        assert_eq!(suffix[0], Var::mk_integer(8));
    }

    #[test]
    fn append_suffix_rejects_changed_prefix() {
        let base = (0..8).map(Var::mk_integer).collect::<List>();
        let mut values = (0..9).map(Var::mk_integer).collect::<Vec<_>>();
        values[4] = Var::mk_integer(99);
        let candidate = values.into_iter().collect::<List>();

        assert_eq!(
            base.append_suffix(&candidate, 8),
            Err(ListAppendError::PrefixMismatch)
        );
    }

    #[test]
    fn append_suffix_rejects_case_only_prefix_change() {
        let base = List::mk_list(&[v_str("Ada")]);
        let edited = base.clone().replaced(0, v_str("ADA")).pushed(v_int(7));

        assert_eq!(
            base.append_suffix(&edited, 8),
            Err(ListAppendError::PrefixMismatch)
        );

        let exact = List::mk_list(&[v_str("Ada"), v_int(7)]);
        assert_eq!(
            base.append_suffix(&exact, 8),
            Ok(List::mk_list(&[v_int(7)]))
        );
    }

    #[test]
    fn append_suffix_bounds_independent_prefix_work() {
        let base = (0..4096).map(Var::mk_integer).collect::<List>();
        let candidate = (0..4097).map(Var::mk_integer).collect::<List>();

        assert_eq!(
            base.append_suffix(&candidate, 128),
            Err(ListAppendError::ComparisonBudgetExceeded)
        );
    }

    #[test]
    fn test_list_is_funcs() {
        let l = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);
        assert!(l.is_true());
        assert!(l.is_sequence());
        assert!(!l.is_associative());
        assert!(!l.is_scalar());
        assert_eq!(l.len().unwrap(), 3);
        assert!(!l.is_empty().unwrap());

        let l = Var::mk_list(&[]);
        assert!(!l.is_true());
        assert!(l.is_sequence());
        assert!(!l.is_associative());
        assert!(!l.is_scalar());
        assert_eq!(l.len().unwrap(), 0);
        assert!(l.is_empty().unwrap());
    }

    #[test]
    fn test_list_index_set() {
        let l = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);
        let r = l
            .index_set(
                &Var::mk_integer(1),
                &Var::mk_integer(42),
                IndexMode::ZeroBased,
            )
            .unwrap();
        let r = r.variant();
        match r {
            Variant::List(l) => {
                let r = l.index(1).unwrap();
                let r = r.variant();
                match r {
                    Variant::Int(i) => assert_eq!(i, 42),
                    _ => panic!("Expected integer, got {r:?}"),
                }
            }
            _ => panic!("Expected list, got {r:?}"),
        }

        let fail_bad_index = l.index_set(
            &Var::mk_integer(10),
            &Var::mk_integer(42),
            IndexMode::ZeroBased,
        );
        assert!(fail_bad_index.is_err());
        assert_eq!(fail_bad_index.unwrap_err(), E_RANGE);
    }

    #[test]
    fn test_list_set_remove() {
        let l = Var::mk_list(&[
            Var::mk_integer(1),
            Var::mk_integer(2),
            Var::mk_integer(3),
            Var::mk_integer(2),
        ]);
        // Only works on list variants.
        let l = match l.variant() {
            Variant::List(l) => l,
            _ => panic!("Expected list"),
        };
        // This will only remove the first instance of 2...
        let removed = l.set_remove(&Var::mk_integer(2)).unwrap();
        let removed_v = match removed.variant() {
            Variant::List(l) => l,
            _ => panic!("Expected list"),
        };
        // should now b e [1, 3, 2]
        assert_eq!(removed_v.len(), 3);
        assert_eq!(
            removed,
            Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(3), Var::mk_integer(2)])
        );
    }

    #[test]
    fn test_list_set_add() {
        let l = Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)]);
        // Only works on list variants.
        let l = match l.variant() {
            Variant::List(l) => l.clone(),
            _ => panic!("Expected list"),
        };
        // This will only add the first instance of 2...
        let added = l.set_add(&Var::mk_integer(2)).unwrap();
        let added_v = match added.variant() {
            Variant::List(l) => l.clone(),
            _ => panic!("Expected list"),
        };
        // should still be [1, 2, 3]
        assert_eq!(added_v.len(), 3);
        assert_eq!(
            added,
            Var::mk_list(&[Var::mk_integer(1), Var::mk_integer(2), Var::mk_integer(3)])
        );

        // now add 4
        let added = l.clone().set_add(&Var::mk_integer(4)).unwrap();
        let added_v = match added.variant() {
            Variant::List(l) => l,
            _ => panic!("Expected list"),
        };
        // should now be [1, 2, 3, 4]
        assert_eq!(added_v.len(), 4);
        assert_eq!(
            added,
            Var::mk_list(&[
                Var::mk_integer(1),
                Var::mk_integer(2),
                Var::mk_integer(3),
                Var::mk_integer(4)
            ])
        );
    }

    #[test]
    fn test_owned_list_ops() {
        let base = List::mk_list(&[v_int(1), v_int(2), v_int(3)]);

        let pushed = base.clone().push_owned(&v_int(4));
        assert_eq!(pushed, v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]));

        let inserted = base.clone().insert_owned(1, &v_int(99));
        assert_eq!(inserted, v_list(&[v_int(1), v_int(99), v_int(2), v_int(3)]));

        let removed = base.clone().remove_at_owned(1).unwrap();
        assert_eq!(removed, v_list(&[v_int(1), v_int(3)]));

        let appended = base
            .clone()
            .append_owned(&v_list(&[v_int(8), v_int(9)]))
            .unwrap();
        assert_eq!(
            appended,
            v_list(&[v_int(1), v_int(2), v_int(3), v_int(8), v_int(9)])
        );
    }

    #[test]
    fn test_list_range() -> Result<(), Error> {
        // test on integer list
        let int_list = v_list(&[1.into(), 2.into(), 3.into(), 4.into(), 5.into()]);
        assert_eq!(
            int_list.range(&v_int(2), &v_int(4), IndexMode::ZeroBased)?,
            v_list(&[3.into(), 4.into(), 5.into()])
        );

        let int_list = v_list(&[1.into(), 2.into(), 3.into(), 4.into(), 5.into()]);
        assert_eq!(
            int_list.range(&v_int(3), &v_int(5), IndexMode::OneBased)?,
            v_list(&[3.into(), 4.into(), 5.into()])
        );

        // range with upper higher than lower, moo returns empty list for this (!)
        let empty_list = v_empty_list();
        assert_eq!(
            empty_list.range(&v_int(1), &v_int(0), IndexMode::ZeroBased),
            Ok(v_empty_list())
        );
        // test on out of range
        let int_list = v_list(&[1.into(), 2.into(), 3.into()]);
        assert_eq!(
            int_list.range(&v_int(2), &v_int(4), IndexMode::ZeroBased),
            Err(E_RANGE.into())
        );
        // test on type mismatch
        let var_int = v_int(10);
        assert_eq!(
            var_int.range(&v_int(1), &v_int(5), IndexMode::ZeroBased),
            Err(E_TYPE.into())
        );

        let list = v_list(&[v_int(0), v_int(0)]);
        assert_eq!(
            list.range(&v_int(1), &v_int(2), IndexMode::OneBased)?,
            v_list(&[v_int(0), v_int(0)])
        );
        Ok(())
    }

    #[test]
    fn test_list_range_set() {
        let base = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]);

        // {1,2,3,4}[1..2] = {"a", "b", "c"} => {1, "a", "b", "c", 4}
        let value = v_list(&[v_str("a"), v_str("b"), v_str("c")]);
        let expected = v_list(&[v_int(1), v_str("a"), v_str("b"), v_str("c"), v_int(4)]);
        let result = base.range_set(&v_int(2), &v_int(3), &value, IndexMode::OneBased);
        assert_eq!(result, Ok(expected));

        // {1,2,3,4}[1..2] = {"a"} => {1, "a", 4}
        let value = v_list(&[v_str("a")]);
        let expected = v_list(&[v_int(1), v_str("a"), v_int(4)]);
        let result = base.range_set(&v_int(2), &v_int(3), &value, IndexMode::OneBased);
        assert_eq!(result, Ok(expected));

        // {1,2,3,4}[1..2] = {} => {1,4}
        let value = v_empty_list();
        let expected = v_list(&[v_int(1), v_int(4)]);
        let result = base.range_set(&v_int(2), &v_int(3), &value, IndexMode::OneBased);
        assert_eq!(result, Ok(expected));

        // {1,2,3,4}[1..2] = {"a", "b"} => {1, "a", "b", 4}
        let value = v_list(&[v_str("a"), v_str("b")]);
        let expected = v_list(&[v_int(1), v_str("a"), v_str("b"), v_int(4)]);
        let result = base.range_set(&v_int(2), &v_int(3), &value, IndexMode::OneBased);
        assert_eq!(result, Ok(expected));
    }

    #[test]
    fn test_list_range_set2() {
        let base = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]);
        let with_val = v_list(&[v_int(3), v_int(4)]);
        let expected = v_list(&[v_int(3), v_int(4), v_int(3), v_int(4)]);
        let result = base.range_set(&v_int(1), &v_int(2), &with_val, IndexMode::OneBased);
        assert_eq!(result, Ok(expected));
    }

    #[test]
    fn test_list_push() {
        let l = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let r = l.push(&v_int(4)).unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]));
    }

    #[test]
    fn test_list_append() {
        let l1 = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let l2 = v_list(&[v_int(4), v_int(5), v_int(6)]);
        let l3 = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4), v_int(5), v_int(6)]);
        assert_eq!(l1.append(&l2), Ok(l3));
    }

    #[test]
    fn test_list_remove_at() {
        let l = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]);
        let r = l.remove_at(&v_int(1), IndexMode::ZeroBased).unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(3), v_int(4)]));
    }

    #[test]
    fn test_list_contains() {
        // Case sensitive and case-insensitive tests
        let l = v_list(&[v_str("a"), v_str("b"), v_str("c")]);
        assert_eq!(l.contains(&v_str("a"), true), Ok(v_bool_int(true)));
        assert_eq!(l.contains(&v_str("A"), false), Ok(v_bool_int(true)));
        assert_eq!(l.contains(&v_str("A"), true), Ok(v_bool_int(false)));
    }

    #[test]
    fn test_index_in() {
        let l = v_list(&[v_str("a"), v_str("b"), v_str("c")]);
        assert_eq!(
            l.index_in(&v_str("a"), false, IndexMode::OneBased).unwrap(),
            v_int(1)
        );
        assert_eq!(
            l.index_in(&v_str("A"), false, IndexMode::OneBased).unwrap(),
            v_int(1)
        );
        assert_eq!(
            l.index_in(&v_str("A"), true, IndexMode::OneBased).unwrap(),
            v_int(0)
        );

        assert_eq!(
            l.index_in(&v_str("A"), true, IndexMode::ZeroBased).unwrap(),
            v_int(-1)
        );
    }

    #[test]
    fn test_list_case_sensitive_compare() {
        let a = v_list(&[v_str("a"), v_str("b"), v_str("c")]);
        let b = v_list(&[v_str("A"), v_str("B"), v_str("C")]);

        assert!(!a.eq_case_sensitive(&b));
        assert!(a == b);
    }

    #[test]
    fn test_list_insert() {
        let l = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let r = l.insert(&v_int(0), &v_int(0), IndexMode::OneBased).unwrap();
        assert_eq!(r, v_list(&[v_int(0), v_int(1), v_int(2), v_int(3)]));

        // Insert to the end
        let l = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let r = l.insert(&v_int(1), &v_int(1), IndexMode::OneBased).unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(1), v_int(2), v_int(3)]));

        // Out of range just goes to the end
        let l = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let r = l
            .insert(&v_int(10), &v_int(10), IndexMode::OneBased)
            .unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(2), v_int(3), v_int(10)]));
    }

    #[test]
    fn test_range_set() {
        // foo = {}; foo[1..2] = {1, 2, 3} => {1, 2, 3}
        let l = v_list(&[]);
        let r = l
            .range_set(
                &v_int(1),
                &v_int(2),
                &v_list(&[v_int(1), v_int(2), v_int(3)]),
                IndexMode::OneBased,
            )
            .unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(2), v_int(3)]));

        // foo = {1}; foo[1..5] = {1, 2, 3} => {1, 2, 3}
        let l = v_list(&[v_int(1)]);
        let r = l
            .range_set(
                &v_int(1),
                &v_int(5),
                &v_list(&[v_int(1), v_int(2), v_int(3)]),
                IndexMode::OneBased,
            )
            .unwrap();
        assert_eq!(r, v_list(&[v_int(1), v_int(2), v_int(3)]));

        // foo = {1}; foo[2..3] = {2, 3} => {1,2,3}}
        let l = v_list(&[v_int(1)]);
        let r = l.range_set(
            &v_int(2),
            &v_int(3),
            &v_list(&[v_int(2), v_int(3)]),
            IndexMode::OneBased,
        );
        assert_eq!(r, Ok(v_list(&[v_int(1), v_int(2), v_int(3)])));

        // ;;a = {""}; a[2..1] = {#1}; return a;
        // => {"", #1}
        let l = v_list(&[v_str("")]);
        let r = l
            .range_set(
                &v_int(2),
                &v_int(1),
                &v_list(&[v_int(1)]),
                IndexMode::OneBased,
            )
            .unwrap();
        assert_eq!(r, v_list(&[v_str(""), v_int(1)]));

        // a = {1,2,3}; a[6..7] = {6,7,8}; return a;  => E_RANGE
        let l = v_list(&[v_int(1), v_int(2), v_int(3)]);
        let r = l.range_set(
            &v_int(6),
            &v_int(7),
            &v_list(&[v_int(6), v_int(7), v_int(8)]),
            IndexMode::OneBased,
        );
        assert_eq!(r, Err(E_RANGE.into()));

        //;;a = {}; a[1..0] = {"test"}; return a;
        // => {"test"}
        let l = v_list(&[]);
        let r = l
            .range_set(
                &v_int(1),
                &v_int(0),
                &v_list(&[v_str("test")]),
                IndexMode::OneBased,
            )
            .unwrap();
        assert_eq!(r, v_list(&[v_str("test")]));

        // escapes = {".", "@abort"}; escapes[1..0] = {"?"}; return escapes;
        // => {"?", ".", "@abort"}
        let l = v_list(&[v_str("."), v_str("@abort")]);
        let r = l
            .range_set(
                &v_int(1),
                &v_int(0),
                &v_list(&[v_str("?")]),
                IndexMode::OneBased,
            )
            .unwrap();
        assert_eq!(r, v_list(&[v_str("?"), v_str("."), v_str("@abort")]));
    }

    #[test]
    fn test_range_set_with_reversed_bounds() {
        // a = {1,2,3,4}; a[4..1] = {9}; return a; => {1,2,3,9,2,3,4}
        //
        // The replacement keeps the prefix before the first bound and the suffix after the second,
        // so a reversed pair includes the items between them twice. The property test sorts its
        // endpoints and cannot see this.
        let base = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]);
        let expected = v_list(&[
            v_int(1),
            v_int(2),
            v_int(3),
            v_int(9),
            v_int(2),
            v_int(3),
            v_int(4),
        ]);
        assert_eq!(
            base.range_set(
                &v_int(4),
                &v_int(1),
                &v_list(&[v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(expected.clone())
        );
        assert_eq!(
            base.range_set_owned(
                &v_int(4),
                &v_int(1),
                &v_list(&[v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(expected)
        );
    }

    #[test]
    fn test_range_set_one_item_keeps_the_rest_of_the_list() {
        let base = v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]);
        let expected = v_list(&[v_int(1), v_int(9), v_int(3), v_int(4)]);
        assert_eq!(
            base.range_set(
                &v_int(2),
                &v_int(2),
                &v_list(&[v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(expected)
        );
        // The last item, and the range just past the end.
        assert_eq!(
            base.range_set(
                &v_int(4),
                &v_int(4),
                &v_list(&[v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(v_list(&[v_int(1), v_int(2), v_int(3), v_int(9)]))
        );
        assert_eq!(
            base.range_set(
                &v_int(5),
                &v_int(5),
                &v_list(&[v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(v_list(&[v_int(1), v_int(2), v_int(3), v_int(4), v_int(9)]))
        );
        // A one-item range set to nothing removes the item.
        assert_eq!(
            base.range_set(&v_int(2), &v_int(2), &v_empty_list(), IndexMode::OneBased),
            Ok(v_list(&[v_int(1), v_int(3), v_int(4)]))
        );
        // Two items are a general splice.
        assert_eq!(
            base.range_set(
                &v_int(2),
                &v_int(3),
                &v_list(&[v_int(8), v_int(9)]),
                IndexMode::OneBased
            ),
            Ok(v_list(&[v_int(1), v_int(8), v_int(9), v_int(4)]))
        );
        assert_eq!(base, v_list(&[v_int(1), v_int(2), v_int(3), v_int(4)]));
    }
}

/// Tests of the list's own structure: block growth, the tree, and sharing between copies.
#[cfg(test)]
mod structure_tests {
    use super::{FLAT_MAX, LEAF_WIDTH, List};

    /// The comparison budget the database gives `append_suffix`.
    const DATABASE_APPEND_BUDGET: usize = 128;
    use crate::{Sequence, Var, v_int};
    use proptest::prelude::*;

    fn ints(n: usize) -> List {
        (0..n as i64).map(v_int).collect()
    }

    fn list_of(var: &Var) -> List {
        var.as_list().expect("list").clone()
    }

    fn assert_matches(list: &List, model: &[i64]) {
        assert_eq!(list.len(), model.len());
        assert!(
            list.iter_ref()
                .map(|v| v.as_integer().unwrap())
                .eq(model.iter().copied())
        );
        assert_eq!(list.iter_ref().len(), model.len());
        for index in (0..model.len()).step_by(model.len() / 97 + 1) {
            assert_eq!(list[index], v_int(model[index]));
            // `nth` from the start and from part way through a block.
            assert_eq!(list.iter_ref().nth(index), Some(&v_int(model[index])));
            let mut iter = list.iter_ref();
            iter.next();
            assert_eq!(
                iter.nth(index).map(|v| v.as_integer().unwrap()),
                model.get(index + 1).copied()
            );
        }
        assert_eq!(list.iter_ref().nth(model.len()), None);
    }

    /// Lengths on both sides of each change of shape: empty, block growth, block to tree, a full
    /// tail, and a full root at one and two levels.
    const LENGTHS: [usize; 20] = [
        0,
        1,
        3,
        4,
        5,
        FLAT_MAX - 1,
        FLAT_MAX,
        FLAT_MAX + 1,
        3 * LEAF_WIDTH,
        3 * LEAF_WIDTH + 1,
        LEAF_WIDTH * LEAF_WIDTH,
        LEAF_WIDTH * LEAF_WIDTH + 1,
        LEAF_WIDTH * LEAF_WIDTH + LEAF_WIDTH,
        LEAF_WIDTH * LEAF_WIDTH + LEAF_WIDTH + 1,
        2 * LEAF_WIDTH * LEAF_WIDTH + 7,
        LEAF_WIDTH * LEAF_WIDTH * LEAF_WIDTH,
        LEAF_WIDTH * LEAF_WIDTH * LEAF_WIDTH + 1,
        LEAF_WIDTH * LEAF_WIDTH * LEAF_WIDTH + LEAF_WIDTH,
        LEAF_WIDTH * LEAF_WIDTH * LEAF_WIDTH + LEAF_WIDTH + 1,
        40_000,
    ];

    /// Miri is too slow for the three-level trees.
    fn lengths() -> impl Iterator<Item = usize> {
        let limit = if cfg!(miri) { 2100 } else { usize::MAX };
        LENGTHS.into_iter().filter(move |len| *len <= limit)
    }

    #[test]
    fn built_lists_hold_their_items_at_every_shape() {
        for len in lengths() {
            let model: Vec<i64> = (0..len as i64).collect();
            assert_matches(&ints(len), &model);
            let values: Vec<Var> = model.iter().copied().map(v_int).collect();
            assert_matches(&List::mk_list(&values), &model);
        }
    }

    #[test]
    fn pushing_one_at_a_time_matches_building_at_once() {
        let mut list = ints(0);
        let mut model = vec![];
        let lengths: Vec<usize> = lengths().collect();
        let mut next_check = 0;
        for i in 0..lengths[lengths.len() - 1].min(LENGTHS[LENGTHS.len() - 2]) as i64 + 2 {
            if lengths.get(next_check) == Some(&model.len()) {
                assert_matches(&list, &model);
                assert_eq!(list, ints(model.len()));
                next_check += 1;
            }
            list = list.pushed(v_int(i));
            model.push(i);
        }
    }

    #[test]
    fn edits_leave_other_copies_unchanged() {
        for len in lengths().filter(|len| *len > 0) {
            let original = ints(len);
            let model: Vec<i64> = (0..len as i64).collect();
            for index in [0, len / 2, len - 1] {
                let set = original.clone().replaced(index, v_int(-1));
                let mut expected = model.clone();
                expected[index] = -1;
                assert_matches(&set, &expected);

                let removed = original.clone().removed(index);
                let mut expected = model.clone();
                expected.remove(index);
                assert_matches(&removed, &expected);

                let inserted = original.clone().inserted(index, v_int(-2));
                let mut expected = model.clone();
                expected.insert(index, -2);
                assert_matches(&inserted, &expected);
            }
            let pushed = original.clone().pushed(v_int(-3));
            let mut expected = model.clone();
            expected.push(-3);
            assert_matches(&pushed, &expected);
            assert_matches(&original, &model);
        }
    }

    #[test]
    fn an_unshared_list_is_edited_where_it_is() {
        // Room for the push without growing, so the block must stay put.
        let list = ints(3).pushed(v_int(3)).removed(3);
        let before = list.get(0) as *const Var;
        let list = list.pushed(v_int(9));
        assert_eq!(list.get(0) as *const Var, before);
        let list = list.replaced(1, v_int(7));
        assert_eq!(list.get(0) as *const Var, before);
        assert_eq!(list, [0, 7, 2, 9].into_iter().map(v_int).collect());
    }

    #[test]
    fn a_long_list_shares_untouched_blocks_with_its_edit() {
        let original = ints(5000);
        let edited = original.clone().replaced(4000, v_int(-1));
        assert!(std::ptr::eq(original.get(10), edited.get(10)));
        assert!(std::ptr::eq(original.get(4999), edited.get(4999)));
        assert!(!std::ptr::eq(original.get(4000), edited.get(4000)));
        assert_eq!(original[4000], v_int(4000));
    }

    // Miri rejects `Var`'s storage of a list pointer as an integer, so it cannot run tests that
    // put a list in a `Var`.
    #[test]
    #[cfg_attr(miri, ignore)]
    fn nested_lists_are_released() {
        let inner = Var::from(ints(200));
        let outer: List = (0..300).map(|_| inner.clone()).collect();
        let copy = outer.clone();
        drop(outer);
        assert_eq!(copy[299], inner);
        drop(copy);
        // Only `inner` holds its list now, so a push goes into its tail where it is.
        let before = inner.as_list().unwrap().get(199) as *const Var;
        let pushed = inner.push_owned(&v_int(5)).unwrap();
        assert_eq!(pushed.as_list().unwrap().get(199) as *const Var, before);
    }

    #[test]
    #[should_panic(expected = "list index out of bounds")]
    fn inserting_past_the_end_of_a_long_list_panics() {
        ints(200).inserted(201, v_int(0));
    }

    #[test]
    #[should_panic(expected = "list index out of bounds")]
    fn inserting_past_the_end_of_a_short_list_panics() {
        ints(3).inserted(4, v_int(0));
    }

    #[test]
    fn a_long_list_drains_from_either_end() {
        let len = if cfg!(miri) { 700 } else { 5000 };
        let mut model: Vec<i64> = (0..len).collect();
        let (mut front, mut back) = (ints(model.len()), ints(model.len()));
        let original = front.clone();
        while !model.is_empty() {
            model.remove(0);
            front = front.removed(0);
            let last = back.len() - 1;
            back = back.removed(last);
            if model.len().is_multiple_of(97) {
                assert_matches(&front, &model);
                let kept: Vec<i64> = (0..model.len() as i64).collect();
                assert_matches(&back, &kept);
            }
        }
        assert_eq!(original.len(), len as usize);
        assert_eq!(original[len as usize - 1], v_int(len - 1));
    }

    #[test]
    fn edits_near_the_front_share_the_rest_of_a_long_list() {
        let original = ints(5000);
        let shared = |list: &List, index: usize, original_index: usize| {
            std::ptr::eq(list.get(index), original.get(original_index))
        };

        let prepended = ints(1).appended(&original);
        assert!(shared(&prepended, 4000, 3999));
        let inserted = original.clone().inserted(2, v_int(-1));
        assert!(shared(&inserted, 4000, 3999));
        let removed = original.clone().removed(2);
        assert!(shared(&removed, 4000, 4001));
        let dropped = original.clone().removed(0);
        assert!(shared(&dropped, 4000, 4001));
        let popped = original.clone().removed(4999);
        assert!(shared(&popped, 10, 10));
        let sliced = original.slice(100, 4900);
        assert!(shared(&sliced, 3000, 3100));
        // An edit to a list that no longer starts on a block boundary still lines up with it.
        let again = dropped.clone().inserted(1, v_int(-1));
        assert!(shared(&again, 4000, 4000));

        let mut model: Vec<i64> = (0..5000).collect();
        model.insert(0, 0);
        assert_matches(&prepended, &model);
        assert_matches(&sliced, &(100..4900).collect::<Vec<i64>>());
        assert_matches(&again, &{
            let mut model: Vec<i64> = (1..5000).collect();
            model.insert(1, -1);
            model
        });
        assert_matches(&original, &(0..5000).collect::<Vec<i64>>());
    }

    #[test]
    fn a_one_item_range_replacement_keeps_the_rest_of_a_long_list() {
        let original = ints(100_000);
        for index in [0, 1, LEAF_WIDTH, 50_000, 99_999] {
            let with = Var::from(List::mk_list(&[v_int(-1)]));
            let replaced = list_of(
                &Var::from(original.clone())
                    .range_set_owned(
                        &v_int(index as i64),
                        &v_int(index as i64),
                        &with,
                        crate::IndexMode::ZeroBased,
                    )
                    .unwrap(),
            );
            assert_eq!(replaced.len(), 100_000);
            assert_eq!(replaced[index], v_int(-1));
            assert_eq!(original[index], v_int(index as i64));
            // Items away from the edited block are the original storage. The block that holds the
            // edit is copied, so its other slots move with it.
            for other in [index.wrapping_sub(1), index + 1] {
                if other < 100_000 && other / LEAF_WIDTH != index / LEAF_WIDTH {
                    assert!(std::ptr::eq(replaced.get(other), original.get(other)));
                }
            }
            for other in [50_000, 99_999] {
                if other / LEAF_WIDTH != index / LEAF_WIDTH {
                    assert!(std::ptr::eq(replaced.get(other), original.get(other)));
                }
            }
        }
    }

    /// The items of `list` after `[from..to] = with`, and the model's.
    ///
    /// `range_set_owned` replaces up to and including `to`, and clamps it to the last item. When
    /// even the first index of the range is past the end, it still deletes the last item.
    fn assert_splice_matches(list: &List, model: &[i64], from: usize, to: usize, with: &[i64]) {
        let len = model.len();
        let to = if len == 0 {
            0
        } else if to >= len {
            len - 1
        } else {
            to
        };
        let expected: Vec<i64> = model[..from.min(len)]
            .iter()
            .copied()
            .chain(with.iter().copied())
            .chain(model[(to + 1).min(len)..].iter().copied())
            .collect();
        assert_matches(list, &expected);
    }

    #[test]
    fn a_range_splice_matches_a_vec_at_every_shape() {
        for len in LENGTHS {
            let base = ints(len);
            let model: Vec<i64> = (0..len as i64).collect();
            let mut edits: Vec<(usize, usize, Vec<i64>)> = Vec::new();
            for from in [
                0,
                1,
                LEAF_WIDTH - 1,
                LEAF_WIDTH,
                len / 2,
                len.saturating_sub(1),
            ] {
                for span in [0, 1, 2, LEAF_WIDTH] {
                    let to = from + span;
                    if from > len + 1 {
                        continue;
                    }
                    edits.push((from, to, vec![]));
                    edits.push((from, to, vec![1]));
                    edits.push((from, to, (0..33).map(|v| -(v as i64)).collect()));
                }
            }
            for (from, to, with) in edits {
                let with_list = List::mk_list(&with.iter().copied().map(v_int).collect::<Vec<_>>());
                let spliced = list_of(
                    &Var::from(base.clone())
                        .range_set_owned(
                            &v_int(from as i64),
                            &v_int(to as i64),
                            &Var::from(with_list),
                            crate::IndexMode::ZeroBased,
                        )
                        .unwrap(),
                );
                assert_splice_matches(&spliced, &model, from, to, &with);
                assert_matches(&base, &model);
            }
        }
    }

    #[test]
    fn a_range_splice_shares_the_longer_kept_side() {
        let original = ints(100_000);
        // A replacement of the same length keeps every kept item in its own slot, so both sides
        // of the edit stay aligned with the original's leaves.
        let same = List::mk_list(&[v_int(-1), v_int(-2)]);
        // A replacement of a different length shifts one side by the difference, so only the
        // other side keeps its slots.
        let longer = List::mk_list(&[v_int(-1), v_int(-2), v_int(-3), v_int(-4)]);

        let splice = |from: usize, to: usize, with: &List| {
            list_of(
                &Var::from(original.clone())
                    .range_set_owned(
                        &v_int(from as i64),
                        &v_int(to as i64),
                        &Var::from(with.clone()),
                        crate::IndexMode::ZeroBased,
                    )
                    .unwrap(),
            )
        };

        // An equal-length replacement in the middle. The suffix is the longer side and keeps
        // its blocks in place.
        let spliced = splice(40_000, 40_001, &same);
        assert_eq!(spliced.len(), 100_000);
        for start in (40_002..spliced.len() - LEAF_WIDTH).filter(|s| s % LEAF_WIDTH == 0) {
            for index in start..start + LEAF_WIDTH {
                assert!(std::ptr::eq(spliced.get(index), original.get(index)));
            }
        }

        // Growing the range by two shifts one side by two, so only the other keeps its slots.
        // The shorter prefix is copied and the longer suffix is shared, two items later.
        let spliced = splice(40_000, 40_001, &longer);
        assert_eq!(spliced.len(), 100_002);
        assert!(!std::ptr::eq(spliced.get(32_000), original.get(32_000)));
        assert!(std::ptr::eq(spliced.get(80_002), original.get(80_000)));
        // The replacement holds four items, so the suffix starts at 40,004.
        assert_eq!(spliced[40_004], original[40_002]);

        // A four-item range leaves the suffix the longer side, and it keeps its blocks in place.
        let spliced = splice(40_000, 40_003, &longer);
        assert_eq!(spliced.len(), 100_000);
        for start in (40_004..spliced.len() - LEAF_WIDTH).filter(|s| s % LEAF_WIDTH == 0) {
            for index in start..start + LEAF_WIDTH {
                assert!(std::ptr::eq(spliced.get(index), original.get(index)));
            }
        }

        // Replace a short late range, so the prefix is longer. The prefix keeps its storage,
        // except the last block, which the tree rewrites when it moves the full tail.
        for replaced in [2usize, 8] {
            let from = 60_000;
            let spliced = splice(from, from + replaced - 1, &same);
            assert_eq!(spliced.len(), 100_000 - replaced + 2);
            for start in (0..from).filter(|s| s % LEAF_WIDTH == 0) {
                for index in start..start + LEAF_WIDTH {
                    assert!(std::ptr::eq(spliced.get(index), original.get(index)));
                }
            }
        }

        // Remove a short early range. The suffix is longer, so the tree is aligned to it.
        let spliced = list_of(
            &Var::from(original.clone())
                .range_set_owned(
                    &v_int(40_000),
                    &v_int(40_003),
                    &Var::from(List::mk_list(&[])),
                    crate::IndexMode::ZeroBased,
                )
                .unwrap(),
        );
        assert_eq!(spliced.len(), 99_996);
        assert_eq!(spliced[40_000], original[40_004]);
        // The suffix keeps its blocks. The visible tail is not a whole block, so the block
        // before it is the one the tree rewrites when it moves the full tail into a leaf.
        let visible_tail = spliced.len() % LEAF_WIDTH;
        let last = (spliced.len() - visible_tail - LEAF_WIDTH) / LEAF_WIDTH * LEAF_WIDTH;
        let mut shared = 0;
        for start in (0..=last).filter(|s| s % LEAF_WIDTH == 0) {
            if (start..start + LEAF_WIDTH)
                .all(|i| std::ptr::eq(spliced.get(i), original.get(i + 4)))
            {
                shared += 1;
            }
        }
        assert_eq!(shared, last / LEAF_WIDTH - 40_032 / LEAF_WIDTH);
    }

    #[test]
    fn a_front_splice_matches_a_removal_and_shares_the_suffix() {
        let original = ints(100_000);
        let removed = list_of(
            &Var::from(original.clone())
                .remove_at_owned(&v_int(10), crate::IndexMode::ZeroBased)
                .unwrap(),
        );
        let spliced = list_of(
            &Var::from(original.clone())
                .range_set_owned(
                    &v_int(10),
                    &v_int(10),
                    &Var::from(List::mk_list(&[])),
                    crate::IndexMode::ZeroBased,
                )
                .unwrap(),
        );
        let model: Vec<i64> = (0..10).chain(11..100_000).collect();
        assert_matches(&spliced, &model);
        assert_eq!(spliced, removed);
        // The suffix is far more than the prefix, so it keeps its leaves, starting with the
        // block that holds the removed item.
        for start in [0, LEAF_WIDTH, 30_000, 60_000, 90_000] {
            let shared = (start..start + LEAF_WIDTH)
                .filter(|&index| {
                    let source = if index < 10 { index } else { index + 1 };
                    std::ptr::eq(spliced.get(index), original.get(source))
                })
                .count();
            let expected = if start == 0 { 1 } else { LEAF_WIDTH };
            assert_eq!(shared, expected, "block at {start}");
        }
    }

    #[test]
    fn a_reversed_range_keeps_both_sides_of_a_long_list() {
        let original = ints(100_000);
        let with = List::mk_list(&[v_int(-1)]);
        let spliced = list_of(
            &Var::from(original.clone())
                .range_set_owned(
                    &v_int(60_000),
                    &v_int(40_000),
                    &Var::from(with),
                    crate::IndexMode::ZeroBased,
                )
                .unwrap(),
        );
        let mut expected: Vec<i64> = (0..60_000).collect();
        expected.push(-1);
        expected.extend(40_001..100_000);
        assert_matches(&spliced, &expected);
        // The prefix is more than the suffix, so it keeps its leaves.
        assert!(std::ptr::eq(spliced.get(0), original.get(0)));
        // A short reversed pair follows the same rule.
        let short = list_of(
            &Var::from(ints(100))
                .range_set_owned(
                    &v_int(60),
                    &v_int(40),
                    &Var::from(List::mk_list(&[v_int(-1)])),
                    crate::IndexMode::ZeroBased,
                )
                .unwrap(),
        );
        let expected: Vec<i64> = (0..60).chain([-1]).chain(41..100).collect();
        assert_matches(&short, &expected);
    }

    #[test]
    fn a_short_slice_of_a_long_list_shares_its_leaves() {
        let original = ints(100_000);
        for (from, to) in [
            (0, 65),
            (1, 66),
            (50_000, 50_200),
            (99_900, 100_000),
            (7, 99_990),
        ] {
            let sliced = original.slice(from, to);
            assert_matches(&sliced, &(from as i64..to as i64).collect::<Vec<_>>());
            assert!(std::ptr::eq(sliced.get(40), original.get(from + 40)));
        }
    }

    #[test]
    fn shrinking_a_long_list_to_few_items_leaves_a_short_list() {
        let shrunk = list_of(
            &Var::from(ints(100_000))
                .range_set_owned(
                    &v_int(0),
                    &v_int(99_999),
                    &Var::from(List::mk_list(&[v_int(-1), v_int(-2)])),
                    crate::IndexMode::ZeroBased,
                )
                .unwrap(),
        );
        assert_matches(&shrunk, &[-1, -2]);
        // An ordinary short list, which shares the leaves of a long list it is appended to.
        let short = List::mk_list(&[v_int(-1), v_int(-2)]);
        let long = ints(100_000);
        let from_short = short.clone().appended(&long);
        let from_shrunk = shrunk.appended(&long);
        assert_eq!(from_shrunk, from_short);
        for index in [0, LEAF_WIDTH, 30_000, 60_000, 99_000] {
            assert!(std::ptr::eq(
                from_shrunk.get(index + 2),
                from_short.get(index + 2)
            ));
            assert!(std::ptr::eq(from_shrunk.get(index + 2), long.get(index)));
        }
    }

    #[test]
    fn appending_to_a_long_list_stays_within_the_database_budget() {
        for (len, added) in [(129, 258), (65, 4000), (5000, 1), (5000, 9000), (64, 300)] {
            let base = ints(len);
            let appended = base.clone().appended(&ints(added));
            let suffix = base.append_suffix(&appended, DATABASE_APPEND_BUDGET);
            assert_eq!(suffix, Ok(ints(added)), "{len} + {added}");
        }
    }

    // Through `Var`, so not under Miri; see `nested_lists_are_released`.
    #[test]
    #[cfg_attr(miri, ignore)]
    fn an_item_dropped_from_the_front_is_released_at_once() {
        // Whether `payload` is the only holder of its list shows in whether a push moves it.
        let is_unshared = |payload: Var| {
            let before = payload.as_list().unwrap().get(199) as *const Var;
            let pushed = payload.push_owned(&v_int(0)).unwrap();
            std::ptr::eq(pushed.as_list().unwrap().get(199), before)
        };
        for drop_from_a_shared_tree in [false, true] {
            let payload = Var::from(ints(200));
            let mut list: List = (0..1000).map(|_| payload.clone()).collect();
            list = list.replaced(0, Var::from(ints(200)));
            let first = list.get(0).clone();
            let other_copy = drop_from_a_shared_tree.then(|| list.clone());
            let rest = list.removed(0);
            drop(other_copy);
            assert_eq!(rest.len(), 999);
            assert!(is_unshared(first));
        }
    }

    #[derive(Clone, Debug)]
    enum Edit {
        Push(i64),
        Insert(usize, i64),
        Remove(usize),
        Set(usize, i64),
        Append(usize),
        Prepend(usize),
        Slice(usize, usize),
        Rebuild(usize),
        Range(usize, usize),
        RangeSet(usize, usize, usize),
        SetAdd(i64),
        SetRemove(i64),
        PopFront,
        KeepCopy,
    }

    fn edit() -> impl Strategy<Value = Edit> {
        let value = -5i64..5000;
        prop_oneof![
            4 => value.clone().prop_map(Edit::Push),
            2 => (any::<usize>(), value.clone()).prop_map(|(i, v)| Edit::Insert(i, v)),
            2 => any::<usize>().prop_map(Edit::Remove),
            2 => (any::<usize>(), value.clone()).prop_map(|(i, v)| Edit::Set(i, v)),
            2 => (0usize..150).prop_map(Edit::Append),
            1 => (0usize..150).prop_map(Edit::Prepend),
            2 => (any::<usize>(), any::<usize>()).prop_map(|(a, b)| Edit::Slice(a, b)),
            1 => (0usize..if cfg!(miri) { 300 } else { 2500 }).prop_map(Edit::Rebuild),
            1 => (any::<usize>(), any::<usize>()).prop_map(|(a, b)| Edit::Range(a, b)),
            1 => (any::<usize>(), any::<usize>(), 0usize..80)
                .prop_map(|(a, b, n)| Edit::RangeSet(a, b, n)),
            1 => value.clone().prop_map(Edit::SetAdd),
            1 => value.prop_map(Edit::SetRemove),
            1 => Just(Edit::PopFront),
            2 => Just(Edit::KeepCopy),
        ]
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(if cfg!(miri) { 4 } else { 200 }))]

        /// Any run of edits leaves the list equal to a `Vec` given the same edits, and leaves
        /// every earlier copy as it was.
        #[test]
        fn edits_match_a_vec(edits in prop::collection::vec(edit(), 1..60)) {
            let mut list = ints(0);
            let mut model: Vec<i64> = vec![];
            let mut copies: Vec<(List, Vec<i64>)> = vec![];
            for edit in edits {
                let len = model.len();
                // See `nested_lists_are_released` for why Miri skips these.
                let through_var = matches!(
                    edit,
                    Edit::Range(..) | Edit::RangeSet(..) | Edit::SetAdd(_) | Edit::SetRemove(_)
                );
                if cfg!(miri) && through_var {
                    continue;
                }
                match edit {
                    Edit::Push(v) => {
                        let base = list.clone();
                        list = list.pushed(v_int(v));
                        model.push(v);
                        let suffix = base.append_suffix(&list, DATABASE_APPEND_BUDGET).unwrap();
                        prop_assert_eq!(suffix.len(), 1);
                        prop_assert_eq!(&suffix[0], &v_int(v));
                    }
                    Edit::Insert(i, v) => {
                        let i = i % (len + 1);
                        list = list.inserted(i, v_int(v));
                        model.insert(i, v);
                    }
                    Edit::Remove(i) if len > 0 => {
                        list = list.removed(i % len);
                        model.remove(i % len);
                    }
                    Edit::Set(i, v) if len > 0 => {
                        list = list.replaced(i % len, v_int(v));
                        model[i % len] = v;
                    }
                    Edit::Append(n) => {
                        let base = list.clone();
                        list = list.appended(&ints(n));
                        model.extend(0..n as i64);
                        if n > 0 {
                            let suffix =
                                base.append_suffix(&list, DATABASE_APPEND_BUDGET).unwrap();
                            prop_assert_eq!(suffix, ints(n));
                        }
                    }
                    Edit::Prepend(n) => {
                        list = ints(n).appended(&list);
                        model.splice(0..0, 0..n as i64);
                    }
                    Edit::Slice(a, b) => {
                        let (a, b) = (a % (len + 1), b % (len + 1));
                        let (from, to) = (a.min(b), a.max(b));
                        list = list.slice(from, to);
                        model = model[from..to].to_vec();
                    }
                    Edit::Rebuild(n) => {
                        list = ints(n);
                        model = (0..n as i64).collect();
                    }
                    Edit::Range(a, b) if len > 0 => {
                        let (a, b) = (a % len, b % len);
                        let (from, to) = (a.min(b), a.max(b));
                        list = list_of(&list.range(from as isize, to as isize).unwrap());
                        model = model[from..=to].to_vec();
                    }
                    Edit::RangeSet(a, b, n) if len > 0 => {
                        let (a, b) = (a % len, b % len);
                        let (from, to) = (a.min(b), a.max(b));
                        let with = Var::from(ints(n));
                        list = list_of(
                            &list.range_set_owned(from as isize, to as isize, &with).unwrap(),
                        );
                        model.splice(from..=to, 0..n as i64);
                    }
                    Edit::SetAdd(v) => {
                        list = list_of(&list.set_add(&v_int(v)).unwrap());
                        if !model.contains(&v) {
                            model.push(v);
                        }
                    }
                    Edit::SetRemove(v) => {
                        list = list_of(&list.set_remove(&v_int(v)).unwrap());
                        if let Some(i) = model.iter().position(|x| *x == v) {
                            model.remove(i);
                        }
                    }
                    Edit::PopFront if len > 0 => {
                        prop_assert_eq!(list.get(0), &v_int(model.remove(0)));
                        list = list.removed(0);
                    }
                    Edit::KeepCopy => copies.push((list.clone(), model.clone())),
                    Edit::Remove(_)
                    | Edit::Set(..)
                    | Edit::Range(..)
                    | Edit::RangeSet(..)
                    | Edit::PopFront => {}
                }
                assert_matches(&list, &model);
            }
            for (copy, model) in &copies {
                assert_matches(copy, model);
            }
        }
    }
}
