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

use uuid::Uuid;

use async_trait::async_trait;
use moor_common::tasks::WorkerError;
use moor_var::{Obj, Symbol, Var};

use crate::RpcError;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum DaemonToWorkerReply {
    Ack,
    Rejected(String),
    /// Let the worker know that it is attached to the daemon.
    Attached(Uuid),
    AuthFailed(String),
    InvalidPayload(String),
    UnknownRequest(Uuid),
    NotRegistered(Uuid),
}

#[derive(Debug, Clone)]
pub enum DaemonToWorkerEvent {
    Ping,
    Request {
        request_id: Uuid,
        authority_principal: Obj,
        request: Vec<Var>,
        timeout: Option<std::time::Duration>,
    },
    PleaseDie,
}

#[async_trait]
pub trait WorkerEventSubscription: Send {
    async fn recv(&mut self) -> Result<DaemonToWorkerEvent, RpcError>;
}

#[async_trait]
pub trait WorkerServices: Send + Sync {
    async fn attach_worker(
        &self,
        worker_id: Uuid,
        worker_type: Symbol,
    ) -> Result<Box<dyn WorkerEventSubscription>, RpcError>;

    async fn detach_worker(&self, worker_id: Uuid) -> Result<(), RpcError>;

    async fn worker_pong(&self, worker_id: Uuid, worker_type: Symbol) -> Result<(), RpcError>;

    async fn request_result(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        result: Var,
    ) -> Result<(), RpcError>;

    async fn request_error(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        error: WorkerError,
    ) -> Result<(), RpcError>;
}
