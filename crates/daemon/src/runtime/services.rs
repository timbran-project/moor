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

use rpc_common::{
    RpcError,
    api::{
        ClientBroadcastSubscription, ClientEventSubscription, HostEventSubscription, HostServices,
        RuntimeClient,
    },
};
use uuid::Uuid;

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

    fn client_subscriptions(
        &self,
        client_id: Uuid,
    ) -> Result<
        (
            Box<dyn ClientEventSubscription>,
            Box<dyn ClientBroadcastSubscription>,
        ),
        RpcError,
    > {
        Ok((
            Box::new(self.event_bus.subscribe_client_events(client_id)),
            Box::new(self.event_bus.subscribe_client_broadcasts()),
        ))
    }

    fn host_events(&self) -> Result<Box<dyn HostEventSubscription>, RpcError> {
        Ok(Box::new(self.event_bus.subscribe_host_events()))
    }
}
