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
        Arc, LazyLock, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use fast_telemetry::{
    DeriveLabel, LabelEnum, LabeledCounter, MetricKind, MetricLabel, MetricLabels, MetricMeta,
    MetricVisitor,
};
use flume::{Receiver, Sender};
use moor_common::tasks::{AbortReason, Kept, SchedulerError, TaskEnding, TaskId, TaskOutcome};
use moor_kernel::{SchedulerClient, tasks::AbortTaskOutcome};
use moor_runtime_api::api::{ClientReply, InvocationResponse};
use tracing::{debug, error, warn};

use super::output_capture_session::CaptureAccumulator;
use crate::runtime::{ClientReplySink, RunOnWorker};

/// How often the sweep looks for calls past their deadlines.
const SWEEP_INTERVAL: Duration = Duration::from_millis(50);
/// The shortest wait for the scheduler to answer an abort, even for a call already out of time.
const MIN_ABORT_WAIT: Duration = Duration::from_millis(100);

type FinishJob = Box<dyn FnOnce() + Send>;

/// Builds and delivers a call's reply from how it ended. It runs on the finish thread, so it must
/// not call the scheduler.
pub(crate) type OnFinish = Box<dyn FnOnce(Finish) + Send>;

/// What a request needs to reply later.
pub(crate) struct DeferredContext {
    pub(crate) scheduler_client: SchedulerClient,
    pub(crate) sink: ClientReplySink,
    pub(crate) run_on_worker: RunOnWorker,
}

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
    /// The task reported this outcome.
    Outcome(TaskOutcome),
    /// The call's deadline passed, and cancelling the task won, so it did not commit.
    DeadlinePassed,
    /// The task's result will not arrive. `Kept` is what is known about its last transaction.
    ResultLost(Kept),
}

impl Finish {
    /// The outcome to report for a call with this deadline.
    pub(crate) fn into_outcome(self, deadline: Duration) -> TaskOutcome {
        match self {
            Finish::Outcome(outcome) => outcome,
            Finish::DeadlinePassed => {
                TaskOutcome::aborted(AbortReason::Deadline(deadline), Kept::No)
            }
            Finish::ResultLost(kept) => TaskOutcome::result_lost(kept),
        }
    }
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

/// Which limit a call counts against. Anyone can start logins and webhooks without credentials, so
/// they have limits of their own and cannot crowd out other calls, or each other.
#[derive(Clone, Copy, Debug, PartialEq, Eq, DeriveLabel)]
#[label_name = "pool"]
pub(crate) enum CallPool {
    Authenticated,
    Login,
    Webhook,
}

/// Calls refused because their pool was full. Hosts turn these into `ServerBusy`.
static REFUSED: LazyLock<LabeledCounter<CallPool>> = LazyLock::new(|| LabeledCounter::new(8));

/// The daemon's pools, registered by the first `DeferredCalls`, for the metrics visitor to read.
static POOLS: OnceLock<[(CallPool, Arc<AtomicUsize>, usize); 3]> = OnceLock::new();

const POOL_IN_USE: MetricMeta<'static> = MetricMeta {
    name: "call_pool_in_use",
    help: "Deferred calls holding a place in their pool",
    kind: MetricKind::Gauge,
    unit: None,
};
const POOL_LIMIT: MetricMeta<'static> = MetricMeta {
    name: "call_pool_limit",
    help: "Places in each deferred call pool",
    kind: MetricKind::Gauge,
    unit: None,
};
const POOL_REFUSED: MetricMeta<'static> = MetricMeta {
    name: "call_pool_refused",
    help: "Deferred calls refused because their pool was full",
    kind: MetricKind::Counter,
    unit: None,
};

/// Visit each call pool's places in use, its limit, and its refusals.
pub(crate) fn visit_call_pool_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    let Some(pools) = POOLS.get() else {
        return;
    };
    for (pool, in_use, limit) in pools {
        let label = MetricLabel {
            name: CallPool::LABEL_NAME,
            value: pool.variant_name(),
        };
        let labels = MetricLabels::one(label);
        visitor.gauge_i64(POOL_IN_USE, labels, in_use.load(Ordering::Relaxed) as i64);
        visitor.gauge_i64(POOL_LIMIT, labels, *limit as i64);
        visitor.counter(POOL_REFUSED, labels, REFUSED.get(*pool) as i64);
    }
}

pub struct DeferredCalls {
    /// When a refusal was last logged, in seconds, so a flood of refusals logs a line a second.
    last_refusal_logged: AtomicU64,
    calls: Mutex<HashMap<TaskId, DeferredCall>>,
    /// Capacity for calls made with credentials.
    calls_in_use: Arc<AtomicUsize>,
    max_calls: usize,
    /// Capacity for logins and the welcome message.
    logins_in_use: Arc<AtomicUsize>,
    max_logins: usize,
    /// Capacity for system handlers called without credentials, such as webhooks.
    webhooks_in_use: Arc<AtomicUsize>,
    max_webhooks: usize,
    finish_jobs: Sender<FinishJob>,
    finish_receiver: Receiver<FinishJob>,
}

impl DeferredCalls {
    pub fn new(max_calls: usize, max_logins: usize, max_webhooks: usize) -> Arc<Self> {
        let (finish_jobs, finish_receiver) = flume::unbounded();
        let calls = Self {
            last_refusal_logged: AtomicU64::new(0),
            calls: Mutex::new(HashMap::new()),
            calls_in_use: Arc::new(AtomicUsize::new(0)),
            max_calls,
            logins_in_use: Arc::new(AtomicUsize::new(0)),
            max_logins,
            webhooks_in_use: Arc::new(AtomicUsize::new(0)),
            max_webhooks,
            finish_jobs,
            finish_receiver,
        };
        // The daemon has one; later ones, in tests, are not exported.
        let _ = POOLS.set([
            (
                CallPool::Authenticated,
                calls.calls_in_use.clone(),
                max_calls,
            ),
            (CallPool::Login, calls.logins_in_use.clone(), max_logins),
            (
                CallPool::Webhook,
                calls.webhooks_in_use.clone(),
                max_webhooks,
            ),
        ]);
        Arc::new(calls)
    }

    /// Take capacity for a call about to start, or return `None` if there is none left.
    pub(crate) fn try_reserve(&self, pool: CallPool) -> Option<Arc<CallSlot>> {
        match pool {
            CallPool::Authenticated => self.reserve_from(pool, &self.calls_in_use, self.max_calls),
            CallPool::Login => self.reserve_from(pool, &self.logins_in_use, self.max_logins),
            CallPool::Webhook => self.reserve_from(pool, &self.webhooks_in_use, self.max_webhooks),
        }
    }

    fn reserve_from(
        &self,
        pool: CallPool,
        in_use: &Arc<AtomicUsize>,
        limit: usize,
    ) -> Option<Arc<CallSlot>> {
        let slot = CallSlot(in_use.clone());
        let used = in_use.fetch_add(1, Ordering::AcqRel);
        // Over the limit, dropping the slot takes back the count just added.
        if used < limit {
            return Some(Arc::new(slot));
        }
        REFUSED.inc(pool);
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
    pub(crate) fn task_result(&self, task_id: TaskId, outcome: TaskOutcome) {
        // A suspended task is still running; its call waits for the task's final outcome.
        if outcome.ending != TaskEnding::Suspended {
            self.finish(task_id, Finish::Outcome(outcome));
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
        self.finish(task_id, Finish::ResultLost(Kept::Unknown));
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
            Ok(AbortTaskOutcome::Cancelled) => self.finish(task_id, Finish::DeadlinePassed),
            // The task has committed, and is finishing or has finished; the monitor may be holding
            // its result, so that result is what the caller gets. Only a closed channel means
            // there isn't one.
            Ok(AbortTaskOutcome::Completing) => {
                if self.wait_for_result(task_id) {
                    self.finish(task_id, Finish::ResultLost(Kept::Yes));
                }
            }
            Ok(AbortTaskOutcome::NotFound) => {
                if self.wait_for_result(task_id) {
                    error!(
                        task_id,
                        "Scheduler could not determine captured task outcome"
                    );
                    self.finish(task_id, Finish::ResultLost(Kept::Unknown));
                }
            }
            Err(error) => {
                error!(
                    task_id,
                    ?error,
                    "Captured task cancellation was not acknowledged"
                );
                self.finish(task_id, Finish::ResultLost(Kept::Unknown));
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

/// Finish a captured invocation by replying with its outcome and committed output.
pub(crate) fn capture_on_finish(
    deadline: Duration,
    output: Option<Arc<CaptureAccumulator>>,
    sink: ClientReplySink,
) -> OnFinish {
    Box::new(move |finish| {
        let output = output
            .as_ref()
            .map(|output| output.take())
            .unwrap_or_default()
            .into_iter()
            .map(|(_, event)| *event)
            .collect();
        sink(Ok(invocation_reply(InvocationResponse {
            outcome: finish.into_outcome(deadline),
            output,
        })));
    })
}

/// Finish a call whose task's output went to the caller's connection, by replying with its outcome.
pub(crate) fn task_on_finish(deadline: Duration, sink: ClientReplySink) -> OnFinish {
    Box::new(move |finish| {
        sink(Ok(invocation_reply(InvocationResponse {
            outcome: finish.into_outcome(deadline),
            output: vec![],
        })));
    })
}

pub(crate) fn invocation_reply(response: InvocationResponse) -> ClientReply {
    ClientReply::InvocationResponse { response }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_runtime_api::RpcMessageError;
    use moor_var::v_int;

    type Replies = flume::Receiver<Result<ClientReply, RpcMessageError>>;

    struct Harness {
        calls: Arc<DeferredCalls>,
        replies: Replies,
    }

    const TASK: TaskId = 7;

    fn harness() -> Harness {
        let calls = DeferredCalls::new(10, 2, 2);
        let (reply_send, replies) = flume::unbounded();
        let now = Instant::now();
        calls.add(NewDeferredCall {
            task_id: TASK,
            execution_expires_at: now,
            expires_at: now + Duration::from_secs(1),
            on_finish: capture_on_finish(
                Duration::from_secs(1),
                None,
                Box::new(move |reply| {
                    reply_send.send(reply).unwrap();
                }),
            ),
            slot: calls.try_reserve(CallPool::Authenticated).unwrap(),
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

        fn outcome(&self) -> TaskOutcome {
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
            .task_result(TASK, TaskOutcome::completed(v_int(1)));
        harness
            .calls
            .task_result(TASK, TaskOutcome::completed(v_int(2)));
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Cancelled));
        assert_eq!(harness.outcome(), TaskOutcome::completed(v_int(1)));
    }

    #[test]
    fn suspending_does_not_end_the_call() {
        let harness = harness();
        harness.calls.task_result(TASK, TaskOutcome::suspended());
        harness.run_finish_jobs();
        assert!(harness.replies.try_recv().is_err());
    }

    #[test]
    fn a_closed_channel_with_no_abort_reports_a_lost_result() {
        let harness = harness();
        harness.calls.result_channel_closed(TASK);
        assert_eq!(harness.outcome(), TaskOutcome::result_lost(Kept::Unknown));
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
        assert_eq!(
            harness.outcome(),
            TaskOutcome::aborted(AbortReason::Deadline(Duration::from_secs(1)), Kept::No)
        );
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
            .task_result(TASK, TaskOutcome::completed(v_int(3)));
        assert_eq!(harness.outcome(), TaskOutcome::completed(v_int(3)));
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
            .task_result(TASK, TaskOutcome::completed(v_int(42)));
        assert_eq!(harness.outcome(), TaskOutcome::completed(v_int(42)));
    }

    #[test]
    fn nothing_to_cancel_and_a_closed_channel_is_a_lost_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::NotFound));
        assert_eq!(harness.outcome(), TaskOutcome::result_lost(Kept::Unknown));
    }

    #[test]
    fn nothing_to_cancel_then_the_channel_closing_is_a_lost_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::NotFound));
        harness.calls.result_channel_closed(TASK);
        assert_eq!(harness.outcome(), TaskOutcome::result_lost(Kept::Unknown));
    }

    #[test]
    fn a_completing_task_whose_channel_already_closed_reports_a_lost_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness.calls.result_channel_closed(TASK);
        harness
            .calls
            .abort_answered(&harness.due(), Ok(AbortTaskOutcome::Completing));
        // The task had committed.
        assert_eq!(harness.outcome(), TaskOutcome::result_lost(Kept::Yes));
    }

    #[test]
    fn a_failed_abort_reports_a_lost_result() {
        let harness = harness();
        harness.calls.take_due_calls(Instant::now());
        harness
            .calls
            .abort_answered(&harness.due(), Err(SchedulerError::SchedulerNotResponding));
        assert_eq!(harness.outcome(), TaskOutcome::result_lost(Kept::Unknown));
    }

    #[test]
    fn a_slot_is_refused_at_the_limit_and_freed_after_the_reply() {
        let harness = harness();
        let calls = &harness.calls;
        let held: Vec<_> = (0..9)
            .map(|_| calls.try_reserve(CallPool::Authenticated).unwrap())
            .collect();
        assert!(
            calls.try_reserve(CallPool::Authenticated).is_none(),
            "the harness's call holds one"
        );

        calls.task_result(TASK, TaskOutcome::completed(v_int(1)));
        assert!(
            calls.try_reserve(CallPool::Authenticated).is_none(),
            "the reply has not been sent"
        );

        harness.run_finish_jobs();
        assert!(calls.try_reserve(CallPool::Authenticated).is_some());
        drop(held);
    }

    #[test]
    fn each_pool_has_its_own_capacity() {
        let calls = DeferredCalls::new(1, 2, 1);
        let call = calls.try_reserve(CallPool::Authenticated).unwrap();
        assert!(calls.try_reserve(CallPool::Authenticated).is_none());

        let first_login = calls.try_reserve(CallPool::Login).unwrap();
        let second_login = calls.try_reserve(CallPool::Login).unwrap();
        assert!(calls.try_reserve(CallPool::Login).is_none());

        let webhook = calls.try_reserve(CallPool::Webhook).unwrap();
        assert!(calls.try_reserve(CallPool::Webhook).is_none());
        assert!(calls.try_reserve(CallPool::Authenticated).is_none());

        drop(first_login);
        assert!(calls.try_reserve(CallPool::Login).is_some());
        assert!(calls.try_reserve(CallPool::Webhook).is_none());
        drop((call, second_login, webhook));
    }

    #[test]
    fn a_task_call_reports_each_ending() {
        let finish = |finish| {
            let (send, receive) = flume::unbounded();
            let on_finish = task_on_finish(
                Duration::from_secs(1),
                Box::new(move |reply| send.send(reply).unwrap()),
            );
            on_finish(finish);
            match receive.try_recv().unwrap() {
                Ok(ClientReply::InvocationResponse { response }) => {
                    assert!(response.output.is_empty());
                    response.outcome
                }
                other => panic!("unexpected reply: {other:?}"),
            }
        };
        assert_eq!(
            finish(Finish::Outcome(TaskOutcome::completed(v_int(1)))),
            TaskOutcome::completed(v_int(1))
        );
        assert_eq!(
            finish(Finish::DeadlinePassed),
            TaskOutcome::aborted(AbortReason::Deadline(Duration::from_secs(1)), Kept::No)
        );
        assert_eq!(
            finish(Finish::ResultLost(Kept::Unknown)),
            TaskOutcome::result_lost(Kept::Unknown)
        );
    }

    #[test]
    fn calls_before_their_deadline_are_not_due() {
        let calls = DeferredCalls::new(10, 2, 2);
        let now = Instant::now();
        calls.add(NewDeferredCall {
            task_id: TASK,
            execution_expires_at: now + Duration::from_secs(60),
            expires_at: now + Duration::from_secs(61),
            on_finish: Box::new(|_| {}),
            slot: calls.try_reserve(CallPool::Authenticated).unwrap(),
        });
        assert!(calls.take_due_calls(now).is_empty());
    }
}
