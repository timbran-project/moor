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

//! Compile coverage for the public task handoff signatures.

use moor_common::tasks::TaskId;
use moor_kernel::{
    Task,
    tasks::{scheduler::Scheduler, task_scheduler_client::TaskSchedulerClient},
    vm::TaskSuspend,
};
use moor_var::{Obj, Symbol, Var};

#[test]
#[allow(clippy::type_complexity)] // Keep the original public signatures visible in this test.
fn public_handoffs_accept_the_original_arguments() {
    let _: fn(&TaskSchedulerClient, TaskSuspend, Box<Task>) = TaskSchedulerClient::suspend;
    let _: fn(&TaskSchedulerClient, Box<Task>, Obj, Option<Vec<(Symbol, Var)>>) =
        TaskSchedulerClient::request_input;
    let _: fn(&Scheduler, TaskId, TaskSuspend, Box<Task>) = Scheduler::handle_task_suspend;
    let _: fn(&Scheduler, TaskId, Box<Task>, Obj, Option<Vec<(Symbol, Var)>>) =
        Scheduler::handle_task_request_input;
}
