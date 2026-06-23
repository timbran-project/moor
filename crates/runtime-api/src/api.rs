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

//! Typed daemon-host API: request/reply enums and traits abstracting the
//! daemon boundary away from FlatBuffer/ZeroMQ wire details.
//!
//! The daemon side implements its runtime API and the host side holds a
//! [`RuntimeClient`]. The ZeroMQ adapter translates between these typed enums
//! and FlatBuffer messages; the in-process adapter calls the runtime API
//! directly without serialization.

use std::{net::SocketAddr, sync::Arc};

use async_trait::async_trait;
use moor_common::model::{ObjectRef, PropDef, PropPerms, VerbDef, VerbDefs};
use moor_common::tasks::{NarrativeEvent, SchedulerError};
use moor_var::{Obj, Symbol, Var};
use uuid::Uuid;

use crate::{AuthToken, ClientToken, HostType, RpcError};

// ---------------------------------------------------------------------------
// Shared payload types
// ---------------------------------------------------------------------------

/// A listener advertised by a host during registration or pong.
#[derive(Debug, Clone)]
pub struct ListenerInfo {
    pub handler_object: Obj,
    pub socket_addr: SocketAddr,
}

/// How a connection is established: fresh, reconnected, or created.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectType {
    Connected,
    Reconnected,
    Created,
    /// Transient session with no connection lifecycle (e.g. history retrieval).
    NoConnect,
}

/// Which entity to retrieve: property or verb.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntityType {
    Property,
    Verb,
}

/// A single action in a batch world-state request. The daemon fills in
/// `player`/`authority_principal` from the request's auth token; clients do
/// not supply them.
#[derive(Debug, Clone)]
pub enum BatchAction {
    RequestProperty {
        obj: ObjectRef,
        property: Symbol,
    },
    RequestProperties {
        obj: ObjectRef,
        inherited: bool,
    },
    RequestSystemProperty {
        obj: ObjectRef,
        property: Symbol,
    },
    RequestVerbs {
        obj: ObjectRef,
        inherited: bool,
    },
    RequestVerbCode {
        obj: ObjectRef,
        verb: Symbol,
    },
    ResolveObject {
        objref: ObjectRef,
    },
    ListObjects,
    RequestAllObjects,
    UpdateProperty {
        obj: ObjectRef,
        property: Symbol,
        value: Var,
    },
    ProgramVerb {
        obj: ObjectRef,
        verb_name: Symbol,
        code: Vec<String>,
    },
    GetObjectFlags {
        obj: Obj,
    },
    QueryObjects {
        parent: Option<Obj>,
        location: Option<Obj>,
        owner: Option<Obj>,
        flags_all: u16,
        flags_any: u16,
    },
}

/// A single batch entry with a client-supplied correlation id.
#[derive(Debug, Clone)]
pub struct BatchActionEntry {
    pub id: String,
    pub action: BatchAction,
}

/// How much history to recall for a player.
#[derive(Debug, Clone)]
pub enum HistoryRecall {
    SinceEvent {
        event_id: Uuid,
        limit: Option<usize>,
    },
    UntilEvent {
        event_id: Uuid,
        limit: Option<usize>,
    },
    SinceSeconds {
        seconds_ago: u64,
        limit: Option<usize>,
    },
    None,
}

/// A snapshot of a presentation available for dismissal.
#[derive(Debug, Clone)]
pub struct PresentationSnapshot {
    pub id: String,
    pub encrypted_blob: Vec<u8>,
}

/// A connection attribute key/value pair set at connection establishment.
#[derive(Debug, Clone)]
pub struct ConnectionAttribute {
    pub key: Symbol,
    pub value: Var,
}

/// Performance counter sample.
#[derive(Debug, Clone)]
pub struct CounterSample {
    pub name: Symbol,
    pub count: i64,
    pub total_cumulative_ns: i64,
}

/// A category of performance counters.
#[derive(Debug, Clone)]
pub struct CounterCategory {
    pub category: Symbol,
    pub counters: Vec<CounterSample>,
}

/// Server feature flags reported to hosts.
#[derive(Debug, Clone, Default)]
pub struct ServerFeatures {
    pub persistent_tasks: bool,
    pub rich_notify: bool,
    pub lexical_scopes: bool,
    pub type_dispatch: bool,
    pub flyweight_type: bool,
    pub list_comprehensions: bool,
    pub bool_type: bool,
    pub use_boolean_returns: bool,
    pub symbol_type: bool,
    pub use_symbols_in_builtins: bool,
    pub custom_errors: bool,
    pub use_uuobjids: bool,
    pub enable_eventlog: bool,
    pub anonymous_objects: bool,
}

/// Information about one object, for object-browsing UIs.
#[derive(Debug, Clone)]
pub struct ObjectInfo {
    pub obj: Obj,
    pub name: Option<Symbol>,
    pub parent: Option<Obj>,
    pub owner: Obj,
    pub flags: u16,
    pub location: Option<Obj>,
    pub contents_count: u32,
    pub verbs_count: u32,
    pub properties_count: u32,
}

/// Result of a batch world-state action.
#[derive(Debug, Clone)]
pub enum WorldStateResult {
    Property(PropDef, PropPerms, Var),
    Properties(Vec<(PropDef, PropPerms)>),
    SystemProperty(Var),
    Verbs(VerbDefs),
    VerbCode(VerbDef, Vec<String>),
    ResolvedObject(Var),
    ObjectsList(Vec<ObjectInfo>),
    AllObjects(Vec<Obj>),
    PropertyUpdated,
    ObjectFlags(u16),
    QueriedObjects(Vec<Obj>),
}

/// A single result entry in a batch reply, keyed by the request's correlation id.
#[derive(Debug, Clone)]
pub struct WorldStateResultEntry {
    pub id: String,
    pub result: WorldStateResult,
}

/// Outcome of programming a verb.
#[derive(Debug, Clone)]
pub enum VerbProgramResponse {
    Success { obj: Obj, verb_name: String },
    Failure { error: SchedulerError },
}

/// Outcome of invoking a verb for its return value (eval, system verb, etc.).
#[derive(Debug, Clone)]
pub enum VerbCallResponse {
    Success {
        result: Var,
        output: Vec<moor_common::tasks::NarrativeEvent>,
    },
    Error {
        error: SchedulerError,
    },
}

/// Outcome of invoking a system handler.
#[derive(Debug, Clone)]
pub enum SystemHandlerResponse {
    Success { result: Var },
    Error { error: SchedulerError },
}

/// A historical narrative event from the event log.
#[derive(Debug, Clone)]
pub struct HistoricalNarrativeEvent {
    pub event_id: Uuid,
    pub timestamp: u64,
    pub player: Obj,
    pub encrypted_blob: Vec<u8>,
}

/// A page of history for a player.
#[derive(Debug, Clone)]
pub struct HistoryResponse {
    pub events: Vec<HistoricalNarrativeEvent>,
    pub time_range_start: u64,
    pub time_range_end: u64,
    pub total_events: u64,
    pub has_more_before: bool,
    pub earliest_event_id: Option<Uuid>,
    pub latest_event_id: Option<Uuid>,
}

/// A decoded per-client event.
#[derive(Debug, Clone)]
pub struct ClientEventMessage {
    pub event: ClientEvent,
}

/// Events the daemon publishes to one client session.
#[derive(Debug, Clone)]
pub enum ClientEvent {
    Narrative {
        player: Obj,
        event: NarrativeEvent,
    },
    RequestInput {
        request_id: Uuid,
        metadata: Vec<(Symbol, Var)>,
    },
    SystemMessage {
        player: Obj,
        message: String,
    },
    Disconnect,
    TaskError {
        task_id: u64,
        error: SchedulerError,
    },
    TaskSuccess {
        task_id: u64,
        result: Var,
    },
    TaskSuspended {
        task_id: u64,
    },
    PlayerSwitched {
        new_player: Obj,
        new_auth_token: AuthToken,
    },
    SetConnectionOption {
        connection_obj: Obj,
        option_name: Symbol,
        value: Var,
    },
    CredentialsUpdated {
        client_id: Uuid,
        client_token: ClientToken,
    },
}

/// A decoded broadcast event.
#[derive(Debug, Clone)]
pub struct BroadcastEventMessage {
    pub event: BroadcastEvent,
}

/// Broadcast events sent to all client hosts.
#[derive(Debug, Clone)]
pub enum BroadcastEvent {
    PingPong,
}

/// Host lifecycle broadcast events.
#[derive(Debug, Clone)]
pub enum HostBroadcastEvent {
    Listen {
        handler_object: Obj,
        host_type: HostType,
        port: u16,
        options: Vec<(Symbol, Var)>,
    },
    Unlisten {
        host_type: HostType,
        port: u16,
    },
    PingPong,
}

/// Per-client event subscription.
#[async_trait]
pub trait ClientEventSubscription: Send {
    async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError>;
}

/// Broadcast event subscription shared by client sessions.
#[async_trait]
pub trait ClientBroadcastSubscription: Send {
    async fn recv_client_broadcast(&mut self) -> Result<BroadcastEventMessage, RpcError>;
}

pub type ClientSubscriptions = (
    Box<dyn ClientEventSubscription>,
    Box<dyn ClientBroadcastSubscription>,
);

/// Host broadcast event subscription.
#[async_trait]
pub trait HostEventSubscription: Send {
    async fn recv_host_event(&mut self) -> Result<HostBroadcastEvent, RpcError>;
}

/// Host-side factory for daemon request/reply and event subscriptions.
pub trait HostServices: Send + Sync {
    fn runtime_client(&self) -> Arc<dyn RuntimeClient>;

    fn client_subscriptions(&self, client_id: Uuid) -> Result<ClientSubscriptions, RpcError>;

    fn host_events(&self) -> Result<Box<dyn HostEventSubscription>, RpcError>;
}

// ---------------------------------------------------------------------------
// Host requests and replies
// ---------------------------------------------------------------------------

/// Requests a host sends to the daemon.
#[derive(Debug, Clone)]
pub enum HostRequest {
    RegisterHost {
        timestamp: u64,
        host_type: HostType,
        listeners: Vec<ListenerInfo>,
    },
    HostPong {
        timestamp: u64,
        host_type: HostType,
        listeners: Vec<ListenerInfo>,
    },
    DetachHost,
    RequestPerformanceCounters,
    GetServerFeatures,
}

/// Replies the daemon returns to a host.
#[derive(Debug, Clone)]
pub enum HostReply {
    Ack,
    Reject {
        reason: String,
    },
    PerformanceCounters {
        timestamp: u64,
        counters: Vec<CounterCategory>,
    },
    ServerFeatures(ServerFeatures),
}

// ---------------------------------------------------------------------------
// Client requests and replies
// ---------------------------------------------------------------------------

/// Requests a client (via a host) sends to the daemon.
#[derive(Debug, Clone)]
pub enum ClientRequest {
    ConnectionEstablish {
        peer_addr: String,
        local_port: u16,
        remote_port: u16,
        acceptable_content_types: Option<Vec<Symbol>>,
        connection_attributes: Option<Vec<ConnectionAttribute>>,
    },
    Reattach {
        client_token: ClientToken,
        auth_token: AuthToken,
        peer_addr: Option<String>,
        local_port: Option<u16>,
        remote_port: Option<u16>,
        acceptable_content_types: Option<Vec<Symbol>>,
        connection_attributes: Option<Vec<ConnectionAttribute>>,
    },
    ClientPong {
        client_token: ClientToken,
        client_sys_time: u64,
        player: Obj,
        host_type: HostType,
        socket_addr: String,
    },
    RequestSysProp {
        auth_token: Option<AuthToken>,
        object: ObjectRef,
        property: Symbol,
    },
    LoginCommand {
        client_token: ClientToken,
        handler_object: Obj,
        connect_args: Vec<String>,
        do_attach: bool,
        event_log_pubkey: Option<String>,
        registration_data: Option<Var>,
    },
    Attach {
        auth_token: AuthToken,
        connect_type: ConnectType,
        handler_object: Obj,
        peer_addr: String,
        local_port: u16,
        remote_port: u16,
        acceptable_content_types: Option<Vec<Symbol>>,
    },
    Command {
        client_token: ClientToken,
        auth_token: AuthToken,
        handler_object: Obj,
        command: String,
    },
    Detach {
        client_token: ClientToken,
        disconnected: bool,
    },
    RequestedInput {
        client_token: ClientToken,
        auth_token: AuthToken,
        request_id: Uuid,
        input: Var,
    },
    OutOfBand {
        client_token: ClientToken,
        auth_token: AuthToken,
        handler_object: Obj,
        args: Var,
        argstr: Var,
    },
    Eval {
        client_token: ClientToken,
        auth_token: AuthToken,
        expression: String,
    },
    InvokeVerb {
        client_token: ClientToken,
        auth_token: AuthToken,
        object: ObjectRef,
        verb: Symbol,
        args: Vec<Var>,
    },
    Retrieve {
        auth_token: AuthToken,
        object: ObjectRef,
        entity_type: EntityType,
        name: Symbol,
    },
    Properties {
        auth_token: AuthToken,
        object: ObjectRef,
        inherited: bool,
    },
    Verbs {
        auth_token: AuthToken,
        object: ObjectRef,
        inherited: bool,
    },
    RequestHistory {
        auth_token: AuthToken,
        recall: HistoryRecall,
    },
    RequestCurrentPresentations {
        auth_token: AuthToken,
    },
    DismissPresentation {
        auth_token: AuthToken,
        presentation_id: String,
    },
    SetClientAttribute {
        client_token: ClientToken,
        auth_token: AuthToken,
        key: Symbol,
        value: Option<Var>,
    },
    Program {
        client_token: ClientToken,
        auth_token: AuthToken,
        object: ObjectRef,
        verb: Symbol,
        code: Vec<String>,
    },
    GetEventLogPublicKey {
        auth_token: AuthToken,
    },
    SetEventLogPublicKey {
        auth_token: AuthToken,
        public_key: String,
    },
    DeleteEventLogHistory {
        auth_token: AuthToken,
    },
    ListObjects {
        auth_token: AuthToken,
    },
    UpdateProperty {
        auth_token: AuthToken,
        object: ObjectRef,
        property: Symbol,
        value: Var,
    },
    InvokeSystemHandler {
        host_id: Uuid,
        handler_type: String,
        args: Vec<Var>,
        auth_token: Option<AuthToken>,
    },
    CallSystemVerb {
        auth_token: Option<AuthToken>,
        verb: Symbol,
        args: Vec<Var>,
    },
    BatchWorldState {
        auth_token: AuthToken,
        actions: Vec<BatchActionEntry>,
        rollback: bool,
    },
    Resolve {
        auth_token: AuthToken,
        objref: ObjectRef,
    },
}

/// Replies the daemon returns to a client (via a host).
#[derive(Debug, Clone)]
pub enum ClientReply {
    NewConnection {
        client_token: ClientToken,
        connection_obj: Obj,
    },
    LoginResult {
        success: bool,
        auth_token: Option<AuthToken>,
        connect_type: ConnectType,
        player: Option<Obj>,
        player_flags: u16,
    },
    AttachResult {
        success: bool,
        client_token: Option<ClientToken>,
        player: Option<Obj>,
        player_flags: u16,
    },
    SysPropValue {
        value: Option<Var>,
    },
    TaskSubmitted {
        task_id: u64,
    },
    InputThanks,
    EvalResult {
        result: Var,
    },
    ThanksPong {
        timestamp: u64,
    },
    VerbsReply {
        verbs: Vec<VerbDef>,
    },
    PropertiesReply {
        properties: Vec<(PropDef, PropPerms)>,
    },
    VerbProgramResponseReply {
        response: VerbProgramResponse,
    },
    PropertyValue {
        prop_info: (PropDef, PropPerms),
        value: Var,
    },
    VerbValue {
        verb_info: VerbDef,
        code: Vec<String>,
    },
    ResolveResult {
        result: Var,
    },
    HistoryResponseReply {
        response: HistoryResponse,
    },
    CurrentPresentations {
        presentations: Vec<PresentationSnapshot>,
    },
    PresentationDismissed,
    ClientAttributeSet,
    Disconnected,
    EventLogPublicKey {
        public_key: String,
    },
    EventLogHistoryDeleted {
        success: bool,
    },
    ListObjectsReply {
        objects: Vec<ObjectInfo>,
    },
    PropertyUpdated,
    SystemHandlerResponseReply {
        response: SystemHandlerResponse,
    },
    VerbCallResponse {
        response: VerbCallResponse,
    },
    BatchWorldStateReply {
        results: Vec<WorldStateResultEntry>,
    },
}

// ---------------------------------------------------------------------------
// Host-side client trait
// ---------------------------------------------------------------------------

/// Host-side client for talking to the runtime (RPC daemon or local) via typed requests.
///
/// `RpcClient` implements this by encoding to FlatBuffer wire messages and
/// decoding the reply. `LocalRuntimeClient` calls the daemon runtime API directly.
#[async_trait]
pub trait RuntimeClient: Send + Sync {
    async fn client_call(
        &self,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcError>;

    async fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, RpcError>;
}
