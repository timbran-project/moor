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

//! Object browser endpoints

use crate::host::{
    auth::StatelessAuth,
    flatbuffer_response,
    negotiate::{
        BOTH_FORMATS, ResponseFormat, TEXT_PLAIN_CONTENT_TYPE, negotiate_response_format,
        reply_result_to_json, require_content_type,
    },
    web_host,
};
use axum::{
    body::Bytes,
    extract::{Path, Query},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use moor_common::{
    model::{CompileError, ObjectRef, WorldStateError},
    tasks::{CommandError, SchedulerError},
};
use moor_compiler::ObjDefParseError;
use moor_runtime_api::api::{BatchAction, BatchActionEntry, ClientRequest};
use moor_runtime_api::{RpcError, RpcMessageError, api_codec::encode_client_success_bytes};
use moor_var::Symbol;
use serde::Deserialize;
use tracing::error;

#[derive(Deserialize)]
pub struct QueryObjectsQuery {
    parent: Option<String>,
    location: Option<String>,
    owner: Option<String>,
    flags_all: Option<u16>,
    flags_any: Option<u16>,
}

pub async fn list_objects_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let list_msg = ClientRequest::ListObjects { auth_token };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, list_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

pub async fn query_objects_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Query(query): Query<QueryObjectsQuery>,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let parent = query
        .parent
        .as_deref()
        .and_then(ObjectRef::parse_curie)
        .and_then(|r| match r {
            ObjectRef::Id(obj) => Some(obj),
            _ => None,
        });
    let location = query
        .location
        .as_deref()
        .and_then(ObjectRef::parse_curie)
        .and_then(|r| match r {
            ObjectRef::Id(obj) => Some(obj),
            _ => None,
        });
    let owner = query
        .owner
        .as_deref()
        .and_then(ObjectRef::parse_curie)
        .and_then(|r| match r {
            ObjectRef::Id(obj) => Some(obj),
            _ => None,
        });

    let batch_msg = ClientRequest::BatchWorldState {
        auth_token,
        actions: vec![BatchActionEntry {
            id: "query".to_string(),
            action: BatchAction::QueryObjects {
                parent,
                location,
                owner,
                flags_all: query.flags_all.unwrap_or(0),
                flags_any: query.flags_any.unwrap_or(0),
            },
        }],
        rollback: true,
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, batch_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

pub async fn update_property_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Path((object, prop_name)): Path<(String, String)>,
    body: Bytes,
) -> Response {
    if let Err(status) = require_content_type(
        header_map.get(header::CONTENT_TYPE),
        &[TEXT_PLAIN_CONTENT_TYPE],
        true, // allow missing for backwards compat
    ) {
        return status.into_response();
    }
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let Some(object_ref) = ObjectRef::parse_curie(&object) else {
        return property_error(
            StatusCode::BAD_REQUEST,
            "invalid_object",
            "Invalid object reference",
        );
    };

    let prop_symbol = Symbol::mk(&prop_name);

    let literal_str = match std::str::from_utf8(&body) {
        Ok(s) => s,
        Err(_) => {
            return property_error(
                StatusCode::BAD_REQUEST,
                "invalid_literal",
                "Property value must be UTF-8 text",
            );
        }
    };

    let value = match moor_compiler::parse_literal_value(literal_str) {
        Ok(v) => v,
        Err(ObjDefParseError::ParseError(CompileError::ParseError {
            error_position,
            message,
            ..
        })) => {
            let (line, column) = error_position.line_col;
            return (
                StatusCode::BAD_REQUEST,
                axum::Json(serde_json::json!({
                    "code": "invalid_literal",
                    "error": format!("Line {line}, column {column}: {message}"),
                    "line": line,
                    "column": column,
                })),
            )
                .into_response();
        }
        Err(e) => {
            return property_error(StatusCode::BAD_REQUEST, "invalid_literal", &e.to_string());
        }
    };

    let update_msg = ClientRequest::UpdateProperty {
        auth_token,
        object: object_ref,
        property: prop_symbol,
        value,
    };

    let reply = match rpc_client.client_call(client_id, update_msg).await {
        Ok(reply) => reply,
        Err(error) => return property_rpc_error(error),
    };
    let reply_bytes = match encode_client_success_bytes(reply) {
        Ok(bytes) => bytes,
        Err(error) => {
            error!(?error, "Failed to encode property update reply");
            return property_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
                "Unable to update property",
            );
        }
    };

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

// Errors use JSON even when the requested success format is FlatBuffers.
fn property_error(status: StatusCode, code: &str, message: &str) -> Response {
    (
        status,
        axum::Json(serde_json::json!({"code": code, "error": message})),
    )
        .into_response()
}

fn property_rpc_error(error: RpcError) -> Response {
    use RpcMessageError::{InvalidRequest, PermissionDenied, TaskError};
    use SchedulerError::{CommandExecutionError, PropertyRetrievalFailed};
    use WorldStateError::*;
    let (status, code, message) = match &error {
        RpcError::Daemon(
            PermissionDenied
            | TaskError(PropertyRetrievalFailed(PropertyPermissionDenied | ObjectPermissionDenied)),
        ) => (
            StatusCode::FORBIDDEN,
            "permission_denied",
            "Property permission denied",
        ),
        RpcError::Daemon(TaskError(PropertyRetrievalFailed(
            PropertyNotFound(..) | PropertyDefinitionNotFound(..),
        ))) => (
            StatusCode::NOT_FOUND,
            "property_not_found",
            "Property not found",
        ),
        RpcError::Daemon(TaskError(
            CommandExecutionError(CommandError::NoObjectMatch)
            | PropertyRetrievalFailed(ObjectNotFound(..)),
        )) => (
            StatusCode::NOT_FOUND,
            "object_not_found",
            "Object not found",
        ),
        RpcError::Daemon(TaskError(PropertyRetrievalFailed(PropertyTypeMismatch))) => (
            StatusCode::BAD_REQUEST,
            "invalid_value",
            "Property value has the wrong type",
        ),
        RpcError::Daemon(InvalidRequest(message)) => {
            (StatusCode::BAD_REQUEST, "invalid_request", message.as_str())
        }
        _ => {
            error!(?error, "Property update failed");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
                "Unable to update property",
            )
        }
    };
    property_error(status, code, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use moor_common::{
        model::WorldStateError,
        tasks::{CommandError, SchedulerError},
    };
    use moor_runtime_api::{
        AuthToken, RpcError, RpcMessageError,
        api::{ClientReply, HostReply, HostRequest, RuntimeClient},
    };
    use std::sync::{Arc, Mutex};
    use uuid::Uuid;

    struct PropertyRuntime {
        reply: Mutex<Option<Result<ClientReply, RpcError>>>,
        requests: Mutex<Vec<ClientRequest>>,
    }

    #[async_trait::async_trait]
    impl RuntimeClient for PropertyRuntime {
        async fn client_call(
            &self,
            _: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, RpcError> {
            self.requests.lock().unwrap().push(request);
            self.reply
                .lock()
                .unwrap()
                .take()
                .expect("unexpected RPC call")
        }
        async fn host_call(&self, _: Uuid, _: HostRequest) -> Result<HostReply, RpcError> {
            panic!("unexpected host call")
        }
    }

    async fn update(
        body: &str,
        reply: Option<Result<ClientReply, RpcError>>,
        accept: &str,
    ) -> (Response, Arc<PropertyRuntime>) {
        let runtime = Arc::new(PropertyRuntime {
            reply: Mutex::new(reply),
            requests: Mutex::new(vec![]),
        });
        let mut headers = HeaderMap::new();
        headers.insert(header::CONTENT_TYPE, "text/plain".parse().unwrap());
        headers.insert(header::ACCEPT, accept.parse().unwrap());
        let response = update_property_handler(
            StatelessAuth {
                auth_token: AuthToken("fixture".into()),
                client_id: Uuid::new_v4(),
                rpc_client: runtime.clone(),
            },
            headers,
            Path(("oid:42".into(), "payload".into())),
            Bytes::copy_from_slice(body.as_bytes()),
        )
        .await;
        (response, runtime)
    }

    async fn error_body(response: Response) -> serde_json::Value {
        assert_eq!(response.headers()[header::CONTENT_TYPE], "application/json");
        serde_json::from_slice(&to_bytes(response.into_body(), 16_384).await.unwrap()).unwrap()
    }

    #[tokio::test]
    async fn property_update_literal_error_has_location_and_never_reaches_the_daemon() {
        let (response, runtime) = update("{1,\n2", None, "application/x-flatbuffers").await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let body = error_body(response).await;
        assert_eq!(body["code"], "invalid_literal");
        assert_eq!(body["line"], 2);
        assert!(body["column"].as_u64().unwrap() > 0);
        assert!(body["error"].as_str().unwrap().contains("expected '}'"));
        assert!(runtime.requests.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn property_update_reports_denied_and_missing_targets_as_client_errors() {
        for (error, status, code) in [
            (
                SchedulerError::PropertyRetrievalFailed(WorldStateError::PropertyPermissionDenied),
                StatusCode::FORBIDDEN,
                "permission_denied",
            ),
            (
                SchedulerError::PropertyRetrievalFailed(WorldStateError::PropertyNotFound(
                    moor_var::Obj::mk_id(42),
                    "payload".into(),
                )),
                StatusCode::NOT_FOUND,
                "property_not_found",
            ),
            (
                SchedulerError::CommandExecutionError(CommandError::NoObjectMatch),
                StatusCode::NOT_FOUND,
                "object_not_found",
            ),
        ] {
            let (response, _) = update(
                "7",
                Some(Err(RpcError::Daemon(RpcMessageError::TaskError(error)))),
                "application/x-flatbuffers",
            )
            .await;
            assert_eq!(response.status(), status);
            let body = error_body(response).await;
            assert_eq!(body["code"], code);
            assert!(!body["error"].as_str().unwrap().is_empty());
        }
    }

    #[tokio::test]
    async fn property_update_keeps_success_formats_and_does_not_expose_internal_errors() {
        for accept in ["application/x-flatbuffers", "application/json"] {
            let (response, runtime) = update(
                "[\"enabled\" -> true]",
                Some(Ok(ClientReply::PropertyUpdated)),
                accept,
            )
            .await;
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(response.headers()[header::CONTENT_TYPE], accept);
            let requests = runtime.requests.lock().unwrap();
            let ClientRequest::UpdateProperty {
                object,
                property,
                value,
                ..
            } = &requests[0]
            else {
                panic!("wrong request")
            };
            assert_eq!(*object, ObjectRef::Id(moor_var::Obj::mk_id(42)));
            assert_eq!(*property, Symbol::mk("payload"));
            assert_eq!(
                *value,
                moor_compiler::parse_literal_value("[\"enabled\" -> true]").unwrap()
            );
        }
        let (response, _) = update(
            "7",
            Some(Err(RpcError::CouldNotSend(
                "private transport detail".into(),
            ))),
            "application/json",
        )
        .await;
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        let body = error_body(response).await;
        assert_eq!(body["code"], "internal_error");
        assert!(!body.to_string().contains("private transport detail"));
    }
}
