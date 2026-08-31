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

//! HTTP endpoint handlers that translate REST requests into daemon RPC calls.

mod batch;
mod commands;
mod event_log;
mod objects;
mod props;
mod verbs;
mod webhooks;

pub use batch::batch_handler;
pub use commands::command_handler;
pub use event_log::{
    delete_history_handler, dismiss_presentation_handler, get_pubkey_handler, history_handler,
    presentations_handler, set_pubkey_handler,
};
pub use objects::{list_objects_handler, query_objects_handler, update_property_handler};
pub use props::{properties_handler, property_retrieval_handler};
pub use verbs::{invoke_verb_handler, verb_program_handler, verb_retrieval_handler, verbs_handler};
pub use webhooks::web_hook_handler;

use axum::http::StatusCode;
use moor_runtime_api::{api::ClientReply, api_codec::encode_invocation_response};
use moor_schema::rpc as moor_rpc;
use tracing::error;

pub(super) fn invocation_response(
    reply: ClientReply,
) -> Result<moor_rpc::InvocationResponse, StatusCode> {
    let ClientReply::InvocationResponse { response } = reply else {
        error!(?reply, "Unexpected daemon reply to captured invocation");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    };
    encode_invocation_response(response).map_err(|error| {
        error!(?error, "Failed to encode invocation response");
        StatusCode::INTERNAL_SERVER_ERROR
    })
}
