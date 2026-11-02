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

//! HTTP responses for failed daemon requests.
//!
//! A request the daemon refuses is reported with the status that fits why, and a JSON body
//! `{"code": "...", "error": "..."}` naming the problem. Only failures of the daemon itself,
//! or ones this host cannot classify, are server errors.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
};
use moor_common::{
    model::WorldStateError,
    tasks::{CommandError, SchedulerError},
};
use moor_runtime_api::{RpcError, RpcMessageError};
use tracing::{debug, error};

/// A JSON error response. Errors use JSON even when the requested success format is
/// FlatBuffers.
pub(crate) fn error_response(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        axum::Json(serde_json::json!({"code": code, "error": message})),
    )
        .into_response()
}

/// A failed request's response, boxed to keep `Result`s that carry it small.
pub(crate) struct ErrorReply(Box<Response>);

impl From<Response> for ErrorReply {
    fn from(response: Response) -> Self {
        Self(Box::new(response))
    }
}

impl From<StatusCode> for ErrorReply {
    fn from(status: StatusCode) -> Self {
        status.into_response().into()
    }
}

impl IntoResponse for ErrorReply {
    fn into_response(self) -> Response {
        *self.0
    }
}

/// The response for a failed daemon request. Server errors carry a generic message; their
/// detail goes only to the log.
pub(crate) fn daemon_error_response(error: &RpcError) -> Response {
    let (status, code, message) = classify(error);
    if status.is_server_error() {
        error!(?error, %status, "Daemon request failed");
        let message = if status == StatusCode::SERVICE_UNAVAILABLE {
            "The daemon is unavailable"
        } else {
            "Internal server error"
        };
        return error_response(status, code, message);
    }
    debug!(?error, %status, "Daemon refused the request");
    error_response(status, code, &message)
}

fn classify(error: &RpcError) -> (StatusCode, &'static str, String) {
    match error {
        RpcError::Daemon(RpcMessageError::PermissionDenied) | RpcError::AuthenticationError(_) => (
            StatusCode::UNAUTHORIZED,
            "unauthorized",
            "Missing or invalid credentials".to_string(),
        ),
        RpcError::Daemon(RpcMessageError::InvalidRequest(message)) => {
            (StatusCode::BAD_REQUEST, "invalid_request", message.clone())
        }
        RpcError::Daemon(RpcMessageError::TaskError(scheduler_error)) => {
            classify_scheduler_error(scheduler_error)
        }
        RpcError::Daemon(RpcMessageError::ServerBusy) => (
            StatusCode::SERVICE_UNAVAILABLE,
            "server_busy",
            "The server is busy".to_string(),
        ),
        RpcError::CouldNotSend(_)
        | RpcError::CouldNotReceive(_)
        | RpcError::ConnectionLost(_)
        | RpcError::Timeout(_)
        | RpcError::Recoverable(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            "daemon_unavailable",
            String::new(),
        ),
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            String::new(),
        ),
    }
}

fn classify_scheduler_error(error: &SchedulerError) -> (StatusCode, &'static str, String) {
    use SchedulerError::*;
    match error {
        VerbRetrievalFailed(world_state)
        | PropertyRetrievalFailed(world_state)
        | ObjectResolutionFailed(world_state)
        | CommandExecutionError(CommandError::DatabaseError(world_state)) => {
            classify_world_state_error(world_state)
        }
        CommandExecutionError(CommandError::NoObjectMatch) => (
            StatusCode::NOT_FOUND,
            "object_not_found",
            "Object not found".to_string(),
        ),
        CommandExecutionError(CommandError::PermissionDenied) => (
            StatusCode::FORBIDDEN,
            "permission_denied",
            "Permission denied".to_string(),
        ),
        TaskAbortedVerbNotFound(..) => (StatusCode::NOT_FOUND, "verb_not_found", error.to_string()),
        SchedulerNotResponding | CouldNotStartTask => (
            StatusCode::SERVICE_UNAVAILABLE,
            "daemon_unavailable",
            String::new(),
        ),
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            String::new(),
        ),
    }
}

fn classify_world_state_error(error: &WorldStateError) -> (StatusCode, &'static str, String) {
    use WorldStateError::*;
    let (status, code) = match error {
        ObjectNotFound(_) => (StatusCode::NOT_FOUND, "object_not_found"),
        VerbNotFound(..) => (StatusCode::NOT_FOUND, "verb_not_found"),
        PropertyNotFound(..) | PropertyDefinitionNotFound(..) => {
            (StatusCode::NOT_FOUND, "property_not_found")
        }
        ObjectPermissionDenied | VerbPermissionDenied | PropertyPermissionDenied => {
            (StatusCode::FORBIDDEN, "permission_denied")
        }
        PropertyTypeMismatch => (StatusCode::BAD_REQUEST, "invalid_value"),
        _ => (StatusCode::INTERNAL_SERVER_ERROR, "internal_error"),
    };
    (status, code, error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use moor_common::model::ObjectRef;
    use moor_var::Obj;

    async fn body(response: Response) -> (StatusCode, serde_json::Value) {
        let status = response.status();
        let bytes = to_bytes(response.into_body(), 1024).await.unwrap();
        (status, serde_json::from_slice(&bytes).unwrap())
    }

    fn task(error: SchedulerError) -> RpcError {
        RpcError::Daemon(RpcMessageError::TaskError(error))
    }

    #[tokio::test]
    async fn request_errors_get_their_own_statuses_and_codes() {
        let missing = Obj::mk_id(999);
        for (error, status, code) in [
            (
                RpcError::Daemon(RpcMessageError::PermissionDenied),
                StatusCode::UNAUTHORIZED,
                "unauthorized",
            ),
            (
                RpcError::Daemon(RpcMessageError::InvalidRequest("bad".into())),
                StatusCode::BAD_REQUEST,
                "invalid_request",
            ),
            (
                task(SchedulerError::VerbRetrievalFailed(
                    WorldStateError::ObjectNotFound(ObjectRef::Id(missing)),
                )),
                StatusCode::NOT_FOUND,
                "object_not_found",
            ),
            (
                task(SchedulerError::VerbRetrievalFailed(
                    WorldStateError::VerbNotFound(missing, "x".into()),
                )),
                StatusCode::NOT_FOUND,
                "verb_not_found",
            ),
            (
                task(SchedulerError::PropertyRetrievalFailed(
                    WorldStateError::PropertyNotFound(missing, "p".into()),
                )),
                StatusCode::NOT_FOUND,
                "property_not_found",
            ),
            (
                task(SchedulerError::PropertyRetrievalFailed(
                    WorldStateError::PropertyPermissionDenied,
                )),
                StatusCode::FORBIDDEN,
                "permission_denied",
            ),
            (
                task(SchedulerError::PropertyRetrievalFailed(
                    WorldStateError::PropertyTypeMismatch,
                )),
                StatusCode::BAD_REQUEST,
                "invalid_value",
            ),
            (
                task(SchedulerError::CommandExecutionError(
                    CommandError::NoObjectMatch,
                )),
                StatusCode::NOT_FOUND,
                "object_not_found",
            ),
            (
                RpcError::Timeout("slow".into()),
                StatusCode::SERVICE_UNAVAILABLE,
                "daemon_unavailable",
            ),
            (
                task(SchedulerError::SchedulerNotResponding),
                StatusCode::SERVICE_UNAVAILABLE,
                "daemon_unavailable",
            ),
            (
                RpcError::Daemon(RpcMessageError::InternalError("boom".into())),
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
            ),
        ] {
            let (got_status, json) = body(daemon_error_response(&error)).await;
            assert_eq!(
                (got_status, json["code"].as_str()),
                (status, Some(code)),
                "{error:?}"
            );
            assert!(json["error"].as_str().is_some_and(|m| !m.is_empty()));
        }
    }

    #[tokio::test]
    async fn server_errors_do_not_reveal_their_detail() {
        for error in [
            RpcError::CouldNotSend("private transport detail".into()),
            RpcError::Daemon(RpcMessageError::InternalError(
                "private transport detail".into(),
            )),
        ] {
            let (_, json) = body(daemon_error_response(&error)).await;
            assert!(!json.to_string().contains("private"), "{json}");
        }
    }

    #[tokio::test]
    async fn not_found_messages_name_what_was_missing() {
        let (_, json) = body(daemon_error_response(&task(
            SchedulerError::VerbRetrievalFailed(WorldStateError::VerbNotFound(
                Obj::mk_id(0),
                "no_such_verb".into(),
            )),
        )))
        .await;
        assert!(
            json["error"].as_str().unwrap().contains("no_such_verb"),
            "{json}"
        );
    }
}
