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

//! Scheduler testing utilities for integration tests with scheduler clients

use std::{sync::Arc, time::Duration};

use moor_common::tasks::{AbortReason, CommandError, SchedulerError, TaskEnding, TaskOutcome};
use moor_var::{E_VERBNF, Obj, SYSTEM_OBJECT, Symbol, Var};

use crate::{
    config::FeaturesConfig,
    tasks::{TaskHandle, scheduler_client::SchedulerClient},
};
use moor_common::tasks::{Exception, Session};

pub type ExecResult = Result<Var, Exception>;

/// Why a test task produced no value.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum TaskFailure {
    /// The scheduler refused the request, so no task ran.
    #[error("request rejected: {0}")]
    Rejected(#[from] SchedulerError),
    /// The task ran and ended without completing.
    #[error("task ended without completing: {0:?}")]
    Ended(TaskOutcome),
}

fn execute<F>(fun: F) -> Result<Var, TaskFailure>
where
    F: FnOnce() -> Result<TaskHandle, SchedulerError>,
{
    let task_handle = fun()?;
    loop {
        let (_, outcome) = task_handle
            .receiver()
            .recv_timeout(Duration::from_secs(5))
            .inspect_err(|e| {
                eprintln!(
                    "subscriber.recv_timeout() failed for task {}: {e}",
                    task_handle.task_id(),
                )
            })
            .unwrap();
        match outcome.ending {
            TaskEnding::Completed(var) => return Ok(var),
            TaskEnding::Suspended => continue,
            // Some endings can be represented as a MOO `Var`; translate those to a `Var`, so
            // that `moot` tests can match against them.
            TaskEnding::Aborted(AbortReason::Exception(Exception { error, .. })) => {
                return Ok(error.into());
            }
            TaskEnding::Aborted(AbortReason::CommandFailed(CommandError::NoCommandMatch)) => {
                return Ok(E_VERBNF.msg("No command match").into());
            }
            _ => return Err(TaskFailure::Ended(outcome)),
        }
    }
}

pub fn call_command(
    scheduler: SchedulerClient,
    session: Arc<dyn Session>,
    player: &Obj,
    command: &str,
) -> Result<Var, TaskFailure> {
    execute(|| scheduler.submit_command_task(&SYSTEM_OBJECT, player, command, session))
}

pub fn call_eval(
    scheduler: SchedulerClient,
    session: Arc<dyn Session>,
    player: &Obj,
    code: String,
) -> Result<Var, TaskFailure> {
    call_eval_with_features(
        scheduler,
        session,
        player,
        code,
        Arc::new(FeaturesConfig::default()),
    )
}

pub fn call_eval_with_features(
    scheduler: SchedulerClient,
    session: Arc<dyn Session>,
    player: &Obj,
    code: String,
    features: Arc<FeaturesConfig>,
) -> Result<Var, TaskFailure> {
    call_eval_with_env_and_features(scheduler, session, player, code, None, features)
}

pub fn call_eval_with_env(
    scheduler: SchedulerClient,
    session: Arc<dyn Session>,
    player: &Obj,
    code: String,
    initial_env: Option<Vec<(Symbol, Var)>>,
) -> Result<Var, TaskFailure> {
    call_eval_with_env_and_features(
        scheduler,
        session,
        player,
        code,
        initial_env,
        Arc::new(FeaturesConfig::default()),
    )
}

pub fn call_eval_with_env_and_features(
    scheduler: SchedulerClient,
    session: Arc<dyn Session>,
    player: &Obj,
    code: String,
    initial_env: Option<Vec<(Symbol, Var)>>,
    features: Arc<FeaturesConfig>,
) -> Result<Var, TaskFailure> {
    execute(|| scheduler.submit_eval_task(player, player, code, initial_env, session, features))
}
