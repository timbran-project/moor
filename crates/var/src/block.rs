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

//! Reference-counted storage shared by lists, maps and strings.
//!
//! [`Block`] is a buffer of items that is copied before it is changed if anything else holds it.
//! [`Shape`] is one pointer to either a block or a tree, which is what a list or a map is.

use std::{
    alloc::{self, Layout},
    marker::PhantomData,
    mem::ManuallyDrop,
    ptr::{self, NonNull},
    sync::atomic::{self, AtomicUsize, Ordering},
};
use triomphe::Arc;

/// The least capacity a block grows to when an item is added to it.
const MIN_GROWN_CAPACITY: usize = 4;

#[repr(C)]
struct BlockHeader {
    refs: AtomicUsize,
    len: u32,
    capacity: u32,
}

/// A reference-counted buffer of items: a header followed by room for `capacity` items, the first
/// `len` of which are initialized.
///
/// Cloning shares the buffer. Every method that changes the items first makes the handle the only
/// one to its buffer, copying the items if it was shared.
#[repr(transparent)]
pub(crate) struct Block<T>(NonNull<BlockHeader>, PhantomData<T>);

// SAFETY: a block owns its items and shares them only for reading, and its count is atomic.
unsafe impl<T: Send + Sync> Send for Block<T> {}
unsafe impl<T: Send + Sync> Sync for Block<T> {}

impl<T> Block<T> {
    /// Where the items start, after the header and any padding their alignment needs.
    const ITEMS_OFFSET: usize =
        (size_of::<BlockHeader>() + align_of::<T>() - 1) & !(align_of::<T>() - 1);

    fn layout(capacity: usize) -> Layout {
        let items = Layout::array::<T>(capacity).expect("block too large");
        let (layout, offset) = Layout::new::<BlockHeader>()
            .extend(items)
            .expect("block too large");
        debug_assert_eq!(offset, Self::ITEMS_OFFSET);
        layout.pad_to_align()
    }

    pub(crate) fn with_capacity(capacity: usize) -> Self {
        let layout = Self::layout(capacity);
        let header = BlockHeader {
            refs: AtomicUsize::new(1),
            len: 0,
            capacity: u32::try_from(capacity).expect("block too large"),
        };
        // SAFETY: the layout has the size of the header at least, so it is not zero-sized.
        let ptr = unsafe { alloc::alloc(layout) }.cast::<BlockHeader>();
        let Some(ptr) = NonNull::new(ptr) else {
            alloc::handle_alloc_error(layout)
        };
        // SAFETY: `ptr` is valid for a header and suitably aligned.
        unsafe { ptr.as_ptr().write(header) };
        Self(ptr, PhantomData)
    }

    #[inline]
    fn header(&self) -> &BlockHeader {
        // SAFETY: the pointer is to a live header for as long as this handle exists.
        unsafe { self.0.as_ref() }
    }

    #[inline]
    pub(crate) fn len(&self) -> usize {
        self.header().len as usize
    }

    #[inline]
    pub(crate) fn capacity(&self) -> usize {
        self.header().capacity as usize
    }

    #[inline]
    fn items(&self) -> *mut T {
        // SAFETY: the allocation extends at least to the start of the items.
        unsafe {
            self.0
                .as_ptr()
                .cast::<u8>()
                .add(Self::ITEMS_OFFSET)
                .cast::<T>()
        }
    }

    #[inline]
    pub(crate) fn as_slice(&self) -> &[T] {
        // SAFETY: the first `len` items are initialized, and nothing writes to a shared block.
        unsafe { std::slice::from_raw_parts(self.items(), self.len()) }
    }

    /// Whether this is the only handle to its buffer.
    #[inline]
    pub(crate) fn is_unique(&self) -> bool {
        self.header().refs.load(Ordering::Acquire) == 1
    }

    /// Whether both handles are to the same buffer.
    #[inline]
    pub(crate) fn ptr_eq(&self, other: &Self) -> bool {
        self.0 == other.0
    }

    /// Set the length.
    ///
    /// # Safety
    /// The block must be unshared, and exactly the first `len` items initialized.
    #[inline]
    unsafe fn set_len(&mut self, len: usize) {
        // SAFETY: the caller holds the only handle, so nothing else reads the header.
        unsafe { (*self.0.as_ptr()).len = len as u32 };
    }

    /// Give a block that nothing else holds room for `capacity` items, which must be more than
    /// it has.
    fn grow_unshared(&mut self, capacity: usize) {
        assert!(self.is_unique() && capacity > self.capacity());
        let old_layout = Self::layout(self.capacity());
        let new_layout = Self::layout(capacity);
        // SAFETY: the buffer was allocated with `old_layout`, and we hold the only handle to it.
        // Moving it moves the header and the initialized items with it.
        let ptr = unsafe { alloc::realloc(self.0.as_ptr().cast(), old_layout, new_layout.size()) }
            .cast::<BlockHeader>();
        let Some(ptr) = NonNull::new(ptr) else {
            alloc::handle_alloc_error(new_layout)
        };
        self.0 = ptr;
        // SAFETY: the header is live and ours alone.
        unsafe { (*self.0.as_ptr()).capacity = u32::try_from(capacity).expect("block too large") };
    }

    /// Add an item at the end.
    ///
    /// # Safety
    /// The block must be unshared and have spare capacity.
    #[inline]
    pub(crate) unsafe fn push_unchecked(&mut self, value: T) {
        let len = self.len();
        debug_assert!(len < self.capacity());
        // SAFETY: by the caller's contract slot `len` is in bounds, unused, and ours alone.
        unsafe {
            self.items().add(len).write(value);
            self.set_len(len + 1);
        }
    }
}

impl<T> FromIterator<T> for Block<T> {
    /// A block of the items. It has room for exactly as many as the iterator says it has at
    /// least, and grows if there turn out to be more.
    fn from_iter<I: IntoIterator<Item = T>>(values: I) -> Self {
        let values = values.into_iter();
        let mut block = Self::with_capacity(values.size_hint().0);
        for value in values {
            if block.len() == block.capacity() {
                block.grow_unshared((block.len() * 2).max(MIN_GROWN_CAPACITY));
            }
            // SAFETY: the block is new, so unshared, and was just given spare capacity if it
            // had none.
            unsafe { block.push_unchecked(value) };
        }
        block
    }
}

impl<T: Clone> Block<T> {
    pub(crate) fn from_slice(values: &[T]) -> Self {
        let mut block = Self::with_capacity(values.len());
        for value in values {
            // SAFETY: the block is new, so unshared, and has room for every value.
            unsafe { block.push_unchecked(value.clone()) };
        }
        block
    }

    /// Make this the only handle to its buffer, with room for at least `capacity` items.
    pub(crate) fn make_unique(&mut self, capacity: usize) {
        let len = self.len();
        let capacity = capacity.max(len);
        if !self.is_unique() {
            let mut copy = Self::with_capacity(capacity);
            for value in self.as_slice() {
                // SAFETY: `copy` is new, so unshared, and has room for every item.
                unsafe { copy.push_unchecked(value.clone()) };
            }
            *self = copy;
            return;
        }
        if self.capacity() < capacity {
            self.grow_unshared(capacity);
        }
    }

    /// The items, for writing. Copies them first if the buffer is shared.
    pub(crate) fn as_mut_slice(&mut self) -> &mut [T] {
        self.make_unique(0);
        // SAFETY: the block is now unshared and its first `len` items are initialized.
        unsafe { std::slice::from_raw_parts_mut(self.items(), self.len()) }
    }

    /// Make room to add one item to an unshared buffer, growing by doubling up to `limit` items.
    pub(crate) fn reserve_one(&mut self, limit: usize) {
        let len = self.len();
        debug_assert!(len < limit);
        if len < self.capacity() && self.is_unique() {
            return;
        }
        let grown = (len * 2).clamp(MIN_GROWN_CAPACITY, limit).max(len + 1);
        self.make_unique(grown.max(self.capacity()));
    }

    /// Add an item at the end. The block never grows past `limit` items.
    pub(crate) fn push(&mut self, value: T, limit: usize) {
        self.reserve_one(limit);
        // SAFETY: `reserve_one` left the block unshared with spare capacity.
        unsafe { self.push_unchecked(value) };
    }

    /// Add copies of `values` at the end. The block must not grow past `limit` items.
    pub(crate) fn extend_from_slice(&mut self, values: &[T], limit: usize) {
        let len = self.len() + values.len();
        assert!(len <= limit);
        // Keep a block's full capacity, so that later pushes do not grow it again.
        self.make_unique(len.max(self.capacity()));
        // SAFETY: the block is unshared and was just given room for every value. The length is
        // set once the copies are in place; if a clone panics, the copies made so far leak.
        unsafe {
            let mut slot = self.items().add(self.len());
            for value in values {
                slot.write(value.clone());
                slot = slot.add(1);
            }
            self.set_len(len);
        }
    }

    /// Drop the items from index `len` on. A shared block is replaced by one with room for
    /// `capacity` items.
    pub(crate) fn truncate(&mut self, len: usize, capacity: usize) {
        let old_len = self.len();
        assert!(len <= old_len);
        if !self.is_unique() {
            let mut kept = Self::with_capacity(capacity.max(len));
            for value in &self.as_slice()[..len] {
                // SAFETY: `kept` is new, so unshared, and has room for `len` items.
                unsafe { kept.push_unchecked(value.clone()) };
            }
            *self = kept;
            return;
        }
        // SAFETY: the block is unshared. The length drops first, so the items being dropped are
        // already outside it.
        unsafe {
            self.set_len(len);
            ptr::drop_in_place(ptr::slice_from_raw_parts_mut(
                self.items().add(len),
                old_len - len,
            ));
        }
    }

    /// Move the items from index `at` on into a new block with room for `capacity` items, and
    /// return it. If this block is shared the new one gets copies, and this one is replaced by
    /// a copy of the items it keeps.
    pub(crate) fn split_off(&mut self, at: usize, capacity: usize) -> Self {
        let len = self.len();
        assert!(at <= len);
        let mut tail = Self::with_capacity(capacity.max(len - at));
        if !self.is_unique() {
            tail.extend_from_slice(&self.as_slice()[at..], usize::MAX);
            self.truncate(at, capacity);
            return tail;
        }
        // SAFETY: both blocks are unshared, and `tail` has room. The items move as bytes, and
        // the lengths are set so that each is owned by exactly one block.
        unsafe {
            ptr::copy_nonoverlapping(self.items().add(at), tail.items(), len - at);
            self.set_len(at);
            tail.set_len(len - at);
        }
        tail
    }

    /// Add the items of `other` at the end, moving them if nothing else holds `other`. The
    /// block must not grow past `limit` items.
    pub(crate) fn append(&mut self, mut other: Self, limit: usize) {
        if !other.is_unique() {
            self.extend_from_slice(other.as_slice(), limit);
            return;
        }
        let (len, added) = (self.len(), other.len());
        assert!(len + added <= limit);
        self.make_unique((len + added).max(self.capacity()));
        // SAFETY: both blocks are unshared, and this one was just given room. The items move as
        // bytes, and the lengths are set so that each is owned by exactly one block.
        unsafe {
            ptr::copy_nonoverlapping(other.items(), self.items().add(len), added);
            other.set_len(0);
            self.set_len(len + added);
        }
    }

    /// Insert an item before `index`. The block never grows past `limit` items.
    pub(crate) fn insert(&mut self, index: usize, value: T, limit: usize) {
        let len = self.len();
        assert!(index <= len);
        self.reserve_one(limit);
        // SAFETY: the block is unshared with room for `len + 1` items. The items from `index` on
        // move up one slot, which leaves slot `index` free to write.
        unsafe {
            let slot = self.items().add(index);
            ptr::copy(slot, slot.add(1), len - index);
            slot.write(value);
            self.set_len(len + 1);
        }
    }

    /// Remove and return the item at `index`.
    pub(crate) fn remove(&mut self, index: usize) -> T {
        let len = self.len();
        assert!(index < len);
        self.make_unique(0);
        // SAFETY: the block is unshared. The item is read out and the ones after it move down
        // over its slot, so exactly the first `len - 1` slots stay initialized.
        unsafe {
            let slot = self.items().add(index);
            let value = slot.read();
            ptr::copy(slot.add(1), slot, len - index - 1);
            self.set_len(len - 1);
            value
        }
    }
}

impl<T> Clone for Block<T> {
    #[inline]
    fn clone(&self) -> Self {
        let refs = self.header().refs.fetch_add(1, Ordering::Relaxed);
        // As in `Arc`: a count this large can only come from leaking handles.
        if refs > isize::MAX as usize {
            std::process::abort();
        }
        Self(self.0, PhantomData)
    }
}

impl<T> Drop for Block<T> {
    #[inline]
    fn drop(&mut self) {
        // The only handle can skip the decrement: no other handle exists to copy from, so the
        // count cannot rise again.
        if !self.is_unique() {
            if self.header().refs.fetch_sub(1, Ordering::Release) != 1 {
                return;
            }
            atomic::fence(Ordering::Acquire);
        }
        let layout = Self::layout(self.capacity());
        // SAFETY: this was the last handle. The first `len` items are initialized, and the
        // buffer was allocated with this layout.
        unsafe {
            ptr::drop_in_place(ptr::slice_from_raw_parts_mut(self.items(), self.len()));
            alloc::dealloc(self.0.as_ptr().cast(), layout);
        }
    }
}

/// One pointer to either a [`Block`] of items or an `Arc` of a tree, told apart by the pointer's
/// low bit. A collection that is a single block while small and a tree when large is one of
/// these, and so is one pointer wide.
#[repr(transparent)]
pub(crate) struct Shape<T, Tree>(NonNull<u8>, PhantomData<(Block<T>, Arc<Tree>)>);

const TREE_TAG: usize = 1;

// SAFETY: a shape owns a `Block` or an `Arc`, and is `Send + Sync` when both are.
unsafe impl<T: Send + Sync, Tree: Send + Sync> Send for Shape<T, Tree> {}
unsafe impl<T: Send + Sync, Tree: Send + Sync> Sync for Shape<T, Tree> {}

pub(crate) enum ShapeRef<'a, T, Tree> {
    Flat(&'a Block<T>),
    Tree(&'a Tree),
}

pub(crate) enum ShapeOwned<T, Tree> {
    Flat(Block<T>),
    Tree(Arc<Tree>),
}

impl<T, Tree> Shape<T, Tree> {
    /// Both kinds of pointer must leave the low bit free for the tag.
    const LOW_BIT_IS_FREE: () =
        assert!(align_of::<Tree>() > TREE_TAG && align_of::<BlockHeader>() > TREE_TAG);

    #[inline]
    pub(crate) fn from_block(block: Block<T>) -> Self {
        Self(ManuallyDrop::new(block).0.cast(), PhantomData)
    }

    #[inline]
    pub(crate) fn from_tree(tree: Arc<Tree>) -> Self {
        let () = Self::LOW_BIT_IS_FREE;
        let ptr = Arc::into_raw(tree).cast_mut().cast::<u8>();
        // SAFETY: the pointer came from an `Arc`, so it is not null, and setting a low bit keeps
        // it so.
        let tagged = unsafe { NonNull::new_unchecked(ptr.map_addr(|addr| addr | TREE_TAG)) };
        Self(tagged, PhantomData)
    }

    #[inline]
    pub(crate) fn is_tree(&self) -> bool {
        self.0.addr().get() & TREE_TAG != 0
    }

    #[inline]
    fn tree_ptr(&self) -> *const Tree {
        self.0
            .as_ptr()
            .map_addr(|addr| addr & !TREE_TAG)
            .cast::<Tree>()
    }

    /// Whether both are the same block or the same tree.
    #[inline]
    pub(crate) fn ptr_eq(&self, other: &Self) -> bool {
        self.0 == other.0
    }

    #[inline]
    pub(crate) fn get(&self) -> ShapeRef<'_, T, Tree> {
        if self.is_tree() {
            // SAFETY: a tagged pointer is to the tree of an `Arc` this shape keeps alive.
            ShapeRef::Tree(unsafe { &*self.tree_ptr() })
        } else {
            // SAFETY: an untagged shape and a `Block` are both a pointer to a block header, and
            // this shape owns a count on that block.
            ShapeRef::Flat(unsafe { &*(self as *const Self).cast::<Block<T>>() })
        }
    }

    #[inline]
    pub(crate) fn into_owned(self) -> ShapeOwned<T, Tree> {
        let this = ManuallyDrop::new(self);
        if this.is_tree() {
            // SAFETY: the pointer came from `Arc::into_raw`, and this shape's count passes to
            // the `Arc`.
            ShapeOwned::Tree(unsafe { Arc::from_raw(this.tree_ptr()) })
        } else {
            ShapeOwned::Flat(Block(this.0.cast(), PhantomData))
        }
    }
}

impl<T, Tree> Clone for Shape<T, Tree> {
    #[inline]
    fn clone(&self) -> Self {
        match self.get() {
            ShapeRef::Flat(block) => Self::from_block(block.clone()),
            ShapeRef::Tree(_) => {
                // SAFETY: the pointer came from `Arc::into_raw`. The `Arc` is only borrowed here:
                // `ManuallyDrop` leaves this shape's count in place.
                let tree = ManuallyDrop::new(unsafe { Arc::from_raw(self.tree_ptr()) });
                Self::from_tree(Arc::clone(&tree))
            }
        }
    }
}

impl<T, Tree> Drop for Shape<T, Tree> {
    #[inline]
    fn drop(&mut self) {
        // SAFETY: `self` is not used again, so its count passes to the owned form and is
        // released with it.
        drop(unsafe { ptr::read(self) }.into_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::Block;

    #[test]
    fn a_shared_block_grows_before_it_is_extended() {
        let mut block = Block::with_capacity(8);
        block.push(1, 8);
        let other = block.clone();
        block.extend_from_slice(&[2, 3, 4], 8);
        assert_eq!(block.as_slice(), [1, 2, 3, 4]);
        assert_eq!(other.as_slice(), [1]);
    }

    #[test]
    fn a_block_collects_every_item_whatever_the_iterator_promises() {
        // `filter` promises nothing, and a range promises exactly.
        let filtered: Block<String> = (0..40).filter(|_| true).map(|i| i.to_string()).collect();
        assert_eq!(filtered.len(), 40);
        assert_eq!(filtered.as_slice()[39], "39");
        let exact: Block<i32> = (0..40).collect();
        assert_eq!((exact.len(), exact.capacity()), (40, 40));
        assert_eq!(Block::<i32>::from_iter([]).len(), 0);
    }

    #[test]
    fn splitting_and_appending_move_or_copy_as_sharing_requires() {
        let strings =
            |range: std::ops::Range<i32>| -> Vec<String> { range.map(|i| i.to_string()).collect() };
        for shared in [false, true] {
            let mut block: Block<String> = strings(0..10).into_iter().collect();
            let other = shared.then(|| block.clone());
            let tail = block.split_off(4, 16);
            assert_eq!(block.as_slice(), strings(0..4));
            assert_eq!(tail.as_slice(), strings(4..10));

            let tail_copy = shared.then(|| tail.clone());
            block.append(tail, 16);
            assert_eq!(block.as_slice(), strings(0..10));
            if let (Some(other), Some(tail_copy)) = (other, tail_copy) {
                assert_eq!(other.as_slice(), strings(0..10));
                assert_eq!(tail_copy.as_slice(), strings(4..10));
            }
        }
    }

    #[test]
    fn items_with_wider_alignment_and_drops_are_handled() {
        // A string owns memory, so Miri sees a missed or doubled drop; `u128` is wider than the
        // header's fields.
        let mut block = Block::<(u128, String)>::with_capacity(0);
        for i in 0..40u128 {
            block.push((i, i.to_string()), 64);
        }
        let shared = block.clone();
        block.insert(3, (99, "x".into()), 64);
        assert_eq!(block.remove(0).0, 0);
        block.truncate(10, 16);
        assert_eq!(block.as_slice()[2], (99, "x".to_string()));
        assert_eq!(shared.len(), 40);
        assert_eq!(shared.as_slice()[39].1, "39");
    }
}
