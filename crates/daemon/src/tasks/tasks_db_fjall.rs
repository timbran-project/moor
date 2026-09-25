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

use fjall::{Database, Keyspace, KeyspaceCreateOptions};
use moor_common::{tasks::TaskId, util::signal_fatal_db_error};
use moor_kernel::{
    SuspendedTask,
    tasks::{
        TasksDb, TasksDbError,
        convert_task::{
            schedule_from_ref, schedule_to_flatbuffer, suspended_task_from_ref,
            suspended_task_to_flatbuffer,
        },
        schedule_q::{ScheduleEntry, ScheduleId},
    },
};
use planus::{ReadAsRoot, WriteAsOffset};
use std::{
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tracing::{debug, error, warn};

/// Handle a fjall error, with special handling for Poisoned errors.
fn handle_fjall_error(e: &fjall::Error, operation: &str) {
    if matches!(e, fjall::Error::Poisoned) {
        signal_fatal_db_error(operation, "database poisoned (fsync failure)");
    } else {
        error!("Tasks DB error during {operation}: {e:?}");
    }
}

pub struct FjallTasksDB {
    keyspace: Database,
    tasks_partition: Keyspace,
    schedules_partition: Keyspace,
    /// Guard to prevent overlapping compaction runs
    compaction_in_progress: Arc<AtomicBool>,
}

impl FjallTasksDB {
    pub fn open(path: &Path) -> (Self, bool) {
        let keyspace = Database::builder(path).open().unwrap();
        let fresh = keyspace.keyspace_count() == 0;
        let tasks_partition = keyspace
            .keyspace("tasks", KeyspaceCreateOptions::default)
            .unwrap();
        let schedules_partition = keyspace
            .keyspace("schedules", KeyspaceCreateOptions::default)
            .unwrap();
        (
            Self {
                keyspace,
                tasks_partition,
                schedules_partition,
                compaction_in_progress: Arc::new(AtomicBool::new(false)),
            },
            fresh,
        )
    }
}

impl TasksDb for FjallTasksDB {
    fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError> {
        let pi = self.tasks_partition.iter();
        let mut tasks = vec![];
        for entry in pi {
            let (key, value) = entry
                .into_inner()
                .map_err(|_| TasksDbError::CouldNotLoadTasks)?;

            let task_id = TaskId::from_le_bytes(key.as_ref().try_into().map_err(|e| {
                error!("Failed to deserialize TaskId from record: {:?}", e);
                TasksDbError::CouldNotLoadTasks
            })?);
            let tasks_bytes = value.as_ref();

            // Deserialize FlatBuffer directly from ref to avoid copying
            let fb_task =
                moor_schema::task::SuspendedTaskRef::read_as_root(tasks_bytes).map_err(|e| {
                    error!("Failed to read FlatBuffer: {:?}", e);
                    TasksDbError::CouldNotLoadTasks
                })?;

            let task = suspended_task_from_ref(fb_task).map_err(|e| {
                error!("Failed to convert FlatBuffer to SuspendedTask: {:?}", e);
                TasksDbError::CouldNotLoadTasks
            })?;

            if task_id != task.task.task_id {
                panic!("Task ID mismatch: {:?} != {:?}", task_id, task.task.task_id);
            }
            tasks.push(task);
        }
        Ok(tasks)
    }

    fn save_task(&self, task: &SuspendedTask) -> Result<(), TasksDbError> {
        let task_id = task.task.task_id.to_le_bytes();

        // Convert to FlatBuffer
        let fb_task = suspended_task_to_flatbuffer(task).map_err(|e| {
            error!("Failed to convert task to FlatBuffer: {:?}", e);
            TasksDbError::CouldNotSaveTask
        })?;

        // Serialize to bytes using planus
        let mut builder = planus::Builder::new();
        let offset = fb_task.prepare(&mut builder);
        let task_bytes = builder.finish(offset, None);

        self.tasks_partition
            .insert(task_id, task_bytes)
            .map_err(|e| {
                handle_fjall_error(&e, "save_task insert");
                TasksDbError::CouldNotSaveTask
            })?;

        Ok(())
    }

    fn delete_task(&self, task_id: TaskId) -> Result<(), TasksDbError> {
        let task_id = task_id.to_le_bytes();
        self.tasks_partition.remove(task_id).map_err(|e| {
            handle_fjall_error(&e, "delete_task");
            TasksDbError::CouldNotDeleteTask
        })?;
        Ok(())
    }

    fn delete_all_tasks(&self) -> Result<(), TasksDbError> {
        for entry in self.tasks_partition.iter() {
            let (key, _) = entry
                .into_inner()
                .map_err(|_| TasksDbError::CouldNotDeleteTask)?;
            self.tasks_partition.remove(key).map_err(|e| {
                handle_fjall_error(&e, "delete_all_tasks");
                TasksDbError::CouldNotDeleteTask
            })?;
        }
        Ok(())
    }

    fn load_schedules(&self) -> Result<Vec<ScheduleEntry>, TasksDbError> {
        let mut out = vec![];
        for entry in self.schedules_partition.iter() {
            let (key, value) = entry
                .into_inner()
                .map_err(|_| TasksDbError::CouldNotLoadSchedules)?;
            let id = ScheduleId::from_le_bytes(key.as_ref().try_into().map_err(|e| {
                error!("Failed to deserialize ScheduleId from record: {:?}", e);
                TasksDbError::CouldNotLoadSchedules
            })?);
            let fb = moor_schema::task::ScheduleRef::read_as_root(value.as_ref()).map_err(|e| {
                error!("Failed to read schedule FlatBuffer: {:?}", e);
                TasksDbError::CouldNotLoadSchedules
            })?;
            let entry = schedule_from_ref(fb).map_err(|e| {
                error!("Failed to convert FlatBuffer to ScheduleEntry: {:?}", e);
                TasksDbError::CouldNotLoadSchedules
            })?;
            if id != entry.id {
                error!("Schedule ID mismatch: {id} != {}", entry.id);
                return Err(TasksDbError::CouldNotLoadSchedules);
            }
            out.push(entry);
        }
        Ok(out)
    }

    fn save_schedule(&self, entry: &ScheduleEntry) -> Result<(), TasksDbError> {
        let fb = schedule_to_flatbuffer(entry).map_err(|e| {
            error!("Failed to convert schedule to FlatBuffer: {:?}", e);
            TasksDbError::CouldNotSaveSchedule
        })?;
        let mut builder = planus::Builder::new();
        let offset = fb.prepare(&mut builder);
        let bytes = builder.finish(offset, None);
        self.schedules_partition
            .insert(entry.id.to_le_bytes(), bytes)
            .map_err(|e| {
                handle_fjall_error(&e, "save_schedule insert");
                TasksDbError::CouldNotSaveSchedule
            })?;
        Ok(())
    }

    fn delete_schedule(&self, schedule_id: ScheduleId) -> Result<(), TasksDbError> {
        self.schedules_partition
            .remove(schedule_id.to_le_bytes())
            .map_err(|e| {
                handle_fjall_error(&e, "delete_schedule");
                TasksDbError::CouldNotDeleteSchedule
            })?;
        Ok(())
    }

    fn delete_all_schedules(&self) -> Result<(), TasksDbError> {
        for entry in self.schedules_partition.iter() {
            let (key, _) = entry
                .into_inner()
                .map_err(|_| TasksDbError::CouldNotDeleteSchedule)?;
            self.schedules_partition.remove(key).map_err(|e| {
                handle_fjall_error(&e, "delete_all_schedules");
                TasksDbError::CouldNotDeleteSchedule
            })?;
        }
        Ok(())
    }

    fn compact(&self) {
        // Skip if previous compaction is still running
        if self.compaction_in_progress.swap(true, Ordering::SeqCst) {
            warn!("Skipping tasks DB compaction - previous run still in progress");
            return;
        }

        let keyspace = self.keyspace.clone();
        let guard = self.compaction_in_progress.clone();
        std::thread::spawn(move || {
            debug!("Tasks database compaction starting");
            if let Err(e) = keyspace.persist(fjall::PersistMode::SyncAll) {
                handle_fjall_error(&e, "compact/persist");
            }
            guard.store(false, Ordering::SeqCst);
        });
    }
}

#[cfg(test)]
mod tests {
    use crate::tasks::tasks_db_fjall::FjallTasksDB;
    use moor_common::{
        tasks::NoopClientSession,
        util::{Deadline, Instant, Timestamp},
    };
    use moor_kernel::tasks::schedule_q::{
        CatchupPolicy, OverlapPolicy, ScheduleEntry, ScheduleKind, ScheduleOptions,
    };
    use moor_kernel::tasks::{
        DEFAULT_DB_COMMIT_QUEUE_TIMEOUT, DEFAULT_DB_COMMIT_QUEUE_WARN, DEFAULT_MAX_TASK_MAILBOX,
        DEFAULT_MAX_TASK_RETRIES,
    };
    use moor_kernel::{
        SuspendedTask, Task, TaskControl, WakeCondition,
        tasks::{ServerOptions, TaskStart, TasksDb},
    };
    use moor_var::{List, Obj, SYSTEM_OBJECT, Symbol, v_int, v_str};
    use std::{
        sync::Arc,
        time::{Duration, UNIX_EPOCH},
    };
    use uuid::Uuid;

    fn deadline_difference(a: Instant, b: Instant) -> Duration {
        if a >= b { a - b } else { b - a }
    }

    // Verify creation of an empty DB, including creation of tables.
    #[test]
    fn open_reopen() {
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(is_fresh);
            let tasks = db.load_tasks().unwrap();
            assert_eq!(tasks.len(), 0);
        }
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(!is_fresh);
            let tasks = db.load_tasks().unwrap();
            assert_eq!(tasks.len(), 0);
        }
    }

    // Verify putting a single task into a fresh db, closing it and reopening it, and getting it out
    #[test]
    fn save_load() {
        let task_id = 0;
        let so = ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        };

        let task = Task::new(
            task_id,
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            TaskStart::StartEval {
                player: SYSTEM_OBJECT,
                program: Default::default(),
                initial_env: None,
            },
            &so,
            Arc::new(TaskControl::new()),
        );

        // Mock task...
        let suspended = SuspendedTask {
            enqueued_at: Timestamp::now(),
            wake_condition: WakeCondition::Never,
            task,
            session: Arc::new(NoopClientSession::new()),
            result_sender: None,
            timer_generation: 0,
        };
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();

        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(is_fresh);
            db.save_task(&suspended).unwrap();
            let tasks = db.load_tasks().unwrap();
            assert_eq!(tasks.len(), 1);
            assert_eq!(tasks[0].task.task_id, task_id);
        }

        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(!is_fresh);
            let tasks = db.load_tasks().unwrap();
            assert_eq!(tasks.len(), 1);
            assert_eq!(tasks[0].task.task_id, task_id);
        }
    }

    // Create a series of tasks, save them, load them, and verify they are the same.
    #[test]
    fn save_load_multiple() {
        let mut tasks = vec![];
        for task_id in 0..50 {
            let so = ServerOptions {
                bg_seconds: 0.0,
                bg_ticks: 0,
                fg_seconds: 0.0,
                fg_ticks: 0,
                max_stack_depth: 0,
                dump_interval: None,
                gc_interval: None,
                max_task_retries: DEFAULT_MAX_TASK_RETRIES,
                max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
                db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
                db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
                rollback_on_task_limit: false,
            };

            let task = Task::new(
                task_id,
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                TaskStart::StartEval {
                    player: SYSTEM_OBJECT,
                    program: Default::default(),
                    initial_env: None,
                },
                &so,
                Arc::new(TaskControl::new()),
            );

            // Mock task...
            let suspended = SuspendedTask {
                enqueued_at: Timestamp::now(),
                wake_condition: WakeCondition::Never,
                task,
                session: Arc::new(NoopClientSession::new()),
                result_sender: None,
                timer_generation: 0,
            };
            tasks.push(suspended);
        }

        // Write em
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(is_fresh);
            for task in tasks.iter() {
                db.save_task(task).unwrap();
            }
        }

        // Load em
        let (db, is_fresh) = FjallTasksDB::open(path);
        assert!(!is_fresh);
        let loaded_tasks = db.load_tasks().unwrap();
        assert_eq!(loaded_tasks.len(), tasks.len());
        for (task, loaded_task) in tasks.iter().zip(loaded_tasks.iter()) {
            assert_eq!(task.task.task_id, loaded_task.task.task_id);
        }
    }

    // Create a series of tasks, save them, delete a few, and load verify the rest are there and
    // the deleted are not.
    #[test]
    fn save_delete_load_multiple() {
        let mut tasks = vec![];
        for task_id in 0..50 {
            let so = ServerOptions {
                bg_seconds: 0.0,
                bg_ticks: 0,
                fg_seconds: 0.0,
                fg_ticks: 0,
                max_stack_depth: 0,
                dump_interval: None,
                gc_interval: None,
                max_task_retries: DEFAULT_MAX_TASK_RETRIES,
                max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
                db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
                db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
                rollback_on_task_limit: false,
            };

            let task = Task::new(
                task_id,
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                TaskStart::StartEval {
                    player: SYSTEM_OBJECT,
                    program: Default::default(),
                    initial_env: None,
                },
                &so,
                Arc::new(TaskControl::new()),
            );

            // Mock task...
            let suspended = SuspendedTask {
                enqueued_at: Timestamp::now(),
                wake_condition: WakeCondition::Never,
                task,
                session: Arc::new(NoopClientSession::new()),
                result_sender: None,
                timer_generation: 0,
            };
            tasks.push(suspended);
        }

        // Write em
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(is_fresh);
            for task in tasks.iter() {
                db.save_task(task).unwrap();
            }
        }

        {
            // Delete some
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(!is_fresh);
            for task_id in 0..50 {
                if task_id % 2 == 0 {
                    db.delete_task(task_id).unwrap();
                }
            }
        }

        // Load em
        let (db, is_fresh) = FjallTasksDB::open(path);
        assert!(!is_fresh);
        let loaded_tasks = db.load_tasks().unwrap();
        assert_eq!(loaded_tasks.len(), 25);

        // Go through the loaded tasks and make sure the deleted ones are not there.
        for task in loaded_tasks.iter() {
            assert!(task.task.task_id % 2 != 0);
        }
    }

    // Test time-based wake conditions across save/load cycles
    #[test]
    fn test_time_wake_conditions() {
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();

        let so = ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        };

        // Create tasks with various time-based wake conditions
        let now = Instant::now();
        let input_uuid = Uuid::new_v4();

        let mut tasks = vec![];
        let test_cases = [
            ("future_5s", 0),
            ("future_1min", 1),
            ("future_1hr", 2),
            ("past_1s", 3),
            ("never", 4),
            ("input", 5),
            ("immediate", 6),
        ];

        for (name, i) in test_cases.iter() {
            let wake_condition = match *i {
                0 => WakeCondition::Time(now + Duration::from_secs(5)),
                1 => WakeCondition::Time(now + Duration::from_secs(60)),
                2 => WakeCondition::Time(now + Duration::from_secs(3600)),
                3 => WakeCondition::Time(now.checked_sub(Duration::from_secs(1)).unwrap_or(now)),
                4 => WakeCondition::Never,
                5 => WakeCondition::Input(input_uuid),
                6 => WakeCondition::Immediate(Some(v_int(0))),
                _ => unreachable!(),
            };

            let task = Task::new(
                *i,
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                TaskStart::StartEval {
                    player: SYSTEM_OBJECT,
                    program: Default::default(),
                    initial_env: None,
                },
                &so,
                Arc::new(TaskControl::new()),
            );

            let suspended = SuspendedTask {
                enqueued_at: Timestamp::now(),
                wake_condition,
                task,
                session: Arc::new(NoopClientSession::new()),
                result_sender: None,
                timer_generation: 0,
            };
            tasks.push((*name, suspended));
        }

        // Save all tasks
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(is_fresh);
            for (_, task) in &tasks {
                db.save_task(task).unwrap();
            }
        }

        // Load and verify
        {
            let (db, is_fresh) = FjallTasksDB::open(path);
            assert!(!is_fresh);
            let loaded_tasks = db.load_tasks().unwrap();
            assert_eq!(loaded_tasks.len(), tasks.len());

            // Verify each task type was preserved correctly
            for (original_name, original_task) in &tasks {
                let loaded_task = loaded_tasks
                    .iter()
                    .find(|t| t.task.task_id == original_task.task.task_id)
                    .unwrap_or_else(|| panic!("Could not find loaded task for {original_name}"));

                match (&original_task.wake_condition, &loaded_task.wake_condition) {
                    (WakeCondition::Time(original), WakeCondition::Time(loaded)) => {
                        assert!(
                            deadline_difference(*original, *loaded) < Duration::from_secs(1),
                            "Deadline changed for {original_name}: {original:?} -> {loaded:?}"
                        );
                    }
                    (WakeCondition::Never, WakeCondition::Never) => {}
                    (WakeCondition::Input(uuid1), WakeCondition::Input(uuid2)) => {
                        assert_eq!(uuid1, uuid2, "Input UUID mismatch for {original_name}");
                    }
                    (WakeCondition::Immediate(_), WakeCondition::Immediate(_)) => {}
                    _ => panic!(
                        "Wake condition type mismatch for {}: {:?} vs {:?}",
                        original_name, original_task.wake_condition, loaded_task.wake_condition
                    ),
                }
            }
        }
    }

    // Test edge cases for time serialization
    #[test]
    fn test_time_edge_cases() {
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let _path = tmpdir.path();

        let so = ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        };

        let now = Instant::now();

        // Test various edge cases
        let edge_cases = [
            now + Duration::from_secs(86400 * 365), // 1 year
            // Very near future
            now + Duration::from_millis(1),
            // Past times (if supported by the system)
            now.checked_sub(Duration::from_millis(1)).unwrap_or(now),
            now.checked_sub(Duration::from_secs(60)).unwrap_or(now),
        ];

        for (i, wake_time) in edge_cases.iter().enumerate() {
            let task = Task::new(
                i,
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                TaskStart::StartEval {
                    player: SYSTEM_OBJECT,
                    program: Default::default(),
                    initial_env: None,
                },
                &so,
                Arc::new(TaskControl::new()),
            );

            let suspended = SuspendedTask {
                enqueued_at: Timestamp::now(),
                wake_condition: WakeCondition::Time(*wake_time),
                task,
                session: Arc::new(NoopClientSession::new()),
                result_sender: None,
                timer_generation: 0,
            };

            // Test save/load cycle for this edge case
            let (db, _) = FjallTasksDB::open(&tmpdir.path().join(format!("edge_case_{i}")));

            // Should not panic during save
            db.save_task(&suspended)
                .unwrap_or_else(|_| panic!("Failed to save edge case {i}"));

            // Should not panic during load
            let loaded_tasks = db
                .load_tasks()
                .unwrap_or_else(|_| panic!("Failed to load edge case {i}"));
            assert_eq!(loaded_tasks.len(), 1);

            // The conversion through wall-clock time should preserve the deadline.
            match &loaded_tasks[0].wake_condition {
                WakeCondition::Time(loaded) => assert!(
                    deadline_difference(*wake_time, *loaded) < Duration::from_secs(1),
                    "Deadline changed for edge case {i}: {wake_time:?} -> {loaded:?}"
                ),
                other => panic!("Edge case {i} changed wake condition type to {other:?}"),
            }
        }
    }

    // Test that reopening the database preserves a future deadline.
    #[test]
    fn test_future_deadline_after_reopen() {
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();

        let so = ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        };

        // Create a task with a future wake time
        let task = Task::new(
            999,
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            TaskStart::StartEval {
                player: SYSTEM_OBJECT,
                program: Default::default(),
                initial_env: None,
            },
            &so,
            Arc::new(TaskControl::new()),
        );

        let wake_time = Deadline::from_now(Duration::from_secs(30)).instant();
        let suspended = SuspendedTask {
            enqueued_at: Timestamp::now(),
            wake_condition: WakeCondition::Time(wake_time),
            task,
            session: Arc::new(NoopClientSession::new()),
            result_sender: None,
            timer_generation: 0,
        };

        // Save the task
        {
            let (db, _) = FjallTasksDB::open(path);
            db.save_task(&suspended).unwrap();
        }

        // Load the task from the reopened database.
        {
            let (db, _) = FjallTasksDB::open(path);
            let loaded_tasks = db.load_tasks().unwrap();
            assert_eq!(loaded_tasks.len(), 1);

            // Verify both the wake condition and the restored deadline.
            match &loaded_tasks[0].wake_condition {
                WakeCondition::Time(loaded) => assert!(
                    deadline_difference(wake_time, *loaded) < Duration::from_secs(1),
                    "Future deadline changed: {wake_time:?} -> {loaded:?}"
                ),
                other => panic!("Expected a time wake condition, got {other:?}"),
            }
        }
    }

    /// A schedule survives save/reopen/load with every persisted field
    /// intact, including the id (K2: ids are stable across restart).
    #[test]
    fn schedule_round_trip() {
        let tmpdir = tempfile::tempdir().expect("Unable to create temporary directory");
        let path = tmpdir.path();
        // Whole seconds so the nanos round-trip is exact.
        let t0 = UNIX_EPOCH + Duration::from_secs(1_800_000_000);
        let next = t0 + Duration::from_secs(90);
        let last = t0 + Duration::from_secs(30);
        let options = ScheduleOptions {
            adaptive: true,
            catchup: CatchupPolicy::Once,
            overlap: OverlapPolicy::Queue,
            jitter: Duration::from_millis(250),
            max_faults: Some(7),
            pass_elapsed: false,
            state: Some(v_str("opaque")),
            persist: true,
            player: Some(Obj::mk_id(77)),
        };
        let entry = ScheduleEntry::from_persisted(
            42,
            Obj::mk_id(6),
            Symbol::mk("drive"),
            List::mk_list(&[v_int(1), v_str("two")]),
            Obj::mk_id(36),
            Obj::mk_id(36),
            ScheduleKind::Every {
                interval: Duration::from_secs(60),
            },
            options,
            t0,
            Some(next),
            Some(next),
            Some(last),
            5,
            2,
            1,
            3,
            4,
            false,
        );

        {
            let (db, _) = FjallTasksDB::open(path);
            db.save_schedule(&entry).unwrap();
            assert_eq!(db.load_schedules().unwrap().len(), 1);
        }
        {
            let (db, _) = FjallTasksDB::open(path);
            let loaded = db.load_schedules().unwrap();
            assert_eq!(loaded.len(), 1);
            let l = &loaded[0];
            assert_eq!(l.id, 42);
            assert_eq!(l.target, Obj::mk_id(6));
            assert_eq!(l.verb, Symbol::mk("drive"));
            assert_eq!(l.args, List::mk_list(&[v_int(1), v_str("two")]));
            assert_eq!(l.authority_principal, Obj::mk_id(36));
            assert_eq!(l.owner, Obj::mk_id(36));
            assert!(matches!(
                l.kind,
                ScheduleKind::Every { interval } if interval == Duration::from_secs(60)
            ));
            assert!(l.options.adaptive);
            assert_eq!(l.options.catchup, CatchupPolicy::Once);
            assert_eq!(l.options.overlap, OverlapPolicy::Queue);
            assert_eq!(l.options.jitter, Duration::from_millis(250));
            assert_eq!(l.options.max_faults, Some(7));
            assert!(!l.options.pass_elapsed);
            assert_eq!(l.options.state, Some(v_str("opaque")));
            assert_eq!(l.options.player, Some(Obj::mk_id(77)));
            assert_eq!(l.created_at, t0);
            assert_eq!(l.next_run, Some(next));
            assert_eq!(l.scheduled_deadline, Some(next));
            assert_eq!(l.last_run, Some(last));
            assert_eq!(l.run_count, 5);
            assert_eq!(l.fault_count, 2);
            assert_eq!(l.consecutive_faults, 1);
            assert_eq!(l.missed_count, 3);
            assert_eq!(l.overlap_count, 4);
            assert!(l.running_task.is_none());

            db.delete_schedule(42).unwrap();
            assert!(db.load_schedules().unwrap().is_empty());
        }
    }
}
