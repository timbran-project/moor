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

//! In-process [`moor_runtime_api::api::RuntimeClient`] adapter.

use std::sync::Arc;

use async_trait::async_trait;
use moor_kernel::SchedulerClient;
use moor_runtime_api::{
    RpcError,
    api::{ClientReply, ClientRequest, HostReply, HostRequest, RuntimeClient},
};
use uuid::Uuid;

use moor_daemon::RuntimeApi;

/// A host-side client that calls the runtime APIs directly.
pub struct LocalRuntimeClient {
    api: Arc<dyn RuntimeApi>,
    scheduler_client: Option<SchedulerClient>,
}

impl Clone for LocalRuntimeClient {
    fn clone(&self) -> Self {
        Self {
            api: self.api.clone(),
            scheduler_client: self.scheduler_client.clone(),
        }
    }
}

impl LocalRuntimeClient {
    pub fn new(api: Arc<dyn RuntimeApi>, scheduler_client: SchedulerClient) -> Self {
        Self {
            api,
            scheduler_client: Some(scheduler_client),
        }
    }

    #[cfg(test)]
    fn host_only(api: Arc<dyn RuntimeApi>) -> Self {
        Self {
            api,
            scheduler_client: None,
        }
    }
}

#[async_trait]
impl RuntimeClient for LocalRuntimeClient {
    async fn client_call(
        &self,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcError> {
        let Some(scheduler_client) = self.scheduler_client.clone() else {
            return Err(RpcError::Fatal(
                "local runtime client has no scheduler client".to_string(),
            ));
        };
        self.api
            .handle_client_request(scheduler_client, client_id, request)
            .map_err(RpcError::Daemon)
    }

    async fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, RpcError> {
        self.api
            .handle_host_request(host_id, request)
            .map_err(RpcError::Daemon)
    }
}

#[cfg(test)]
mod tests {
    use moor_kernel::SchedulerClient;
    use moor_runtime_api::{
        HostType, RpcMessageError,
        api::{ClientRequest, HostReply, HostRequest},
    };
    use uuid::Uuid;

    use super::LocalRuntimeClient;
    use moor_daemon::RuntimeApi;

    struct MockRuntimeApi;

    impl RuntimeApi for MockRuntimeApi {
        fn handle_host_request(
            &self,
            _host_id: Uuid,
            request: HostRequest,
        ) -> Result<HostReply, RpcMessageError> {
            match request {
                HostRequest::RegisterHost { host_type, .. } => {
                    assert_eq!(host_type, HostType::TCP);
                    Ok(HostReply::Ack)
                }
                _ => panic!("unexpected host request"),
            }
        }

        fn handle_client_request(
            &self,
            _scheduler_client: SchedulerClient,
            _client_id: Uuid,
            _request: ClientRequest,
        ) -> Result<moor_runtime_api::api::ClientReply, RpcMessageError> {
            panic!("client request not used by this smoke test")
        }
    }

    #[tokio::test]
    async fn local_runtime_client_calls_host_api_directly() {
        let client = LocalRuntimeClient::host_only(std::sync::Arc::new(MockRuntimeApi));
        let reply = moor_runtime_api::api::RuntimeClient::host_call(
            &client,
            Uuid::new_v4(),
            HostRequest::RegisterHost {
                timestamp: 1,
                host_type: HostType::TCP,
                listeners: Vec::new(),
            },
        )
        .await
        .unwrap();

        assert!(matches!(reply, HostReply::Ack));
    }
}
