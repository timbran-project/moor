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

use std::sync::Arc;

use async_trait::async_trait;
use moor_common::tasks::WorkerError;
use moor_runtime_api::{
    DaemonToWorkerEvent, RpcError, WorkerEventSubscription, WorkerServices,
    api::{ClientSubscriptions, HostEventSubscription, HostServices, RuntimeClient},
};
use moor_var::{Symbol, Var};
use uuid::Uuid;

use moor_daemon::WorkersMessageHandlerImpl;

use super::LocalEventBus;

#[derive(Clone)]
pub struct LocalRuntimeServices {
    pub runtime_client: Arc<dyn RuntimeClient>,
    pub event_bus: Arc<LocalEventBus>,
}

impl HostServices for LocalRuntimeServices {
    fn runtime_client(&self) -> Arc<dyn RuntimeClient> {
        self.runtime_client.clone()
    }

    fn client_subscriptions(&self, client_id: Uuid) -> Result<ClientSubscriptions, RpcError> {
        Ok((
            Box::new(self.event_bus.subscribe_client_events(client_id)),
            Box::new(self.event_bus.subscribe_client_broadcasts()),
        ))
    }

    fn host_events(&self) -> Result<Box<dyn HostEventSubscription>, RpcError> {
        Ok(Box::new(self.event_bus.subscribe_host_events()))
    }
}

pub struct LocalWorkerServices {
    message_handler: Arc<WorkersMessageHandlerImpl>,
}

impl LocalWorkerServices {
    pub fn new(message_handler: Arc<WorkersMessageHandlerImpl>) -> Self {
        Self { message_handler }
    }
}

struct LocalWorkerEventSubscription {
    recv: flume::Receiver<DaemonToWorkerEvent>,
}

#[async_trait]
impl WorkerEventSubscription for LocalWorkerEventSubscription {
    async fn recv(&mut self) -> Result<DaemonToWorkerEvent, RpcError> {
        self.recv
            .recv_async()
            .await
            .map_err(|e| RpcError::ConnectionLost(e.to_string()))
    }
}

#[async_trait]
impl WorkerServices for LocalWorkerServices {
    async fn attach_worker(
        &self,
        worker_id: Uuid,
        worker_type: Symbol,
    ) -> Result<Box<dyn WorkerEventSubscription>, RpcError> {
        let recv = self
            .message_handler
            .attach_local_worker(worker_id, worker_type);
        Ok(Box::new(LocalWorkerEventSubscription { recv }))
    }

    async fn detach_worker(&self, worker_id: Uuid) -> Result<(), RpcError> {
        self.message_handler.detach_local_worker(worker_id);
        Ok(())
    }

    async fn worker_pong(&self, worker_id: Uuid, worker_type: Symbol) -> Result<(), RpcError> {
        self.message_handler
            .local_worker_pong(worker_id, worker_type);
        Ok(())
    }

    async fn request_result(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        result: Var,
    ) -> Result<(), RpcError> {
        self.message_handler
            .local_request_result(worker_id, request_id, result)
    }

    async fn request_error(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        error: WorkerError,
    ) -> Result<(), RpcError> {
        self.message_handler
            .local_request_error(worker_id, request_id, error)
    }
}
