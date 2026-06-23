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

//! Typed daemon-side API trait.
//!
//! [`RuntimeApi`] operates on the typed request/reply enums in
//! [`moor_runtime_api::api`], decoupled from the FlatBuffer wire format. The existing
//! `MessageHandler` becomes an adapter that decodes FlatBuffer refs into these enums, calls
//! `RuntimeApi`, and encodes
//! the replies back.

use moor_kernel::SchedulerClient;
use moor_runtime_api::RpcMessageError;
use moor_runtime_api::api::{ClientReply, ClientRequest, HostReply, HostRequest};
use uuid::Uuid;

/// Runtime business logic operating on typed requests.
///
/// Implementations are sync because the daemon request loop runs on blocking
/// worker threads; the kernel's `SchedulerClient` is itself sync. A future
/// in-process adapter embedded in a tokio host can call these directly.
pub trait RuntimeApi: Send + Sync {
    fn handle_host_request(
        &self,
        host_id: Uuid,
        request: HostRequest,
    ) -> Result<HostReply, RpcMessageError>;

    fn handle_client_request(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcMessageError>;
}
