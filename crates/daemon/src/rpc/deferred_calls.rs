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

//! Calls waiting for their tasks, without an RPC worker waiting too.
//!
//! A worker submits the task, adds a call here, and takes its next job. `TaskMonitor` reports what
//! the task does, and a sweep thread cancels tasks past their deadlines. Every outcome goes through
//! [`DeferredCalls::finish`], and removing the call from the map is what decides which outcome wins,
//! so each call gets exactly one reply however these race.
//!
//! Only the monitor reads a task's result channel. It takes a result off the channel before it reports
//! it, so an empty channel does not mean there is no result, and the sweep must not act as if it did.

use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use flume::{Receiver, Sender};
use moor_common::tasks::{SchedulerError, TaskId};
use moor_kernel::{
    SchedulerClient,
    tasks::{AbortTaskOutcome, TaskNotification},
};
use moor_runtime_api::{
    RpcMessageError,
    api::{ClientReply, InvocationOutcome, InvocationResponse},
};
use tracing::{debug, error, warn};

use super::output_capture_session::CaptureAccumulator;

/// How often the sweep looks for calls past their deadlines.
const SWEEP_INTERVAL: Duration = Duration::from_millis(50);
/// The shortest wait for the scheduler to answer an abort, even for a call already out of time.
const MIN_ABORT_WAIT: Duration = Duration::from_millis(100);

type TaskResult = Result<TaskNotification, SchedulerError>;
type FinishJob = Box<dyn FnOnce() + Send>;

/// Builds and delivers a call's reply from how it ended. It runs on the finish thread, so it must
/// not call the scheduler.
pub(crate) type OnFinish = Box<dyn FnOnce(Finish) + Send>;

/// Work that may block on the scheduler, which an RPC worker runs.
pub type WorkerJob = Box<dyn FnOnce() + Send>;
/// Queues a job for an RPC worker.
pub type RunOnWorker = Arc<dyn Fn(WorkerJob) + Send + Sync>;

/// What a request needs to reply later.
pub(crate) struct DeferredContext {
    pub(crate) scheduler_client: SchedulerClient,
    pub(crate) sink: ClientReplySink,
    pub(crate) run_on_worker: RunOnWorker,
}

/// Delivers a call's one reply. It may run on any thread.
pub(crate) type ClientReplySink = Box<dyn FnOnce(Result<ClientReply, RpcMessageError>) + Send>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Phase {
    Running,
    /// The sweep is asking the scheduler to cancel. If the task's result channel closes now, the
    /// abort's answer decides the reply, because cancelling a task can drop its channel.
    Aborting,
    /// The task has claimed its final commit, so its real result is on the way.
    Completing,
}

/// How a call ended.
#[derive(Debug)]
pub(crate) enum Finish {
    Result(TaskResult),
    TimedOut,
    Failed(SchedulerError),
    ResultLost,
}

struct DeferredCall {
    /// When to ask the scheduler to cancel the task.
    execution_expires_at: Instant,
    /// The end of the whole deadline, including cancellation.
    expires_at: Instant,
    on_finish: OnFinish,
    phase: Phase,
    /// The monitor reported the result channel closing while an abort was in progress.
    channel_closed: bool,
    _slot: Arc<CallSlot>,
}

/// The parts of a call that the sweep works on without holding the lock.
struct DueCall {
    task_id: TaskId,
    expires_at: Instant,
}

pub(crate) struct NewDeferredCall {
    pub(crate) task_id: TaskId,
    pub(crate) execution_expires_at: Instant,
    pub(crate) expires_at: Instant,
    pub(crate) on_finish: OnFinish,
    pub(crate) slot: Arc<CallSlot>,
}

/// Capacity for one call. It is released when the last reference drops, after the reply has been
/// sent. A login's remaining steps hold a reference too.
pub(crate) struct CallSlot(Arc<AtomicUsize>);

impl Drop for CallSlot {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}

pub struct DeferredCalls {
    /// When a refusal was last logged, in seconds, so a flood of refusals logs a line a second.
    last_refusal_logged: AtomicU64,
    calls: Mutex<HashMap<TaskId, DeferredCall>>,
    /// Capacity for calls made with credentials.
    calls_in_use: Arc<AtomicUsize>,
    max_calls: usize,
    /// Capacity for logins and the welcome message, which anyone can trigger without credentials.
    /// This is separate so they cannot crowd out other calls.
    logins_in_use: Arc<AtomicUsize>,
    max_logins: usize,
    finish_jobs: Sender<FinishJob>,
    finish_receiver: Receiver<FinishJob>,
}

impl DeferredCalls {
    pub fn new(max_calls: usize, max_logins: usize) -> Arc<Self> {
        let (finish_jobs, finish_receiver) = flume::unbounded();
        Arc::new(Self {
            last_refusal_logged: AtomicU64::new(0),
            calls: Mutex::new(HashMap::new()),
            calls_in_use: Arc::new(AtomicUsize::new(0)),
            max_calls,
            logins_in_use: Arc::new(AtomicUsize::new(0)),
            max_logins,
            finish_jobs,
            finish_receiver,
        })
    }

    /// Take capacity for a call about to start, or return `None` if there is none left.
    pub(crate) fn try_reserve(&self) -> Option<Arc<CallSlot>> {
        self.reserve_from(&self.calls_in_use, self.max_calls)
    }

    /// Take capacity for a login or welcome message about to start.
    pub(crate) fn try_reserve_login(&self) -> Option<Arc<CallSlot>> {
        self.reserve_from(&self.logins_in_use, self.max_logins)
    }

    fn reserve_from(&self, in_use: &Arc<AtomicUsize>, limit: usize) -> Option<Arc<CallSlot>> {
        let slot = CallSlot(in_use.clone());
        let used = in_use.fetch_add(1, Ordering::AcqRel);
        // Over the limit, dropping the slot takes back the count just added.
        if used < limit {
            return Some(Arc::new(slot));
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_secs());
        if self.last_refusal_logged.swap(now, Ordering::Relaxed) != now {
            warn!(limit, "Refusing deferred calls: too many are waiting");
        }
        None
    }

    pub(crate) fn add(&self, call: NewDeferredCall) {
        self.calls.lock().unwrap().insert(
            call.task_id,
            DeferredCall {
                execution_expires_at: call.execution_expires_at,
                expires_at: call.expires_at,
                on_finish: call.on_finish,
                phase: Phase::Running,
                channel_closed: false,
                _slot: call.slot,
            },
        );
    }

    /// Report a message from the task's result channel.
    pub(crate) fn task_result(&self, task_id: TaskId, result: TaskResult) {
        if !matches!(result, Ok(TaskNotification::Suspended)) {
            self.finish(task_id, Finish::Result(result));
        }
    }

    /// Report that the task's result channel closed with no result still to come.
    pub(crate) fn result_channel_closed(&self, task_id: TaskId) {
        {
            let mut calls = self.calls.lock().unwrap();
            let Some(call) = calls.get_mut(&task_id) else {
                return;
            };
            // Cancelling a task can drop its channel, so leave the reply to the abort's answer.
            if call.phase == Phase::Aborting {
                call.channel_closed = true;
                return;
            }
        }
        self.finish(task_id, Finish::ResultLost);
    }

    /// End a call, if nothing has yet. The reply is built on the finish thread: captured output and
    /// results can be large, and the callers must not be held up.
    fn finish(&self, task_id: TaskId, finish: Finish) {
        let Some(call) = self.calls.lock().unwrap().remove(&task_id) else {
            debug!(task_id, ?finish, "Deferred call has already finished");
            return;
        };
        // The finish thread stops at shutdown, when hosts stop waiting for replies too.
        let _ = self
            .finish_jobs
            .send(Box::new(move || call.deliver(finish)));
    }

    /// Mark every call past its execution deadline as being aborted, and return them.
    fn take_due_calls(&self, now: Instant) -> Vec<DueCall> {
        let mut calls = self.calls.lock().unwrap();
        calls
            .iter_mut()
            .filter(|(_, call)| call.phase == Phase::Running && now >= call.execution_expires_at)
            .map(|(task_id, call)| {
                call.phase = Phase::Aborting;
                DueCall {
                    task_id: *task_id,
                    expires_at: call.expires_at,
                }
            })
            .collect()
    }

    /// Leave a call waiting for its result from the monitor. Returns true if no result can come,
    /// because the channel has already closed.
    fn wait_for_result(&self, task_id: TaskId) -> bool {
        let mut calls = self.calls.lock().unwrap();
        let Some(call) = calls.get_mut(&task_id) else {
            return false;
        };
        call.phase = Phase::Completing;
        call.channel_closed
    }

    /// Act on the scheduler's answer to an abort.
    fn abort_answered(&self, due: &DueCall, answer: Result<AbortTaskOutcome, SchedulerError>) {
        let task_id = due.task_id;
        match answer {
            Ok(AbortTaskOutcome::Cancelled) => self.finish(task_id, Finish::TimedOut),
            // The task is finishing, or has finished and the monitor may be holding its result, so
            // that result is what the caller gets. Only a closed channel means there isn't one.
            Ok(AbortTaskOutcome::Completing) => {
                if self.wait_for_result(task_id) {
                    self.finish(task_id, Finish::ResultLost);
                }
            }
            Ok(AbortTaskOutcome::NotFound) => {
                if self.wait_for_result(task_id) {
                    error!(
                        task_id,
                        "Scheduler could not determine captured task outcome"
                    );
                    self.finish(
                        task_id,
                        Finish::Failed(SchedulerError::TaskNotFound(task_id)),
                    );
                }
            }
            Err(error) => {
                error!(
                    task_id,
                    ?error,
                    "Captured task cancellation was not acknowledged"
                );
                self.finish(task_id, Finish::Failed(error));
            }
        }
    }

    fn sweep_once(&self, scheduler_client: &SchedulerClient) {
        for due in self.take_due_calls(Instant::now()) {
            let wait = due
                .expires_at
                .saturating_duration_since(Instant::now())
                .max(MIN_ABORT_WAIT);
            let answer = scheduler_client.abort_task_with_timeout(due.task_id, wait);
            self.abort_answered(&due, answer);
        }
    }

    /// Cancel tasks past their deadlines until shutdown.
    ///
    /// Aborts can wait on a stalled scheduler, so this has its own thread and does not build replies.
    pub fn run_sweep(&self, scheduler_client: SchedulerClient, kill_switch: Arc<AtomicBool>) {
        while !kill_switch.load(Ordering::Relaxed) {
            self.sweep_once(&scheduler_client);
            std::thread::sleep(SWEEP_INTERVAL);
        }
    }

    /// Build and send finished calls' replies until shutdown.
    pub fn run_finisher(&self, kill_switch: Arc<AtomicBool>) {
        while !kill_switch.load(Ordering::Relaxed) {
            if let Ok(job) = self.finish_receiver.recv_timeout(Duration::from_secs(1)) {
                job();
            }
        }
    }
}

impl DeferredCall {
    fn deliver(self, finish: Finish) {
        // The slot is held until this returns, so it covers building and sending the reply.
        (self.on_finish)(finish);
    }
}

/// When to ask for cancellation, and the end of the whole deadline, leaving time for the abort.
pub(crate) fn deadline_instants(deadline: Duration) -> (Instant, Instant) {
    let expires_at = Instant::now() + deadline;
    let cancellation_reserve = (deadline / 10).min(Duration::from_millis(100));
    (expires_at - cancellation_reserve, expires_at)
}

/// Finish a captured invocation by replying with its result and committed output.
pub(crate) fn capture_on_finish(
    deadline: Duration,
    output: Option<Arc<CaptureAccumulator>>,
    to_reply: fn(InvocationResponse) -> ClientReply,
    sink: ClientReplySink,
) -> OnFinish {
    Box::new(move |finish| {
        let take_output = || {
            output
                .as_ref()
                .map(|output| output.take())
                .unwrap_or_default()
                .into_iter()
                .map(|(_, event)| *event)
                .collect::<Vec<_>>()
        };
        let response = match finish {
            Finish::Result(result) => capture_result_response(result, take_output),
            Finish::TimedOut => capture_timeout_response(deadline, take_output()),
            Finish::Failed(error) => InvocationResponse {
                outcome: InvocationOutcome::Error { error },
                output: take_output(),
            },
            Finish::ResultLost => {
                sink(Err(result_lost_error()));
                return;
            }
        };
        sink(Ok(to_reply(response)));
    })
}

/// Finish a call that replies with its task's value, or with the task's error.
pub(crate) fn task_on_finish(
    deadline: Duration,
    to_reply: impl FnOnce(moor_var::Var) -> Result<ClientReply, RpcMessageError> + Send + 'static,
    sink: ClientReplySink,
) -> OnFinish {
    Box::new(move |finish| {
        sink(match finish {
            Finish::Result(Ok(TaskNotification::Result(result))) => to_reply(result),
            Finish::Result(Ok(TaskNotification::Suspended)) => {
                Err(RpcMessageError::TaskError(SchedulerError::TaskAbortedError))
            }
            Finish::Result(Err(error)) | Finish::Failed(error) => {
                Err(RpcMessageError::TaskError(error))
            }
            Finish::TimedOut => Err(RpcMessageError::TaskError(
                SchedulerError::TaskAbortedLimit(moor_common::tasks::AbortLimitReason::Time(
                    deadline,
                )),
            )),
            Finish::ResultLost => Err(result_lost_error()),
        });
    })
}

fn result_lost_error() -> RpcMessageError {
    RpcMessageError::InternalError("Task ended without a result".to_string())
}

pub(crate) fn capture_timeout_response(
    deadline: Duration,
    output: Vec<moor_common::tasks::NarrativeEvent>,
) -> InvocationResponse {
    InvocationResponse {
        outcome: InvocationOutcome::Error {
            error: SchedulerError::TaskAbortedLimit(moor_common::tasks::AbortLimitReason::Time(
                deadline,
            )),
        },
        output,
    }
}

pub(crate) fn capture_result_response(
    result: TaskResult,
    take_output: impl FnOnce() -> Vec<moor_common::tasks::NarrativeEvent>,
) -> InvocationResponse {
    let outcome = match result {
        Ok(TaskNotification::Result(result)) => InvocationOutcome::Success { result },
        Ok(TaskNotification::Suspended) => InvocationOutcome::Error {
            error: SchedulerError::TaskAbortedError,
        },
        Err(error) => InvocationOutcome::Error { error },
    };
    InvocationResponse {
        outcome,
        output: take_output(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::v_int;

    type Replies = flume::Receiver<Result<ClientReply, RpcMessageError>>;

    struct Harness {
        calls: Arc<DeferredCalls>,
        replies: Replies,
    }

    const TASK: TaskId = 7;

    fn invocation_reply(response: InvocationResponse) -> ClientReply {
        ClientReply::InvocationResponse { response }
    }

    fn harness() -> Harness {
        let calls = DeferredCalls::new(10, 2);
        let (reply_send, replies) = flume::unbounded();
        let now = Instant::now();
        calls.add(NewDeferredCall {
            task_id: TASK,
            execution_expires_at: now,
            expires_at: now + Duration::from_secs(1),
            on_finish: capture_on_finish(
                Duration::from_secs(1),
                None,
                invocation_reply,
                Box::new(move |reply| {
                    reply_send.send(reply).unwrap();
                }),
            ),
            slot: calls.try_reserve().unwrap(),
        });
        Harness { calls, replies }
    }

    impl Harness {
        fn run_finish_jobs(&self) {
            while let Ok(job) = self.calls.finish_receiver.try_recv() {
                job();
            }
        }

        fn due(&self) -> DueCall {
            DueCall {
                task_id: TASK,
                expires_at: Instant::now(),
            }
        }

        fn only_reply(&self) -> Result<ClientReply, RpcMessageError> {
            self.run_finish_jobs();
            let reply = self.replies.try_recv().expect("a reply");
            assert!(self.replies.try_recv().is_err(), "a second reply");
            reply
        }

        fn outcome(&self) -> InvocationOutcome {
            match self.only_reply() {
                Ok(ClientReply::InvocationResponse { response }) => response.outcome,
                other => panic!("unexpected reply: {other:?}"),
            }
        }
    }

    #[test]
    fn a_result_replies_once_however_many_outcomes_arrive() {
        let harness = harness();
        harness
            .calls
            .task_result(TASK, Ok(TaskNotification::Result(v_int(1))));
        harness
            .calls
            .task_result(TASK, Ok(TaskNotification::Result(v_int(2))));
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Cancelled));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Success { result } if result == v_int(1)
        ));
    }

    #[test]
    fn suspending_does_not_end_the_call() {
        let harness = harness();
        harness
            .calls
            .task_result(TASK, Ok(TaskNotification::Suspended));
        harness.run_finish_jobs();
        assert!(harness.replies.try_recv().is_err());
    }

    #[test]
    fn a_closed_channel_with_no_abort_reports_a_lost_result() {
        let harness = harness();
        harness.calls.result_channel_closed(TASK);
        assert!(harness.only_reply().is_err());
    }

    #[test]
    fn cancelling_can_close_the_channel_before_the_abort_answers() {
        let harness = harness();
        assert_eq!(harness.calls.take_due_calls(Instant::now()).len(), 1);

        harness.calls.result_channel_closed(TASK);
        harness.run_finish_jobs();
        assert!(
            harness.replies.try_recv().is_err(),
            "the abort should decide"
        );

        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Cancelled));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Error {
                error: SchedulerError::TaskAbortedLimit(_)
            }
        ));
    }

    #[test]
    fn a_completing_task_keeps_waiting_for_its_real_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Completing));
        harness.run_finish_jobs();
        assert!(harness.replies.try_recv().is_err());

        harness
            .calls
            .task_result(TASK, Ok(TaskNotification::Result(v_int(3))));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Success { result } if result == v_int(3)
        ));
    }

    /// The monitor takes a result off the channel before reporting it, so the abort can find
    /// nothing to cancel while the real result is on its way.
    #[test]
    fn a_result_in_flight_when_the_abort_finds_nothing_is_still_delivered() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::NotFound));
        harness.run_finish_jobs();
        assert!(harness.replies.try_recv().is_err(), "no result has arrived");

        harness
            .calls
            .task_result(TASK, Ok(TaskNotification::Result(v_int(42))));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Success { result } if result == v_int(42)
        ));
    }

    #[test]
    fn nothing_to_cancel_and_a_closed_channel_is_an_error() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::NotFound));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Error {
                error: SchedulerError::TaskNotFound(TASK)
            }
        ));
    }

    #[test]
    fn nothing_to_cancel_then_the_channel_closing_is_an_error() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::NotFound));
        harness.calls.result_channel_closed(TASK);
        assert!(harness.only_reply().is_err());
    }

    #[test]
    fn a_completing_task_whose_channel_already_closed_reports_a_lost_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Completing));
        assert!(harness.only_reply().is_err());
    }

    #[test]
    fn a_failed_abort_reports_the_error() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Err(SchedulerError::SchedulerNotResponding));
        assert!(matches!(
            harness.outcome(),
            InvocationOutcome::Error {
                error: SchedulerError::SchedulerNotResponding
            }
        ));
    }

    #[test]
    fn a_slot_is_refused_at_the_limit_and_freed_after_the_reply() {
        let harness = harness();
        let calls = &harness.calls;
        let held: Vec<_> = (0..9).map(|_| calls.try_reserve().unwrap()).collect();
        assert!(
            calls.try_reserve().is_none(),
            "the harness's call holds one"
        );

        calls.task_result(TASK, Ok(TaskNotification::Result(v_int(1))));
        assert!(calls.try_reserve().is_none(), "the reply has not been sent");

        harness.run_finish_jobs();
        assert!(calls.try_reserve().is_some());
        drop(held);
    }

    #[test]
    fn logins_have_their_own_capacity() {
        let calls = DeferredCalls::new(1, 2);
        let call = calls.try_reserve().unwrap();
        assert!(calls.try_reserve().is_none());

        let first = calls.try_reserve_login().unwrap();
        let second = calls.try_reserve_login().unwrap();
        assert!(calls.try_reserve_login().is_none());
        assert!(calls.try_reserve().is_none());

        drop(first);
        assert!(calls.try_reserve_login().is_some());
        drop((call, second));
    }

    #[test]
    fn a_task_call_reports_each_ending() {
        let finish = |finish| {
            let (send, receive) = flume::unbounded();
            let on_finish = task_on_finish(
                Duration::from_secs(1),
                |result| Ok(ClientReply::EvalResult { result }),
                Box::new(move |reply| send.send(reply).unwrap()),
            );
            on_finish(finish);
            receive.try_recv().unwrap()
        };
        assert!(matches!(
            finish(Finish::Result(Ok(TaskNotification::Result(v_int(1))))),
            Ok(ClientReply::EvalResult { .. })
        ));
        assert!(matches!(
            finish(Finish::TimedOut),
            Err(RpcMessageError::TaskError(
                SchedulerError::TaskAbortedLimit(_)
            ))
        ));
        assert!(matches!(
            finish(Finish::Failed(SchedulerError::SchedulerNotResponding)),
            Err(RpcMessageError::TaskError(
                SchedulerError::SchedulerNotResponding
            ))
        ));
        assert!(matches!(
            finish(Finish::ResultLost),
            Err(RpcMessageError::InternalError(_))
        ));
    }

    #[test]
    fn calls_before_their_deadline_are_not_due() {
        let calls = DeferredCalls::new(10, 2);
        let now = Instant::now();
        calls.add(NewDeferredCall {
            task_id: TASK,
            execution_expires_at: now + Duration::from_secs(60),
            expires_at: now + Duration::from_secs(61),
            on_finish: Box::new(|_| {}),
            slot: calls.try_reserve().unwrap(),
        });
        assert!(calls.take_due_calls(now).is_empty());
    }
}
