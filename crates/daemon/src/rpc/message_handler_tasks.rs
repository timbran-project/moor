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

use crate::rpc::{
    message_handler::{
        RpcMessageHandler, USER_CONNECTED_SYM, USER_CREATED_SYM, USER_DISCONNECTED_SYM,
        USER_RECONNECTED_SYM,
    },
    session::RpcSession,
};
use eyre::{Context, Error};
use moor_common::model::ObjectRef;
use moor_kernel::SchedulerClient;
use moor_schema::rpc as moor_rpc;
use moor_var::{List, Obj, SYSTEM_OBJECT, v_empty_str, v_obj};
use std::sync::Arc;
use uuid::Uuid;

impl RpcMessageHandler {
    pub(crate) fn submit_connected_task(
        &self,
        handler_object: &Obj,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        player: &Obj,
        connection: &Obj,
        initiation_type: moor_rpc::ConnectType,
    ) -> Result<(), Error> {
        let session = Arc::new(RpcSession::new(
            client_id,
            *connection,
            self.event_log.clone(),
            self.mailbox_sender.clone(),
        ));

        let connected_verb = match initiation_type {
            moor_rpc::ConnectType::Connected => *USER_CONNECTED_SYM,
            moor_rpc::ConnectType::Reconnected => *USER_RECONNECTED_SYM,
            moor_rpc::ConnectType::Created => *USER_CREATED_SYM,
            moor_rpc::ConnectType::NoConnect => {
                unreachable!("NoConnect should never call submit_connected_task")
            }
        };
        scheduler_client
            .submit_verb_task(
                player,
                &ObjectRef::Id(*handler_object),
                connected_verb,
                List::mk_list(&[v_obj(*player)]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                session,
            )
            .with_context(|| "could not submit 'connected' task")?;
        Ok(())
    }

    pub(crate) fn submit_disconnected_task(
        &self,
        handler_object: &Obj,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        player: &Obj,
        connection: &Obj,
    ) -> Result<(), Error> {
        let session = Arc::new(RpcSession::new(
            client_id,
            *connection,
            self.event_log.clone(),
            self.mailbox_sender.clone(),
        ));

        scheduler_client
            .submit_verb_task(
                player,
                &ObjectRef::Id(*handler_object),
                *USER_DISCONNECTED_SYM,
                List::mk_list(&[v_obj(*player)]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                session,
            )
            .with_context(|| "could not submit 'connected' task")?;
        Ok(())
    }
}
