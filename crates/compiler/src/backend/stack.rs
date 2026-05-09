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

use moor_var::program::labels::Offset;

#[derive(Debug, Default)]
pub struct StackState {
    cur_stack: usize,
    max_stack: usize,
    saved_stack: Option<Offset>,
}

#[derive(Debug)]
pub struct StackSnapshot {
    cur_stack: usize,
    max_stack: usize,
    saved_stack: Option<Offset>,
}

#[derive(Debug, Default)]
pub struct ScopeDepthState {
    cur_depth: usize,
    max_depth: usize,
}

#[derive(Debug)]
pub struct ScopeDepthSnapshot {
    cur_depth: usize,
    max_depth: usize,
}

impl StackState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, n: usize) {
        self.cur_stack += n;
        if self.cur_stack > self.max_stack {
            self.max_stack = self.cur_stack;
        }
    }

    pub fn pop(&mut self, n: usize) {
        if self.cur_stack < n {
            panic!(
                "Stack underflow: trying to pop {} items but stack only has {} items",
                n, self.cur_stack
            );
        }
        self.cur_stack -= n;
    }

    pub fn depth(&self) -> usize {
        self.cur_stack
    }

    pub fn set_depth(&mut self, depth: usize) {
        self.cur_stack = depth;
        if self.cur_stack > self.max_stack {
            self.max_stack = self.cur_stack;
        }
    }

    pub fn max_depth(&self) -> usize {
        self.max_stack
    }

    pub fn snapshot_and_reset(&mut self) -> StackSnapshot {
        let snapshot = StackSnapshot {
            cur_stack: self.cur_stack,
            max_stack: self.max_stack,
            saved_stack: self.saved_stack,
        };
        self.cur_stack = 0;
        self.max_stack = 0;
        self.saved_stack = None;
        snapshot
    }

    pub fn restore(&mut self, snapshot: StackSnapshot) {
        self.cur_stack = snapshot.cur_stack;
        self.max_stack = snapshot.max_stack;
        self.saved_stack = snapshot.saved_stack;
    }

    pub fn saved_top(&self) -> Option<Offset> {
        self.saved_stack
    }

    pub fn save_top(&mut self) -> Option<Offset> {
        let old = self.saved_stack;
        self.saved_stack = Some((self.cur_stack - 1).into());
        old
    }

    pub fn restore_saved_top(&mut self, old: Option<Offset>) {
        self.saved_stack = old;
    }
}

impl ScopeDepthState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn enter(&mut self) {
        self.cur_depth += 1;
        if self.cur_depth > self.max_depth {
            self.max_depth = self.cur_depth;
        }
    }

    pub fn exit(&mut self) {
        if self.cur_depth == 0 {
            panic!("Scope depth underflow");
        }
        self.cur_depth -= 1;
    }

    pub fn depth(&self) -> usize {
        self.cur_depth
    }

    pub fn max_depth(&self) -> usize {
        self.max_depth
    }

    pub fn snapshot_and_reset(&mut self) -> ScopeDepthSnapshot {
        let snapshot = ScopeDepthSnapshot {
            cur_depth: self.cur_depth,
            max_depth: self.max_depth,
        };
        self.cur_depth = 0;
        self.max_depth = 0;
        snapshot
    }

    pub fn restore(&mut self, snapshot: ScopeDepthSnapshot) {
        self.cur_depth = snapshot.cur_depth;
        self.max_depth = snapshot.max_depth;
    }
}

#[cfg(test)]
mod tests {
    use super::StackState;
    use moor_var::program::labels::Offset;

    #[test]
    fn tracks_depth_and_saved_top() {
        let mut stack = StackState::new();
        stack.push(3);
        assert_eq!(stack.depth(), 3);
        assert_eq!(stack.max_depth(), 3);

        let old = stack.save_top();
        assert_eq!(old, None);
        assert_eq!(stack.saved_top(), Some(Offset(2)));

        stack.pop(2);
        assert_eq!(stack.depth(), 1);
        stack.restore_saved_top(old);
        assert_eq!(stack.saved_top(), None);
    }

    #[test]
    fn depth_reset_updates_max_depth() {
        let mut stack = StackState::new();
        stack.set_depth(4);
        stack.set_depth(2);
        assert_eq!(stack.depth(), 2);
        assert_eq!(stack.max_depth(), 4);
    }

    #[test]
    fn scope_depth_tracks_max_and_restore() {
        let mut scopes = super::ScopeDepthState::new();
        scopes.enter();
        scopes.enter();
        scopes.exit();
        assert_eq!(scopes.depth(), 1);
        assert_eq!(scopes.max_depth(), 2);

        let snapshot = scopes.snapshot_and_reset();
        assert_eq!(scopes.depth(), 0);
        assert_eq!(scopes.max_depth(), 0);

        scopes.restore(snapshot);
        assert_eq!(scopes.depth(), 1);
        assert_eq!(scopes.max_depth(), 2);
    }
}
