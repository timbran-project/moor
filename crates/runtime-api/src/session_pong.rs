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

//! Answers the daemon's pings for one client session, in a task of its own.
//!
//! A ping asks whether the client is still there. A pong that fails says the daemon is slow, not
//! that the client has gone, so it is logged and the session carries on. The session ends only when
//! the daemon reports that it no longer has the connection. Running apart from the session's own
//! loop also means a slow pong cannot stop that session's input and output.

use std::{
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use moor_var::Obj;
use tokio::task::JoinHandle;
use tracing::{debug, warn};
use uuid::Uuid;

use crate::{
    ClientToken, RpcError, RpcMessageError,
    api::{BroadcastEvent, ClientBroadcastSubscription, ClientRequest, RuntimeClient},
};

/// Delay after a failed read of the ping subscription, so a broken socket cannot spin this task.
const SUBSCRIPTION_ERROR_DELAY: Duration = Duration::from_secs(1);

/// What a session's pongs identify it by.
pub struct PongIdentity {
    pub client_id: Uuid,
    pub client_token: ClientToken,
    pub player: Obj,
    pub socket_addr: String,
}

/// The running pong task. Dropping this stops it.
pub struct PongTask(JoinHandle<()>);

impl PongTask {
    pub fn spawn(
        mut pings: Box<dyn ClientBroadcastSubscription>,
        client: Arc<dyn RuntimeClient>,
        identity: PongIdentity,
    ) -> Self {
        Self(tokio::spawn(async move {
            loop {
                let event = match pings.recv_client_broadcast().await {
                    Ok(message) => message.event,
                    Err(error) => {
                        warn!(client_id = %identity.client_id, %error, "Unable to read pings");
                        tokio::time::sleep(SUBSCRIPTION_ERROR_DELAY).await;
                        continue;
                    }
                };
                match event {
                    BroadcastEvent::PingPong => {
                        if !send_pong(client.as_ref(), &identity).await {
                            return;
                        }
                    }
                }
            }
        }))
    }

    /// Wait until the daemon no longer has this connection, and so the session must end.
    ///
    /// Call this at most until it completes: it must not be awaited again after that.
    pub async fn connection_gone(&mut self) {
        if let Err(error) = (&mut self.0).await {
            warn!(%error, "Pong task ended unexpectedly");
        }
    }
}

impl Drop for PongTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// Send one pong, and report whether the session should carry on.
async fn send_pong(client: &dyn RuntimeClient, identity: &PongIdentity) -> bool {
    let client_sys_time = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as u64)
        .unwrap_or_default();
    let request = ClientRequest::ClientPong {
        client_token: identity.client_token.clone(),
        client_sys_time,
        player: identity.player,
        socket_addr: identity.socket_addr.clone(),
    };
    match client.client_call(identity.client_id, request).await {
        Ok(_) => true,
        Err(RpcError::Daemon(RpcMessageError::NoConnection)) => {
            debug!(client_id = %identity.client_id, "Daemon no longer has this connection");
            false
        }
        Err(error) => {
            warn!(client_id = %identity.client_id, %error, "Unable to send pong; keeping the session");
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::{BroadcastEventMessage, ClientReply, HostReply, HostRequest};
    use async_trait::async_trait;
    use std::sync::Mutex;
    use tokio::sync::mpsc;

    struct Pings(mpsc::UnboundedReceiver<()>);

    #[async_trait]
    impl ClientBroadcastSubscription for Pings {
        async fn recv_client_broadcast(&mut self) -> Result<BroadcastEventMessage, RpcError> {
            match self.0.recv().await {
                Some(()) => Ok(BroadcastEventMessage {
                    event: BroadcastEvent::PingPong,
                }),
                None => std::future::pending().await,
            }
        }
    }

    /// Answers each pong with the next scripted reply, and reports that it was asked.
    struct Replies {
        replies: Mutex<Vec<Result<ClientReply, RpcError>>>,
        answered: mpsc::UnboundedSender<()>,
    }

    #[async_trait]
    impl RuntimeClient for Replies {
        async fn client_call(
            &self,
            _client_id: Uuid,
            _request: ClientRequest,
        ) -> Result<ClientReply, RpcError> {
            let reply = self.replies.lock().unwrap().remove(0);
            self.answered.send(()).unwrap();
            reply
        }

        async fn host_call(
            &self,
            _host_id: Uuid,
            _request: HostRequest,
        ) -> Result<HostReply, RpcError> {
            unreachable!("pongs are client calls")
        }
    }

    fn spawn_with(
        replies: Vec<Result<ClientReply, RpcError>>,
    ) -> (
        PongTask,
        mpsc::UnboundedSender<()>,
        mpsc::UnboundedReceiver<()>,
    ) {
        let (ping, pings) = mpsc::unbounded_channel();
        let (answered, answers) = mpsc::unbounded_channel();
        let task = PongTask::spawn(
            Box::new(Pings(pings)),
            Arc::new(Replies {
                replies: Mutex::new(replies),
                answered,
            }),
            PongIdentity {
                client_id: Uuid::new_v4(),
                client_token: ClientToken("token".into()),
                player: Obj::mk_id(1),
                socket_addr: "127.0.0.1:1".into(),
            },
        );
        (task, ping, answers)
    }

    #[tokio::test]
    async fn a_failed_pong_keeps_the_session_and_the_next_ping_is_answered() {
        let (mut task, ping, mut answers) = spawn_with(vec![
            Err(RpcError::CouldNotReceive("timed out".into())),
            Ok(ClientReply::ThanksPong { timestamp: 0 }),
        ]);

        ping.send(()).unwrap();
        answers.recv().await.unwrap();
        ping.send(()).unwrap();
        answers.recv().await.unwrap();

        let ended = tokio::time::timeout(Duration::from_millis(50), task.connection_gone()).await;
        assert!(ended.is_err(), "the session should still be running");
    }

    #[tokio::test]
    async fn the_session_ends_when_the_daemon_no_longer_has_the_connection() {
        let (mut task, ping, _answers) =
            spawn_with(vec![Err(RpcError::Daemon(RpcMessageError::NoConnection))]);

        ping.send(()).unwrap();

        tokio::time::timeout(Duration::from_secs(5), task.connection_gone())
            .await
            .expect("the session should end");
    }
}
