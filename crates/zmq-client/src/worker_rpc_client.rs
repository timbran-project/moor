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

use crate::rpc_client::exchange;
use moor_common::tasks::WorkerError;
use moor_runtime_api::{
    DaemonToWorkerReply, RpcError, mk_attach_worker_msg, mk_request_error_msg,
    mk_request_result_msg, mk_worker_pong_msg,
};
use moor_schema::{convert::var_to_flatbuffer, rpc as moor_rpc};
use moor_var::{Symbol, Var};
use planus::{Builder, ReadAsRoot};
use r0z_async::{
    Multipart,
    request_reply::{RequestReply, RequestReplyState},
};
use tokio::sync::{Mutex, MutexGuard};
use uuid::Uuid;

/// Keep exclusive access to the worker socket through the complete exchange.
struct WorkerSocketGuard<'a> {
    socket: MutexGuard<'a, Option<RequestReply>>,
}

impl WorkerSocketGuard<'_> {
    fn socket_mut(&mut self) -> &mut RequestReply {
        self.socket.as_mut().expect("worker guard owns its socket")
    }
}

impl Drop for WorkerSocketGuard<'_> {
    fn drop(&mut self) {
        if self
            .socket
            .as_ref()
            .is_some_and(|socket| socket.state() != RequestReplyState::SendReady)
        {
            self.socket.take();
        }
    }
}

/// Serializes worker RPC exchanges on a request socket.
pub struct WorkerRpcSendClient {
    socket: Mutex<Option<RequestReply>>,
}

impl WorkerRpcSendClient {
    pub fn new(request_sender: RequestReply) -> Self {
        Self {
            socket: Mutex::new(Some(request_sender)),
        }
    }

    pub async fn make_worker_rpc_call_fb_pong(
        &self,
        worker_id: Uuid,
        worker_type: Symbol,
    ) -> Result<(), RpcError> {
        let mut socket_guard = self.acquire_socket().await?;

        let fb_message = mk_worker_pong_msg(worker_id, &worker_type);

        let worker_id_bytes = worker_id.as_bytes().to_vec();

        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&fb_message, None);

        let message = Multipart::from(vec![worker_id_bytes, rpc_msg_payload.to_vec()]);

        exchange(socket_guard.socket_mut(), message).await?;
        Ok(())
    }

    pub async fn make_worker_rpc_call_fb_result(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        result: Var,
    ) -> Result<(), RpcError> {
        let mut socket_guard = self.acquire_socket().await?;

        let result_fb = var_to_flatbuffer(&result)
            .map_err(|e| RpcError::CouldNotSend(format!("Failed to serialize result: {e}")))?;

        let fb_message = mk_request_result_msg(worker_id, request_id, result_fb);

        let worker_id_bytes = worker_id.as_bytes().to_vec();

        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&fb_message, None);

        let message = Multipart::from(vec![worker_id_bytes, rpc_msg_payload.to_vec()]);

        exchange(socket_guard.socket_mut(), message).await?;
        Ok(())
    }

    pub async fn make_worker_rpc_call_fb_attach(
        &self,
        worker_id: Uuid,
        worker_type: Symbol,
    ) -> Result<DaemonToWorkerReply, RpcError> {
        let mut socket_guard = self.acquire_socket().await?;

        let fb_message = mk_attach_worker_msg(worker_id, &worker_type);

        let worker_id_bytes = worker_id.as_bytes().to_vec();

        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&fb_message, None);

        let message = Multipart::from(vec![worker_id_bytes, rpc_msg_payload.to_vec()]);

        // Perform the RPC call - socket cleanup is guaranteed by the guard
        match exchange(socket_guard.socket_mut(), message).await {
            Ok(reply) => {
                let reply_bytes = &reply[0];

                // Decode flatbuffer response
                let fb_reply = moor_rpc::DaemonToWorkerReplyRef::read_as_root(reply_bytes)
                    .map_err(|e| {
                        RpcError::CouldNotDecode(format!(
                            "Unable to decode flatbuffer daemon reply: {e}"
                        ))
                    })?;

                let reply_union = fb_reply.reply().map_err(|e| {
                    RpcError::CouldNotDecode(format!("Unable to decode reply union: {e}"))
                })?;

                let reply = match reply_union {
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerAck(_) => DaemonToWorkerReply::Ack,
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerRejected(rejected) => {
                        let reason = rejected
                            .reason()
                            .ok()
                            .flatten()
                            .unwrap_or("Unknown reason")
                            .to_string();
                        DaemonToWorkerReply::Rejected(reason)
                    }
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerAttached(attached) => {
                        let worker_id_data = attached
                            .worker_id()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to get worker_id: {e}"))
                            })?
                            .data()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!(
                                    "Failed to get worker_id data: {e}"
                                ))
                            })?;
                        let worker_id = Uuid::from_slice(worker_id_data).map_err(|e| {
                            RpcError::CouldNotDecode(format!("Invalid worker UUID: {e}"))
                        })?;

                        DaemonToWorkerReply::Attached(worker_id)
                    }
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerAuthFailed(auth_failed) => {
                        let reason = auth_failed
                            .reason()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to get reason: {e}"))
                            })?
                            .to_string();
                        DaemonToWorkerReply::AuthFailed(reason)
                    }
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerInvalidPayload(invalid) => {
                        let reason = invalid
                            .reason()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to get reason: {e}"))
                            })?
                            .to_string();
                        DaemonToWorkerReply::InvalidPayload(reason)
                    }
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerUnknownRequest(unknown) => {
                        let request_id_data = unknown
                            .request_id()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to get request_id: {e}"))
                            })?
                            .data()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!(
                                    "Failed to get request_id data: {e}"
                                ))
                            })?;
                        let request_id = Uuid::from_slice(request_id_data).map_err(|e| {
                            RpcError::CouldNotDecode(format!("Invalid request UUID: {e}"))
                        })?;
                        DaemonToWorkerReply::UnknownRequest(request_id)
                    }
                    moor_rpc::DaemonToWorkerReplyUnionRef::WorkerNotRegistered(not_registered) => {
                        let worker_id_data = not_registered
                            .worker_id()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to get worker_id: {e}"))
                            })?
                            .data()
                            .map_err(|e| {
                                RpcError::CouldNotDecode(format!(
                                    "Failed to get worker_id data: {e}"
                                ))
                            })?;
                        let worker_id = Uuid::from_slice(worker_id_data).map_err(|e| {
                            RpcError::CouldNotDecode(format!("Invalid worker UUID: {e}"))
                        })?;
                        DaemonToWorkerReply::NotRegistered(worker_id)
                    }
                };

                Ok(reply)
            }
            Err(error) => {
                // Socket is already cleaned up by the guard on error
                Err(error)
            }
        }
    }

    pub async fn make_worker_rpc_call_fb_error(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        error: WorkerError,
    ) -> Result<(), RpcError> {
        let mut socket_guard = self.acquire_socket().await?;

        let fb_error = match error {
            WorkerError::PermissionDenied(msg) => {
                moor_rpc::WorkerErrorUnion::WorkerPermissionDenied(Box::new(
                    moor_rpc::WorkerPermissionDenied { message: msg },
                ))
            }
            WorkerError::InvalidRequest(msg) => moor_rpc::WorkerErrorUnion::WorkerInvalidRequest(
                Box::new(moor_rpc::WorkerInvalidRequest { message: msg }),
            ),
            WorkerError::InternalError(msg) => moor_rpc::WorkerErrorUnion::WorkerInternalError(
                Box::new(moor_rpc::WorkerInternalError { message: msg }),
            ),
            WorkerError::RequestTimedOut(msg) => moor_rpc::WorkerErrorUnion::WorkerRequestTimedOut(
                Box::new(moor_rpc::WorkerRequestTimedOut { message: msg }),
            ),
            WorkerError::RequestError(msg) => moor_rpc::WorkerErrorUnion::WorkerRequestError(
                Box::new(moor_rpc::WorkerRequestError { message: msg }),
            ),
            WorkerError::WorkerDetached(msg) => {
                moor_rpc::WorkerErrorUnion::WorkerDetached(Box::new(moor_rpc::WorkerDetached {
                    message: msg,
                }))
            }
            WorkerError::NoWorkerAvailable(symbol) => {
                moor_rpc::WorkerErrorUnion::NoWorkerAvailable(Box::new(
                    moor_rpc::NoWorkerAvailable {
                        worker_type: Box::new(moor_rpc::Symbol {
                            value: symbol.as_arc_str().to_string(),
                        }),
                    },
                ))
            }
        };

        let fb_message = mk_request_error_msg(
            worker_id,
            request_id,
            moor_rpc::WorkerError { error: fb_error },
        );

        let worker_id_bytes = worker_id.as_bytes().to_vec();

        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&fb_message, None);

        let message = Multipart::from(vec![worker_id_bytes, rpc_msg_payload.to_vec()]);

        exchange(socket_guard.socket_mut(), message).await?;
        Ok(())
    }

    async fn acquire_socket(&self) -> Result<WorkerSocketGuard<'_>, RpcError> {
        let socket = self.socket.lock().await;
        if socket.is_none() {
            return Err(RpcError::CouldNotSend(
                "RPC request socket not initialized".to_string(),
            ));
        }
        Ok(WorkerSocketGuard { socket })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn socket_fixture() -> (WorkerRpcSendClient, RequestReply) {
        let context = r0z::Context::new();
        let endpoint = format!("inproc://worker-rpc-test-{}", Uuid::new_v4());
        let server = r0z_async::reply(&context).bind(&endpoint).unwrap();
        let socket = r0z_async::request(&context)
            .set_sndtimeo(1000)
            .set_rcvtimeo(1000)
            .connect(&endpoint)
            .unwrap();
        (WorkerRpcSendClient::new(socket), server)
    }

    #[tokio::test]
    async fn concurrent_calls_serialize_and_reuse_socket() {
        let (client, mut server) = socket_fixture();
        let peer = async {
            for _ in 0..2 {
                assert_eq!(server.recv().await.unwrap().len(), 2);
                server.send(vec!["ack"].into()).await.unwrap();
            }
        };
        let calls = async {
            let (first, second) = tokio::join!(
                client.make_worker_rpc_call_fb_pong(Uuid::new_v4(), Symbol::mk("test")),
                client.make_worker_rpc_call_fb_pong(Uuid::new_v4(), Symbol::mk("test"))
            );
            first.unwrap();
            second.unwrap();
            assert_eq!(
                client.socket.lock().await.as_ref().unwrap().state(),
                RequestReplyState::SendReady
            );
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(peer, calls);
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn cancellation_discards_worker_socket() {
        let (client, mut server) = socket_fixture();
        {
            let call = client.make_worker_rpc_call_fb_pong(Uuid::new_v4(), Symbol::mk("test"));
            tokio::pin!(call);
            tokio::select! {
                result = &mut call => panic!("call completed before reply: {result:?}"),
                request = server.recv() => { request.unwrap(); }
            }
        }
        assert!(client.socket.lock().await.is_none());
        assert!(matches!(
            client
                .make_worker_rpc_call_fb_pong(Uuid::new_v4(), Symbol::mk("test"))
                .await,
            Err(RpcError::CouldNotSend(_))
        ));
        server.send(vec!["late reply"].into()).await.unwrap();
    }
}
