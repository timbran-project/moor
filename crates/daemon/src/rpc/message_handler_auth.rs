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

use crate::rpc::message_handler::RpcMessageHandler;
use moor_runtime_api::{
    AuthToken, ClientToken, MOOR_AUTH_TOKEN_FOOTER, MOOR_SESSION_TOKEN_FOOTER, RpcMessageError,
};
use moor_var::Obj;
use pasetors::{Public, token::UntrustedToken, version4::PublicToken, version4::V4};
use serde_json::json;
use std::time::Instant;
use tracing::debug;
use uuid::Uuid;

impl RpcMessageHandler {
    pub(crate) fn validate_auth_token(
        &self,
        token: AuthToken,
        objid: Option<&Obj>,
    ) -> Result<Obj, RpcMessageError> {
        {
            let guard = self.auth_token_cache.pin();
            if let Some((t, o)) = guard.get(&token)
                && t.elapsed().as_secs() <= 60
            {
                if objid.is_some_and(|expected| expected != o) {
                    return Err(RpcMessageError::PermissionDenied);
                }
                return Ok(*o);
            }
        }
        let verified_token = self
            .verify_public_token(token.0.as_str(), MOOR_AUTH_TOKEN_FOOTER)
            .map_err(|e| {
                debug!(error = ?e, "Unable to parse/validate token");
                RpcMessageError::PermissionDenied
            })?;

        let verified_token = serde_json::from_str::<serde_json::Value>(verified_token.as_str())
            .map_err(|e| {
                debug!(error = ?e, "Unable to parse/validate token JSON");
                RpcMessageError::PermissionDenied
            })
            .unwrap();

        let Some(token_player) = verified_token.get("player") else {
            debug!("Token does not contain player");
            return Err(RpcMessageError::PermissionDenied);
        };
        let Some(token_player) = token_player.as_str() else {
            debug!("Token player is not valid (expected string, found: {token_player:?})");
            return Err(RpcMessageError::PermissionDenied);
        };
        let Ok(token_player) = Obj::try_from(token_player) else {
            debug!("Token player is not valid");
            return Err(RpcMessageError::PermissionDenied);
        };
        if !token_player.is_positive() {
            debug!("Token player is not a valid objid");
            return Err(RpcMessageError::PermissionDenied);
        }
        if let Some(objid) = objid {
            // Does the 'player' match objid? If not, reject it.
            if objid.ne(&token_player) {
                debug!(?objid, ?token_player, "Token player does not match objid");
                return Err(RpcMessageError::PermissionDenied);
            }
        }

        // TODO: we will need to verify that the player object id inside the token is valid inside
        //   moor itself. And really only something with a WorldState can do that. So it's not
        //   enough to have validated the auth token here, we will need to pepper the scheduler/task
        //   code with checks to make sure that the player objid is valid before letting it go
        //   forwards.

        let guard = self.auth_token_cache.pin();
        guard.insert(token.clone(), (Instant::now(), token_player));
        Ok(token_player)
    }

    /// Signs a v4.public token with the daemon's key. The footer names the token's kind.
    fn sign_public_token(&self, payload: &serde_json::Value, footer: &str) -> String {
        PublicToken::sign(
            &self.private_key,
            payload.to_string().as_bytes(),
            Some(footer.as_bytes()),
            None,
        )
        .expect("Unable to build Paseto token")
    }

    /// Verifies a v4.public token signed by the daemon and returns its payload. The footer must
    /// match exactly.
    fn verify_public_token(
        &self,
        token: &str,
        footer: &str,
    ) -> Result<String, pasetors::errors::Error> {
        let untrusted = UntrustedToken::<Public, V4>::try_from(token)?;
        let trusted =
            PublicToken::verify(&self.public_key, &untrusted, Some(footer.as_bytes()), None)?;
        Ok(trusted.payload().to_string())
    }

    pub(crate) fn make_client_token(&self, client_id: Uuid) -> ClientToken {
        let payload = json!({
            "client_id": client_id.to_string(),
            "iss": "moor",
            "aud": "moor_connection",
        });
        ClientToken(self.sign_public_token(&payload, MOOR_SESSION_TOKEN_FOOTER))
    }

    pub(crate) fn make_auth_token(&self, oid: &Obj) -> AuthToken {
        let payload = json!({
            "player": oid.to_string(),
        });
        AuthToken(self.sign_public_token(&payload, MOOR_AUTH_TOKEN_FOOTER))
    }

    pub(crate) fn validate_client_token_impl(
        &self,
        token: ClientToken,
        client_id: Uuid,
    ) -> Result<(), RpcMessageError> {
        {
            let guard = self.client_token_cache.pin();
            if let Some((t, token_client_id)) = guard.get(&token)
                && t.elapsed().as_secs() <= 60
            {
                if client_id != *token_client_id {
                    return Err(RpcMessageError::PermissionDenied);
                }
                return Ok(());
            }
        }

        let verified_token = self
            .verify_public_token(token.0.as_str(), MOOR_SESSION_TOKEN_FOOTER)
            .map_err(|e| {
                debug!(error = ?e, "Unable to parse/validate client token");
                RpcMessageError::PermissionDenied
            })?;

        let verified_token = serde_json::from_str::<serde_json::Value>(verified_token.as_str())
            .map_err(|e| {
                debug!(error = ?e, "Unable to parse/validate client token JSON");
                RpcMessageError::PermissionDenied
            })?;

        // Does the token match the client it came from? If not, reject it.
        let Some(token_client_id) = verified_token.get("client_id") else {
            debug!("Token does not contain client_id");
            return Err(RpcMessageError::PermissionDenied);
        };
        let Some(token_client_id) = token_client_id.as_str() else {
            debug!("Token client_id is null");
            return Err(RpcMessageError::PermissionDenied);
        };
        let Ok(token_client_id) = Uuid::parse_str(token_client_id) else {
            debug!("Token client_id is not a valid UUID");
            return Err(RpcMessageError::PermissionDenied);
        };
        if client_id != token_client_id {
            debug!(
                ?client_id,
                ?token_client_id,
                "Token client_id does not match client_id"
            );
            return Err(RpcMessageError::PermissionDenied);
        }

        let guard = self.client_token_cache.pin();
        guard.insert(token.clone(), (Instant::now(), token_client_id));

        Ok(())
    }

    pub fn client_auth(&self, token: ClientToken, client_id: Uuid) -> Result<Obj, RpcMessageError> {
        let Some(connection) = self.connections.connection_object_for_client(client_id) else {
            debug!(client_id = ?client_id, "client_auth: no connection found for client_id");
            return Err(RpcMessageError::NoConnection);
        };

        if let Err(e) = self.validate_client_token_impl(token, client_id) {
            debug!(client_id = ?client_id, error = ?e, "client_auth: token validation failed");
            return Err(e);
        }
        Ok(connection)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        connections::ConnectionRegistryFactory,
        tasks::task_monitor::TaskMonitor,
        testing::{MockEventLog, MockTransport, test_env::create_test_keys},
    };
    use std::sync::{Arc, RwLock};

    fn handler() -> RpcMessageHandler {
        let (public, private) = create_test_keys();
        let (sender, _) = flume::unbounded();
        RpcMessageHandler::new(
            Arc::new(moor_kernel::config::Config::default()),
            public,
            private,
            ConnectionRegistryFactory::in_memory_only().unwrap(),
            Arc::new(RwLock::new(Default::default())),
            sender.clone(),
            Arc::new(MockEventLog::new()),
            TaskMonitor::new(sender),
            crate::rpc::DeferredCalls::new(1, 1, 1),
            Arc::new(MockTransport::new()),
        )
    }

    #[test]
    fn cached_auth_token_preserves_requested_player_check() {
        let handler = handler();
        let player = Obj::mk_id(1);
        let other = Obj::mk_id(2);
        let token = handler.make_auth_token(&player);
        assert_eq!(
            handler.validate_auth_token(token.clone(), None).unwrap(),
            player
        );
        assert!(matches!(
            handler.validate_auth_token(token.clone(), Some(&other)),
            Err(RpcMessageError::PermissionDenied)
        ));
        assert_eq!(
            handler.validate_auth_token(token, Some(&player)).unwrap(),
            player
        );
    }

    #[test]
    fn cached_client_token_preserves_client_binding() {
        let handler = handler();
        let client = Uuid::new_v4();
        let other = Uuid::new_v4();
        let token = handler.make_client_token(client);
        assert!(matches!(
            handler.validate_client_token_impl(token.clone(), other),
            Err(RpcMessageError::PermissionDenied)
        ));
        handler
            .validate_client_token_impl(token.clone(), client)
            .unwrap();
        assert!(matches!(
            handler.validate_client_token_impl(token.clone(), other),
            Err(RpcMessageError::PermissionDenied)
        ));
        handler.validate_client_token_impl(token, client).unwrap();
    }
}
