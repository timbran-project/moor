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

//! ZeroMQ-backed host services factory.

use std::sync::Arc;

use moor_runtime_api::{
    CLIENT_BROADCAST_TOPIC, HOST_BROADCAST_TOPIC, RpcError,
    api::{
        ClientBroadcastSubscription, ClientEventSubscription, HostEventSubscription, HostServices,
        RuntimeClient,
    },
};
use tmq::subscribe;
use uuid::Uuid;

use crate::{
    pubsub_client::{
        ZmqClientBroadcastSubscription, ZmqClientEventSubscription, ZmqHostEventSubscription,
    },
    rpc_client::{CurveKeys, RpcClient},
    zmq,
};

#[derive(Clone)]
pub struct ZmqHostServices {
    zmq_context: tmq::Context,
    rpc_address: String,
    events_address: String,
    curve_keys: Option<(String, String, String)>,
}

impl ZmqHostServices {
    pub fn new(
        zmq_context: tmq::Context,
        rpc_address: String,
        events_address: String,
        curve_keys: Option<(String, String, String)>,
    ) -> Self {
        Self {
            zmq_context,
            rpc_address,
            events_address,
            curve_keys,
        }
    }

    pub fn rpc_client(&self) -> RpcClient {
        RpcClient::new_with_defaults(
            Arc::new(self.zmq_context.clone()),
            self.rpc_address.clone(),
            self.curve_keys
                .as_ref()
                .map(|(client_secret, client_public, server_public)| CurveKeys {
                    client_secret: client_secret.clone(),
                    client_public: client_public.clone(),
                    server_public: server_public.clone(),
                }),
        )
    }

    fn subscriber(
        &self,
    ) -> Result<tmq::SocketBuilder<tmq::subscribe::SubscribeWithoutTopic>, RpcError> {
        let mut builder = subscribe(&self.zmq_context);

        if let Some((client_secret, client_public, server_public)) = &self.curve_keys {
            let client_secret_bytes = zmq::z85_decode(client_secret).map_err(|_| {
                RpcError::CouldNotInitiateSession("Invalid client secret key".to_string())
            })?;
            let client_public_bytes = zmq::z85_decode(client_public).map_err(|_| {
                RpcError::CouldNotInitiateSession("Invalid client public key".to_string())
            })?;
            let server_public_bytes = zmq::z85_decode(server_public).map_err(|_| {
                RpcError::CouldNotInitiateSession("Invalid server public key".to_string())
            })?;

            builder = builder
                .set_curve_secretkey(&client_secret_bytes)
                .set_curve_publickey(&client_public_bytes)
                .set_curve_serverkey(&server_public_bytes);
        }

        Ok(builder)
    }
}

impl HostServices for ZmqHostServices {
    fn runtime_client(&self) -> Arc<dyn RuntimeClient> {
        Arc::new(self.rpc_client())
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
        let events_sub = self
            .subscriber()?
            .connect(self.events_address.as_str())
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to connect narrative subscriber: {e}"
                ))
            })?
            .subscribe(&client_id.as_bytes()[..])
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to subscribe to narrative messages: {e}"
                ))
            })?;

        let broadcast_sub = self
            .subscriber()?
            .connect(self.events_address.as_str())
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to connect broadcast subscriber: {e}"
                ))
            })?
            .subscribe(CLIENT_BROADCAST_TOPIC)
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to subscribe to broadcast messages: {e}"
                ))
            })?;

        Ok((
            Box::new(ZmqClientEventSubscription::new(client_id, events_sub)),
            Box::new(ZmqClientBroadcastSubscription::new(broadcast_sub)),
        ))
    }

    fn host_events(&self) -> Result<Box<dyn HostEventSubscription>, RpcError> {
        let events_sub = self
            .subscriber()?
            .connect(self.events_address.as_str())
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to connect host events subscriber: {e}"
                ))
            })?
            .subscribe(HOST_BROADCAST_TOPIC)
            .map_err(|e| {
                RpcError::CouldNotInitiateSession(format!(
                    "Unable to subscribe to host events: {e}"
                ))
            })?;

        Ok(Box::new(ZmqHostEventSubscription::new(events_sub)))
    }
}
