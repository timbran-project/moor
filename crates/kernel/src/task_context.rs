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

//! Thread-local task context for eliminating parameter threading.
//! Provides RAII-based transaction management with automatic cleanup.
//! Contains WorldState, TaskSchedulerClient, task_id, player objid, and Session.

use std::{cell::RefCell, sync::Arc};

#[cfg(feature = "trace_events")]
use std::collections::hash_map::DefaultHasher;
#[cfg(feature = "trace_events")]
use std::hash::{Hash, Hasher};

use moor_common::{
    model::{
        BuiltinProxyCacheBits, CommitResult, WorldState, WorldStateError, loader::LoaderInterface,
    },
    tasks::{Session, TaskId},
};
use moor_compiler::BuiltinId;
use moor_var::Obj;

use crate::tasks::task_scheduler_client::TaskSchedulerClient;

const BITS_PER_WORD: usize = u64::BITS as usize;

#[derive(Clone)]
struct BuiltinProxyCache {
    absent: BuiltinProxyCacheBits,
    guard_version: i64,
}

impl BuiltinProxyCache {
    fn new(absent: BuiltinProxyCacheBits, guard_version: i64) -> Self {
        Self {
            absent,
            guard_version,
        }
    }

    fn is_absent(&self, builtin: BuiltinId) -> bool {
        let bit = usize::from(builtin.0);
        let word = bit / BITS_PER_WORD;
        if word >= self.absent.len() {
            return false;
        }
        self.absent[word] & (1 << (bit % BITS_PER_WORD)) != 0
    }

    fn mark_absent(&mut self, builtin: BuiltinId) {
        let bit = usize::from(builtin.0);
        let word = bit / BITS_PER_WORD;
        if word >= self.absent.len() {
            return;
        }
        self.absent[word] |= 1 << (bit % BITS_PER_WORD);
    }
}

impl TaskContext {
    fn builtin_proxy_cache_from_world_state(world_state: &dyn WorldState) -> BuiltinProxyCache {
        BuiltinProxyCache::new(
            world_state.builtin_proxy_cache_snapshot(),
            world_state.builtin_proxy_cache_guard_version(),
        )
    }

    fn refresh_builtin_proxy_cache_if_changed(&mut self) {
        let guard_version = self.world_state.builtin_proxy_cache_guard_version();
        if guard_version == self.builtin_proxy_cache.guard_version {
            return;
        }
        self.builtin_proxy_cache = BuiltinProxyCache::new(
            self.world_state.builtin_proxy_cache_snapshot(),
            guard_version,
        );
    }
}

/// Complete current task execution context containing all necessary state.
/// There is one of these per-thread, and no more, and each running task *must* have one, and this
/// is considered an invariant (failure to have one is a panic).
pub struct TaskContext {
    pub world_state: Box<dyn WorldState>,
    pub task_scheduler_client: TaskSchedulerClient,
    pub task_id: TaskId,
    pub player: Obj,
    pub session: Arc<dyn Session>,
    builtin_proxy_cache: BuiltinProxyCache,
}

thread_local! {
    static CURRENT_CONTEXT: RefCell<Option<TaskContext>> = const { RefCell::new(None) };
}

/// RAII guard that ensures transaction cleanup on drop.
/// Transaction must be explicitly committed or rolled back before drop.
pub struct TaskGuard(());

impl TaskGuard {
    /// Start a new task context on the current thread.
    /// Panics if a context is already active.
    pub fn new(
        world_state: Box<dyn WorldState>,
        task_scheduler_client: TaskSchedulerClient,
        task_id: TaskId,
        player: Obj,
        session: Arc<dyn Session>,
    ) -> Self {
        CURRENT_CONTEXT.with(|ctx| {
            let mut current = ctx.borrow_mut();
            assert!(
                current.is_none(),
                "Task context already active on this thread"
            );
            let builtin_proxy_cache =
                TaskContext::builtin_proxy_cache_from_world_state(world_state.as_ref());
            *current = Some(TaskContext {
                world_state,
                task_scheduler_client,
                task_id,
                player,
                session,
                builtin_proxy_cache,
            });
        });

        #[cfg(feature = "trace_events")]
        {
            let thread_id = {
                let mut hasher = DefaultHasher::new();
                std::thread::current().id().hash(&mut hasher);
                hasher.finish()
            };
            crate::trace_transaction_begin!(format!("task_{task_id}"), thread_id);
        }

        TaskGuard(())
    }
}

impl Drop for TaskGuard {
    fn drop(&mut self) {
        // Emergency cleanup - rollback any remaining transaction
        CURRENT_CONTEXT.with(|ctx| {
            if let Some(task_ctx) = ctx.borrow_mut().take() {
                // Only warn if we're not already panicking (which would trigger this drop)
                if !std::thread::panicking() {
                    tracing::warn!(
                        "Task context dropped without explicit commit/rollback, rolling back"
                    );
                }

                #[cfg(feature = "trace_events")]
                {
                    let task_id = task_ctx.task_id;
                    let thread_id = {
                        let mut hasher = DefaultHasher::new();
                        std::thread::current().id().hash(&mut hasher);
                        hasher.finish()
                    };

                    // Emit emergency rollback event
                    crate::trace_transaction_rollback!(
                        format!("task_{task_id}"),
                        thread_id,
                        "emergency_cleanup"
                    );

                    // End the transaction span
                    use crate::tracing_events::{TraceEventType, emit_trace_event};
                    emit_trace_event(TraceEventType::TransactionEnd {
                        tx_id: format!("task_{task_id}"),
                        thread_id,
                    });
                }

                let _ = task_ctx.world_state.rollback(); // Best effort cleanup
            }
        });
    }
}

/// Execute a closure with access to the current transaction.
/// Panics if no context is active.
pub fn with_current_transaction<R>(f: impl FnOnce(&dyn WorldState) -> R) -> R {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        f(task_ctx.world_state.as_ref())
    })
}

/// Execute a closure with mutable access to the current transaction.
/// Panics if no context is active.
pub fn with_current_transaction_mut<R>(f: impl FnOnce(&mut dyn WorldState) -> R) -> R {
    CURRENT_CONTEXT.with(|ctx| {
        let mut ctx_ref = ctx.borrow_mut();
        let task_ctx = ctx_ref
            .as_mut()
            .expect("No active task context on this thread");
        let result = f(task_ctx.world_state.as_mut());
        task_ctx.refresh_builtin_proxy_cache_if_changed();
        result
    })
}

/// Return true if the current transaction has already proven this builtin has no #0 proxy.
pub fn builtin_proxy_absent_cached(builtin: BuiltinId) -> bool {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        task_ctx.builtin_proxy_cache.is_absent(builtin)
    })
}

/// Remember that this builtin has no #0 proxy in the current transaction.
pub fn mark_builtin_proxy_absent(builtin: BuiltinId) {
    CURRENT_CONTEXT.with(|ctx| {
        let mut ctx_ref = ctx.borrow_mut();
        let task_ctx = ctx_ref
            .as_mut()
            .expect("No active task context on this thread");
        task_ctx.builtin_proxy_cache.mark_absent(builtin);
        task_ctx.world_state.mark_builtin_proxy_absent(builtin);
    });
}

/// Get a clone of the current task scheduler client.
/// Panics if no context is active.
pub fn current_task_scheduler_client() -> TaskSchedulerClient {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        task_ctx.task_scheduler_client.clone()
    })
}

/// Get the current task ID.
/// Panics if no context is active.
pub fn current_task_id() -> TaskId {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        task_ctx.task_id
    })
}

/// Get the current player object.
/// Panics if no context is active.
pub fn current_player() -> Obj {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        task_ctx.player
    })
}

/// Get a clone of the current session.
/// Panics if no context is active.
pub fn current_session() -> Arc<dyn Session> {
    CURRENT_CONTEXT.with(|ctx| {
        let ctx_ref = ctx.borrow();
        let task_ctx = ctx_ref
            .as_ref()
            .expect("No active task context on this thread");
        task_ctx.session.clone()
    })
}

/// Commit the current thread's active transaction.
/// Panics if no context is active.
pub fn commit_current_transaction() -> Result<CommitResult, WorldStateError> {
    CURRENT_CONTEXT.with(|ctx| {
        let task_ctx = ctx
            .borrow_mut()
            .take()
            .expect("No active task context to commit");

        #[cfg(feature = "trace_events")]
        let task_id = task_ctx.task_id;
        #[cfg(feature = "trace_events")]
        let thread_id = {
            let mut hasher = DefaultHasher::new();
            std::thread::current().id().hash(&mut hasher);
            hasher.finish()
        };

        let result = task_ctx.world_state.commit();

        #[cfg(feature = "trace_events")]
        {
            // Emit commit event and end the transaction span
            let success = matches!(result, Ok(moor_common::model::CommitResult::Success { .. }));
            let timestamp = match &result {
                Ok(moor_common::model::CommitResult::Success { timestamp, .. }) => *timestamp,
                _ => 0,
            };

            crate::trace_transaction_commit!(
                format!("task_{task_id}"),
                thread_id,
                success,
                timestamp
            );

            // End the transaction span
            use crate::tracing_events::{TraceEventType, emit_trace_event};
            emit_trace_event(TraceEventType::TransactionEnd {
                tx_id: format!("task_{task_id}"),
                thread_id,
            });
        }

        result
    })
}

/// Rollback the current thread's active transaction.
/// Panics if no context is active.
pub fn rollback_current_transaction() -> Result<(), WorldStateError> {
    CURRENT_CONTEXT.with(|ctx| {
        let task_ctx = ctx
            .borrow_mut()
            .take()
            .expect("No active task context to rollback");

        #[cfg(feature = "trace_events")]
        {
            let task_id = task_ctx.task_id;
            let thread_id = {
                let mut hasher = DefaultHasher::new();
                std::thread::current().id().hash(&mut hasher);
                hasher.finish()
            };

            // Emit rollback event and end the transaction span
            crate::trace_transaction_rollback!(
                format!("task_{task_id}"),
                thread_id,
                "explicit_rollback"
            );

            // End the transaction span
            use crate::tracing_events::{TraceEventType, emit_trace_event};
            emit_trace_event(TraceEventType::TransactionEnd {
                tx_id: format!("task_{task_id}"),
                thread_id,
            });
        }

        task_ctx.world_state.rollback()
    })
}

/// Check if there's an active context on the current thread.
pub fn has_active_task() -> bool {
    CURRENT_CONTEXT.with(|ctx| ctx.borrow().is_some())
}

/// Extract the current transaction from thread-local storage.
/// This is a transitional helper for compatibility with existing parameter-passing code.
/// Panics if no context is active.
pub fn extract_current_transaction() -> Box<dyn WorldState> {
    CURRENT_CONTEXT.with(|ctx| {
        let task_ctx = ctx
            .borrow_mut()
            .take()
            .expect("No active task context to extract");
        task_ctx.world_state
    })
}

#[derive(Debug)]
pub enum TransactionRenewalError {
    Commit(WorldStateError),
    Begin(WorldStateError),
}

/// Execute a closure that creates a new transaction while preserving the current task context.
/// This atomically commits the current transaction and starts a new one with preserved context.
pub fn with_new_transaction<F, R>(
    create_transaction: F,
) -> Result<(CommitResult, Option<R>), TransactionRenewalError>
where
    F: FnOnce() -> Result<(Box<dyn WorldState>, R), WorldStateError>,
{
    // Extract context before commit to preserve it
    let (task_scheduler_client, task_id, player, session) = CURRENT_CONTEXT.with(|ctx| {
        let mut task_ctx = ctx.borrow_mut();
        let task_ctx = task_ctx.as_mut().expect("No active task context");
        (
            task_ctx.task_scheduler_client.clone(),
            task_ctx.task_id,
            task_ctx.player,
            task_ctx.session.clone(),
        )
    });

    // Commit current transaction (this removes the context)
    let commit_result = commit_current_transaction().map_err(TransactionRenewalError::Commit)?;

    match commit_result {
        CommitResult::Success { .. } => {
            // Create the new transaction
            let (new_world_state, result) =
                create_transaction().map_err(TransactionRenewalError::Begin)?;

            // Restore context with new world state and preserved values
            CURRENT_CONTEXT.with(|ctx| {
                let mut current = ctx.borrow_mut();
                assert!(
                    current.is_none(),
                    "Task context unexpectedly active after commit"
                );
                let builtin_proxy_cache =
                    TaskContext::builtin_proxy_cache_from_world_state(new_world_state.as_ref());
                *current = Some(TaskContext {
                    world_state: new_world_state,
                    task_scheduler_client,
                    task_id,
                    player,
                    session,
                    builtin_proxy_cache,
                });
            });

            Ok((commit_result, Some(result)))
        }
        CommitResult::ConflictRetry { conflict_info } => {
            // On conflict, we don't create a new transaction
            Ok((CommitResult::ConflictRetry { conflict_info }, None))
        }
    }
}

/// Execute a closure with loader interface access to the current transaction.
/// This temporarily extracts the WorldState, converts it to LoaderInterface using
/// the same underlying transaction, executes the closure, then restores it as WorldState.
/// Returns an error if no context is active or if the WorldState doesn't support conversion.
pub fn with_loader_interface<F, R, E>(f: F) -> Result<R, E>
where
    F: FnOnce(&mut dyn LoaderInterface) -> Result<R, E>,
{
    // Extract the current WorldState and context info
    let (world_state, task_scheduler_client, task_id, player, session) =
        CURRENT_CONTEXT.with(|ctx| {
            let task_ctx = ctx.borrow_mut().take().expect("No active task context");
            (
                task_ctx.world_state,
                task_ctx.task_scheduler_client,
                task_ctx.task_id,
                task_ctx.player,
                task_ctx.session,
            )
        });

    // Convert WorldState to LoaderInterface
    let mut loader = world_state
        .as_loader_interface()
        .expect("Could not extract loader from world state");

    // Execute the closure with loader interface
    let result = f(loader.as_mut());

    // Convert back to WorldState
    let world_state = loader
        .as_world_state()
        .expect("Could not extract world state from loader");

    // Restore the context
    CURRENT_CONTEXT.with(|ctx| {
        let mut current = ctx.borrow_mut();
        let builtin_proxy_cache =
            TaskContext::builtin_proxy_cache_from_world_state(world_state.as_ref());
        *current = Some(TaskContext {
            world_state,
            task_scheduler_client,
            task_id,
            player,
            session,
            builtin_proxy_cache,
        });
    });

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    // For now, we just test the basic guard functionality without a full WorldState mock
    // since implementing the full WorldState trait would be quite large

    #[test]
    fn test_no_transaction_initially() {
        assert!(!has_active_task());
    }

    #[test]
    #[should_panic(expected = "No active task context")]
    fn test_panic_on_no_transaction() {
        with_current_transaction(|_| ());
    }

    #[test]
    #[should_panic(expected = "No active task context to commit")]
    fn test_panic_on_commit_no_transaction() {
        commit_current_transaction().unwrap();
    }

    #[test]
    #[should_panic(expected = "No active task context to rollback")]
    fn test_panic_on_rollback_no_transaction() {
        rollback_current_transaction().unwrap();
    }
}
