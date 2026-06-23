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

//! Message handler for workers business logic, separated from transport concerns

use eyre::Context;
use moor_common::tasks::WorkerError;
use moor_schema::{
    convert::{symbol_from_ref, uuid_from_ref, var_from_ref, var_to_flatbuffer},
    rpc as moor_rpc,
};

use moor_kernel::tasks::workers::{WorkerRequest, WorkerResponse};
use moor_runtime_api::{
    DaemonToWorkerEvent, RpcError, StrErr, WORKER_BROADCAST_TOPIC, mk_ping_workers_msg,
    mk_worker_ack_reply, mk_worker_attached_reply, mk_worker_invalid_payload_reply,
    mk_worker_not_registered_reply, mk_worker_request_msg, mk_worker_unknown_request_reply,
    worker_error_from_ref,
};
use moor_var::{Obj, Symbol, Var};
use planus::Builder;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, RwLock},
    time::{Duration, Instant},
};
use tracing::{error, info, warn};
use uuid::Uuid;
use zmq::{Socket, SocketType};

pub const WORKER_TIMEOUT: Duration = Duration::from_secs(10);
pub const PING_FREQUENCY: Duration = Duration::from_secs(5);

struct Worker {
    id: Uuid,
    last_ping_time: Instant,
    worker_type: Symbol,
    /// The set of pending requests for this worker, that we are waiting on responses for.
    requests: Vec<(Uuid, Obj, Vec<Var>)>,
    local_events: Option<flume::Sender<DaemonToWorkerEvent>>,
}

enum WorkerEventSink {
    Zmq(Arc<Mutex<Socket>>),
    Local,
}

/// Trait for handling workers message business logic
pub trait WorkersMessageHandler: Send + Sync {
    /// Process a worker-to-daemon message (flatbuffer format)
    fn handle_worker_message(
        &self,
        worker_id: &[u8],
        message: &moor_rpc::WorkerToDaemonMessageRef,
    ) -> moor_rpc::DaemonToWorkerReply;

    /// Check for expired workers and handle pending requests
    fn check_expired_workers(&self);

    /// Send ping to all workers
    fn ping_workers(&self) -> Result<(), eyre::Error>;

    /// Process a worker request from the scheduler
    fn process_worker_request(&self, request: WorkerRequest) -> Result<(), eyre::Error>;

    /// Get information about all workers
    fn get_workers_info(&self) -> Vec<moor_common::tasks::WorkerInfo>;
}

/// Implementation of message handler that contains the actual business logic
pub struct WorkersMessageHandlerImpl {
    workers: Arc<RwLock<HashMap<Uuid, Worker>>>,
    scheduler_send: flume::Sender<WorkerResponse>,
    event_sink: WorkerEventSink,
}

impl WorkersMessageHandlerImpl {
    pub fn new_zmq(
        zmq_context: zmq::Context,
        workers_broadcast: &str,
        scheduler_send: flume::Sender<WorkerResponse>,
        curve_secret_key: Option<String>, // Z85-encoded CURVE secret key
    ) -> Result<Self, eyre::Error> {
        // Create the publish socket for broadcasting to workers
        let publish = zmq_context
            .socket(SocketType::PUB)
            .context("Unable to create ZMQ PUB socket")?;

        // Configure CURVE encryption if key provided
        if let Some(ref secret_key) = curve_secret_key {
            // Set ZAP domain for authentication
            publish
                .set_zap_domain("moor")
                .context("Failed to set ZAP domain on workers PUB socket")?;

            publish
                .set_curve_server(true)
                .context("Failed to enable CURVE server on workers PUB socket")?;

            // Decode Z85-encoded secret key to bytes
            let secret_key_bytes =
                zmq::z85_decode(secret_key).context("Failed to decode Z85 secret key")?;
            publish
                .set_curve_secretkey(&secret_key_bytes)
                .context("Failed to set CURVE secret key on workers PUB socket")?;

            info!("CURVE encryption enabled on workers PUB socket with ZAP authentication");
        }

        publish
            .bind(workers_broadcast)
            .context("Unable to bind ZMQ PUB socket")?;

        let workers_publish = Arc::new(Mutex::new(publish));

        Ok(Self {
            workers: Arc::new(RwLock::new(HashMap::new())),
            scheduler_send,
            event_sink: WorkerEventSink::Zmq(workers_publish),
        })
    }

    pub fn new_local(scheduler_send: flume::Sender<WorkerResponse>) -> Self {
        Self {
            workers: Arc::new(RwLock::new(HashMap::new())),
            scheduler_send,
            event_sink: WorkerEventSink::Local,
        }
    }

    pub fn attach_local_worker(
        &self,
        worker_id: Uuid,
        worker_type: Symbol,
    ) -> flume::Receiver<DaemonToWorkerEvent> {
        let (send, recv) = flume::unbounded();
        let mut workers = self.workers.write().unwrap();
        workers.insert(
            worker_id,
            Worker {
                last_ping_time: Instant::now(),
                worker_type,
                id: worker_id,
                requests: vec![],
                local_events: Some(send),
            },
        );
        info!(
            "Local worker {} of type {} attached",
            worker_id, worker_type
        );
        recv
    }

    pub fn detach_local_worker(&self, worker_id: Uuid) {
        self.abort_worker(worker_id);
    }

    pub fn local_worker_pong(&self, worker_id: Uuid, worker_type: Symbol) {
        let mut workers = self.workers.write().unwrap();
        if let Some(worker) = workers.get_mut(&worker_id) {
            worker.last_ping_time = Instant::now();
            return;
        }

        warn!("Received pong from unknown local worker; re-establishing...");
        let (send, _) = flume::unbounded();
        workers.insert(
            worker_id,
            Worker {
                last_ping_time: Instant::now(),
                worker_type,
                id: worker_id,
                requests: vec![],
                local_events: Some(send),
            },
        );
    }

    pub fn local_request_result(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        result: Var,
    ) -> Result<(), RpcError> {
        self.complete_worker_request(worker_id, request_id, Ok(result))
            .map_err(RpcError::Recoverable)
    }

    pub fn local_request_error(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        error: WorkerError,
    ) -> Result<(), RpcError> {
        self.complete_worker_request(worker_id, request_id, Err(error))
            .map_err(RpcError::Recoverable)
    }
}

impl WorkersMessageHandler for WorkersMessageHandlerImpl {
    fn handle_worker_message(
        &self,
        worker_id: &[u8],
        message: &moor_rpc::WorkerToDaemonMessageRef,
    ) -> moor_rpc::DaemonToWorkerReply {
        let Ok(worker_id) = Uuid::from_slice(worker_id) else {
            error!("Unable to parse worker id {worker_id:?} from message");
            return mk_worker_invalid_payload_reply("Invalid worker ID format");
        };

        // Now handle the message using flatbuffer types directly
        let Ok(message_union) = message.message() else {
            error!("Failed to read message union from WorkerToDaemonMessage");
            return mk_worker_invalid_payload_reply("Missing or invalid message union");
        };

        let result = match message_union {
            moor_rpc::WorkerToDaemonMessageUnionRef::AttachWorker(attach) => {
                self.handle_attach_worker(worker_id, attach)
            }
            moor_rpc::WorkerToDaemonMessageUnionRef::WorkerPong(pong) => {
                self.handle_worker_pong(worker_id, pong)
            }
            moor_rpc::WorkerToDaemonMessageUnionRef::DetachWorker(_detach) => {
                self.handle_detach_worker(worker_id)
            }
            moor_rpc::WorkerToDaemonMessageUnionRef::RequestResult(result) => {
                self.handle_request_result(worker_id, result)
            }
            moor_rpc::WorkerToDaemonMessageUnionRef::RequestError(error) => {
                self.handle_request_error(worker_id, error)
            }
        };

        result.unwrap_or_else(|e| {
            error!("Error handling worker message: {}", e);
            mk_worker_invalid_payload_reply(e)
        })
    }

    fn check_expired_workers(&self) {
        let mut workers = self.workers.write().unwrap();
        let now = Instant::now();
        workers.retain(|_, worker| {
            if now.duration_since(worker.last_ping_time) > WORKER_TIMEOUT {
                error!(
                    "Worker {} of type {} has expired",
                    worker.id, worker.worker_type
                );
                // Abort all requests for this worker
                for (id, _, _) in &worker.requests {
                    self.scheduler_send
                        .send(WorkerResponse::Error {
                            request_id: *id,
                            error: WorkerError::WorkerDetached(format!(
                                "{} worker {} detached",
                                worker.worker_type, worker.id
                            )),
                        })
                        .ok();
                }
                false
            } else {
                true
            }
        });
    }

    fn ping_workers(&self) -> Result<(), eyre::Error> {
        match &self.event_sink {
            WorkerEventSink::Zmq(publish) => {
                let fb_message = mk_ping_workers_msg();
                let mut builder = Builder::new();
                let event_bytes = builder.finish(&fb_message, None);
                let payload = vec![WORKER_BROADCAST_TOPIC.to_vec(), event_bytes.to_vec()];

                let publish = publish.lock().unwrap();
                publish
                    .send_multipart(payload, 0)
                    .context("Unable to send ping to workers")?;
            }
            WorkerEventSink::Local => {
                let workers = self.workers.read().unwrap();
                for worker in workers.values() {
                    let Some(local_events) = worker.local_events.as_ref() else {
                        continue;
                    };
                    local_events
                        .send(DaemonToWorkerEvent::Ping)
                        .context("Unable to send ping to local worker")?;
                }
            }
        }
        Ok(())
    }

    fn process_worker_request(&self, request: WorkerRequest) -> Result<(), eyre::Error> {
        match request {
            WorkerRequest::Request {
                request_id,
                request_type,
                authority_principal,
                request,
                timeout,
            } => {
                // Pick a worker of the given type to send the request to,
                // preferably one with the lowest # of requests already queued up
                let mut workers = self.workers.write().unwrap();
                let mut found_worker = None;
                let mut min_requests = usize::MAX;
                for (worker_id, worker) in workers.iter_mut() {
                    if worker.worker_type == request_type && worker.requests.len() < min_requests {
                        min_requests = worker.requests.len();
                        found_worker = Some((worker_id, worker));
                    }
                }

                let Some((_, worker)) = found_worker else {
                    error!("No workers available for request type {}", request_type);
                    self.scheduler_send
                        .send(WorkerResponse::Error {
                            request_id,
                            error: WorkerError::NoWorkerAvailable(request_type),
                        })
                        .ok();
                    return Ok(());
                };

                match &self.event_sink {
                    WorkerEventSink::Zmq(publish) => {
                        let request_fb: Result<Vec<_>, _> =
                            request.iter().map(var_to_flatbuffer).collect();
                        let request_vars = request_fb
                            .context("Failed to serialize request variables to flatbuffer")?;
                        let timeout_ms = timeout.map(|d| d.as_millis() as u64).unwrap_or(0);
                        let fb_message = mk_worker_request_msg(
                            worker.id,
                            request_id,
                            &authority_principal,
                            request_vars,
                            timeout_ms,
                        );

                        let mut builder = Builder::new();
                        let event_bytes = builder.finish(&fb_message, None);
                        let payload = vec![WORKER_BROADCAST_TOPIC.to_vec(), event_bytes.to_vec()];

                        let publish = publish.lock().unwrap();
                        publish
                            .send_multipart(payload, 0)
                            .context("Unable to send request to worker")?;
                    }
                    WorkerEventSink::Local => {
                        let Some(local_events) = worker.local_events.as_ref() else {
                            self.scheduler_send
                                .send(WorkerResponse::Error {
                                    request_id,
                                    error: WorkerError::WorkerDetached(format!(
                                        "{} worker {} has no local event channel",
                                        worker.worker_type, worker.id
                                    )),
                                })
                                .ok();
                            return Ok(());
                        };
                        local_events
                            .send(DaemonToWorkerEvent::Request {
                                request_id,
                                authority_principal,
                                request: request.clone(),
                                timeout,
                            })
                            .context("Unable to send request to local worker")?;
                    }
                }

                info!(
                    "Sending request to worker {} of type {}",
                    worker.id, worker.worker_type
                );

                // Then shove it into the queue for the given worker
                worker
                    .requests
                    .push((request_id, authority_principal, request));
                Ok(())
            }
        }
    }

    fn get_workers_info(&self) -> Vec<moor_common::tasks::WorkerInfo> {
        use moor_common::tasks::WorkerInfo;
        use std::collections::HashMap;

        let workers = self.workers.read().unwrap();
        let now = std::time::Instant::now();

        // Group workers by type and calculate statistics
        let mut worker_stats: HashMap<moor_var::Symbol, (usize, usize, Vec<f64>)> = HashMap::new();

        for worker in workers.values() {
            let entry = worker_stats
                .entry(worker.worker_type)
                .or_insert((0, 0, Vec::new()));
            entry.0 += 1; // worker_count
            entry.1 += worker.requests.len(); // total_queue_size

            // Calculate time since last ping in seconds
            let last_ping_ago_secs = now.duration_since(worker.last_ping_time).as_secs_f64();
            entry.2.push(last_ping_ago_secs);
        }

        // Convert to WorkerInfo structs
        worker_stats
            .into_iter()
            .map(
                |(worker_type, (worker_count, total_queue_size, ping_times))| {
                    let last_ping_ago_secs = ping_times.iter().copied().fold(0.0f64, f64::max);
                    WorkerInfo {
                        worker_type,
                        worker_count,
                        total_queue_size,
                        avg_response_time_ms: 0.0, // TODO: Implement response time tracking
                        last_ping_ago_secs,
                    }
                },
            )
            .collect()
    }
}

impl crate::system_control::WorkerInfoSource for WorkersMessageHandlerImpl {
    fn get_workers_info(&self) -> Vec<moor_common::tasks::WorkerInfo> {
        WorkersMessageHandler::get_workers_info(self)
    }
}

/// Helper to extract WorkerError from flatbuffer
fn extract_worker_error(
    error_ref: Result<moor_rpc::WorkerErrorRef, planus::Error>,
) -> Result<WorkerError, String> {
    let error = error_ref.map_err(|_| "Failed to read error field".to_string())?;
    worker_error_from_ref(error).map_err(|e| format!("Failed to deserialize error: {e}"))
}

impl WorkersMessageHandlerImpl {
    fn abort_worker(&self, worker_id: Uuid) {
        let mut workers = self.workers.write().unwrap();
        let Some(worker) = workers.remove(&worker_id) else {
            error!("Received detach from unknown or old worker");
            return;
        };

        for (id, _, _) in worker.requests {
            self.scheduler_send
                .send(WorkerResponse::Error {
                    request_id: id,
                    error: WorkerError::WorkerDetached(format!(
                        "{} worker {} detached",
                        worker.worker_type, worker_id
                    )),
                })
                .ok();
        }
    }

    fn complete_worker_request(
        &self,
        worker_id: Uuid,
        request_id: Uuid,
        result: Result<Var, WorkerError>,
    ) -> Result<(), String> {
        let mut workers = self.workers.write().unwrap();
        let Some(worker) = workers.get_mut(&worker_id) else {
            error!(
                "Received response from unknown or old worker ({}), ignoring",
                worker_id
            );
            return Err(format!("Worker {worker_id} is not registered"));
        };

        let found_request_idx = worker
            .requests
            .iter()
            .position(|(pending_request_id, _, _)| request_id == *pending_request_id);

        let Some(idx) = found_request_idx else {
            error!("Received response for unknown or old request");
            return Err(format!("Worker request {request_id} is not pending"));
        };

        worker.requests.remove(idx);

        match result {
            Ok(response) => {
                self.scheduler_send
                    .send(WorkerResponse::Response {
                        request_id,
                        response,
                    })
                    .ok();
            }
            Err(error) => {
                self.scheduler_send
                    .send(WorkerResponse::Error { request_id, error })
                    .ok();
            }
        }

        Ok(())
    }

    /// Handle AttachWorker message
    fn handle_attach_worker(
        &self,
        worker_id: Uuid,
        attach: moor_rpc::AttachWorkerRef,
    ) -> Result<moor_rpc::DaemonToWorkerReply, String> {
        let worker_type = attach.worker_type().str_err().and_then(symbol_from_ref)?;

        let mut workers = self.workers.write().unwrap();
        workers.insert(
            worker_id,
            Worker {
                last_ping_time: Instant::now(),
                worker_type,
                id: worker_id,
                requests: vec![],
                local_events: None,
            },
        );
        info!("Worker {} of type {} attached", worker_id, worker_type);

        Ok(mk_worker_attached_reply(worker_id))
    }

    /// Handle WorkerPong message
    fn handle_worker_pong(
        &self,
        worker_id: Uuid,
        pong: moor_rpc::WorkerPongRef,
    ) -> Result<moor_rpc::DaemonToWorkerReply, String> {
        let worker_type = pong.worker_type().str_err().and_then(symbol_from_ref)?;

        let mut workers = self.workers.write().unwrap();
        if let Some(worker) = workers.get_mut(&worker_id) {
            worker.last_ping_time = Instant::now();
            Ok(mk_worker_ack_reply())
        } else {
            warn!("Received pong from unknown or old worker (did we restart?); re-establishing...");
            workers.insert(
                worker_id,
                Worker {
                    last_ping_time: Instant::now(),
                    worker_type,
                    id: worker_id,
                    requests: vec![],
                    local_events: None,
                },
            );
            info!("Worker {} of type {} re-attached", worker_id, worker_type);

            Ok(mk_worker_attached_reply(worker_id))
        }
    }

    /// Handle DetachWorker message
    fn handle_detach_worker(
        &self,
        worker_id: Uuid,
    ) -> Result<moor_rpc::DaemonToWorkerReply, String> {
        self.abort_worker(worker_id);
        Ok(mk_worker_ack_reply())
    }

    /// Handle RequestResult message
    fn handle_request_result(
        &self,
        worker_id: Uuid,
        result: moor_rpc::RequestResultRef,
    ) -> Result<moor_rpc::DaemonToWorkerReply, String> {
        let request_id = result.request_id().str_err().and_then(uuid_from_ref)?;

        let result_var = result.result().str_err().and_then(var_from_ref)?;

        match self.complete_worker_request(worker_id, request_id, Ok(result_var)) {
            Ok(()) => Ok(mk_worker_ack_reply()),
            Err(_) => {
                if self.workers.read().unwrap().contains_key(&worker_id) {
                    Ok(mk_worker_unknown_request_reply(request_id))
                } else {
                    Ok(mk_worker_not_registered_reply(worker_id))
                }
            }
        }
    }

    /// Handle RequestError message
    fn handle_request_error(
        &self,
        worker_id: Uuid,
        error: moor_rpc::RequestErrorRef,
    ) -> Result<moor_rpc::DaemonToWorkerReply, String> {
        let request_id = error.request_id().str_err().and_then(uuid_from_ref)?;
        let worker_error = extract_worker_error(error.error())?;

        match self.complete_worker_request(worker_id, request_id, Err(worker_error)) {
            Ok(()) => Ok(mk_worker_ack_reply()),
            Err(_) => {
                if self.workers.read().unwrap().contains_key(&worker_id) {
                    Ok(mk_worker_unknown_request_reply(request_id))
                } else {
                    Ok(mk_worker_not_registered_reply(worker_id))
                }
            }
        }
    }
}
