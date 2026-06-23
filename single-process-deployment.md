# Single-Process Deployment

## Problem

mooR currently deploys as several cooperating processes:

- `moor-daemon` owns the database, scheduler, VM, connection registry, task monitor, event log, host
  enrollment, worker routing, and RPC server.
- `moor-telnet-host` listens for line-oriented TCP/Telnet clients and talks to the daemon over
  ZeroMQ request/reply plus pub/sub.
- `moor-web-host` listens for HTTP/WebSocket/WebRTC clients and talks to the daemon over the same
  ZeroMQ RPC and event channels.

This shape is useful for clustered or split-host deployments, but it is heavier than necessary for a
small personal server, local development, demos, or package-based installs where all components run
on one machine. A single-process deployment should provide the normal daemon, telnet, and web
experience from one process and one config surface, without requiring ZeroMQ host enrollment,
CURVE/ZAP, or multiple systemd services.

## Goal

Add a new `moor` binary that runs the daemon runtime, telnet host, and web host in one process.

The first version should preserve existing daemon/session semantics. It should not create a parallel
scheduler API or bypass connection/session/auth behavior.

There are two useful milestones:

- Stage 1: one binary, one shared ZeroMQ context, and `inproc://` endpoints for daemon/host RPC and
  pub/sub. This keeps the current FlatBuffer protocol and host code shape, but removes external
  socket files, TCP RPC listeners, CURVE/ZAP, multiple processes, and multiple service units.
- Stage 2: replace the in-process FlatBuffer boundary with a typed Rust daemon API. FlatBuffers
  remain the split-process wire format, with a ZeroMQ adapter translating between wire messages and
  typed daemon requests/replies/events.

## Current Status

The single-process binary exists as `crates/daemon/src/bin/moor.rs`. The split-process daemon entry
point is `crates/daemon/src/bin/moor-daemon.rs`.

The current single-process path uses typed in-process services for host/runtime request-reply and
event delivery:

- `moor_runtime_api::api::RuntimeClient` is the host-side typed request client trait.
- `crates/daemon/src/runtime/api.rs` defines the daemon-side `RuntimeApi`.
- `LocalRuntimeClient`, `LocalEventBus`, and `LocalRuntimeServices` provide the in-process adapter.
- `RpcClient` remains the ZeroMQ-backed split-process adapter and implements `RuntimeClient`.

FlatBuffers remain the split-process wire format. The daemon `rpc` module owns FlatBuffer
decode/encode and ZeroMQ transport handling; the daemon `runtime` module owns typed runtime APIs and
local in-process implementations.

The default development workflow is `npm run full:dev`, which runs Meadow plus `npm run moor:dev`.
That script uses the checked-in `moor-dev.yaml` unless `MOOR_CONFIG` is set.

## Non-Goals

- Do not remove the existing clustered deployment model.
- Do not remove ZeroMQ RPC, host enrollment, CURVE, workers, or split host binaries.
- Do not rewrite telnet or web sessions to call `SchedulerClient` directly in the first pass.
- Do not remove the FlatBuffer protocol from the split deployment path.
- Do not require external worker clustering in single-process deployment. The `moor` binary can run
  selected embedded workers over internal endpoints, while split deployments keep external workers.

## Current Seams

The daemon already has a useful server-side abstraction:

- `crates/daemon/src/rpc/message_handler.rs`
  - `MessageHandler` owns daemon RPC business logic.
  - It currently accepts FlatBuffer refs and produces daemon reply structs.
  - Most request handlers immediately extract local types such as `Obj`, `Var`, `Symbol`, tokens,
    object refs, strings, UUIDs, and listener addresses before doing daemon work.
- `crates/daemon/src/rpc/transport.rs`
  - `Transport` owns publishing and request-loop mechanics.
  - `RpcTransport` is the current ZeroMQ implementation.
- `crates/daemon/src/rpc/session.rs`
  - VM sessions send `SessionActions` into the daemon RPC/event layer.

The host side is more tightly coupled to ZeroMQ:

- `moor_zmq_client::rpc_client::RpcClient` owns ZeroMQ request/reply sockets.
- `moor_zmq_client::pubsub_client` reads client and broadcast events from `tmq::Subscribe`.
- Telnet and web sessions store `RpcClient` and `tmq::Subscribe` directly.
- Host lifecycle uses `start_host_session()` and `process_hosts_events()`, which are
  ZeroMQ-specific.
- `TaskClient` wraps `RpcClient` plus ZeroMQ pub/sub for HTTP verb invocation.

For Stage 1 the central work is runtime assembly and sharing a single ZeroMQ context. For Stage 2
the central work is extracting the daemon request/reply/event API from the current wire schema, then
adapting ZeroMQ and single-process deployment to that API.

## Target Architecture

```text
               split deploy                              stage 1 single-process

 telnet/web process                                      moor process
      |                                                       |
      | RpcClient + Subscribe                                | RpcClient + Subscribe
      v                                                       v
 FlatBuffer ZeroMQ  ----------------------->          FlatBuffer ZeroMQ inproc
      |                                                       |
      v                                                       v
 moor-daemon process                                  daemon runtime + scheduler
```

The same high-level host/session code should work in both modes:

- In split mode, host code uses a ZeroMQ-backed client and pub/sub subscription.
- In Stage 1 single-process mode, host code still uses ZeroMQ-backed clients and subscriptions, but
  the endpoints are `inproc://` and all sockets share one context.
- In Stage 2 single-process mode, host code uses an in-process client and in-process event
  subscriptions.
- Stage 2 shares the same typed request/reply/event model across split and single-process modes.

## Stage 2 Proposed Abstractions

### Typed Daemon API

Add typed request/reply enums near the daemon RPC layer or in a small shared daemon API crate:

```rust
pub enum HostRequest {
    RegisterHost { host_type: HostType, listeners: Vec<ListenerInfo> },
    HostPong { listeners: Vec<ListenerInfo> },
    GetServerFeatures,
}

pub enum ClientRequest {
    ConnectionEstablish(ConnectionEstablishRequest),
    Reattach(ReattachRequest),
    ClientPong(ClientPongRequest),
    RequestSysProp(RequestSysPropRequest),
    LoginCommand(LoginCommandRequest),
    Attach(AttachRequest),
    Command(CommandRequest),
    Detach(DetachRequest),
    RequestedInput(RequestedInputRequest),
    OutOfBand(OutOfBandRequest),
    Eval(EvalRequest),
    InvokeVerb(InvokeVerbRequest),
    Retrieve(RetrieveRequest),
    Resolve(ResolveRequest),
    Properties(PropertiesRequest),
    Verbs(VerbsRequest),
    RequestHistory(RequestHistoryRequest),
    RequestCurrentPresentations(CurrentPresentationsRequest),
    DismissPresentation(DismissPresentationRequest),
    SetClientAttribute(SetClientAttributeRequest),
    Program(ProgramRequest),
    GetEventLogPublicKey(GetEventLogPublicKeyRequest),
    SetEventLogPublicKey(SetEventLogPublicKeyRequest),
    DeleteEventLogHistory(DeleteEventLogHistoryRequest),
    ListObjects(ListObjectsRequest),
    UpdateProperty(UpdatePropertyRequest),
    InvokeSystemHandler(InvokeSystemHandlerRequest),
    CallSystemVerb(CallSystemVerbRequest),
    BatchWorldState(BatchWorldStateRequest),
}
```

`RpcMessageHandler` should move toward methods that accept those typed requests:

```rust
pub trait RuntimeApi: Send + Sync {
    fn handle_host_request(
        &self,
        host_id: Uuid,
        request: HostRequest,
    ) -> Result<HostReply, RpcMessageError>;

    fn handle_client_request(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcMessageError>;
}
```

The current FlatBuffer `MessageHandler` becomes an adapter:

- decode FlatBuffer request refs into typed request enums
- call `RuntimeApi`
- encode typed replies back to FlatBuffers for ZeroMQ callers

Single-process deployment calls `RuntimeApi` directly and does not serialize requests or replies
through FlatBuffers.

### Request/Reply Client

The client trait lives in `moor-runtime-api`:

```rust
#[async_trait]
pub trait RuntimeClient: Send + Sync + Clone + 'static {
    async fn client_call(
        &self,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcError>;

    async fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, RpcError>;
}
```

`RpcClient` remains the ZeroMQ implementation, but it converts typed requests into FlatBuffer wire
messages and decodes FlatBuffer replies back into typed replies. `LocalRuntimeClient` invokes
`RuntimeApi` directly with a `SchedulerClient`.

### Event Subscriptions

Add an event subscription abstraction for the three existing event classes:

- per-client events keyed by `client_id`
- client broadcasts
- host broadcasts

```rust
#[async_trait]
pub trait ClientEventSubscription: Send {
    async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError>;
    async fn recv_client_broadcast(&mut self) -> Result<BroadcastEventMessage, RpcError>;
}

#[async_trait]
pub trait HostEventSubscription: Send {
    async fn recv_host_event(&mut self) -> Result<HostBroadcastEventMessage, RpcError>;
}
```

The existing ZeroMQ path wraps `tmq::Subscribe` and converts FlatBuffer events into typed events.
The in-process path wraps receiver handles from an `InProcessEventBus`.

## Stage 1 `inproc://` Transport

Stage 1 should continue using ZeroMQ sockets, but with all daemon and host sockets created from one
shared `zmq::Context`/`tmq::Context` and routed over `inproc://` endpoints.

Stage 1 is a packaging/runtime assembly change, not an RPC architecture change. It should use the
Phase 0.5 library APIs and preserve the current FlatBuffer request/reply/event path.

### Stage 1 Binary Ownership

The combined binary should own process-level concerns for the single-process deployment:

- CLI args and YAML config loading for the combined process
- logging/tracing setup
- `color_eyre::install()`
- banner/output
- Tokio runtime creation
- Unix signal handling
- one shared kill switch
- one shared ZeroMQ context

The daemon, telnet, and web libraries should continue to own only runtime assembly. The combined
binary should construct:

- `moor_daemon::DaemonRuntimeConfig`
- `moor_daemon::DaemonRuntime`
- `moor_telnet_host::TelnetHostConfig`
- `moor_telnet_host::HostRuntime`
- `moor_web_host::WebHostConfig`
- `moor_web_host::HostRuntime`

### Stage 1 Crate Shape

Preferred first cut:

```text
crates/daemon/
  src/bin/moor-daemon.rs # existing moor-daemon split-process binary
  src/bin/moor.rs      # new single-process binary
```

This keeps the single-process entry point close to daemon runtime setup. If daemon package metadata
or optional host dependencies become awkward, move the exact same assembly code into a small
`crates/moor` package later.

### Stage 1 Endpoint Plan

Use fixed internal endpoints for the first pass:

```text
inproc://moor-services-rpc
inproc://moor-services-events
```

RPC and events should use `inproc://` endpoints until the remaining daemon RPC loop is replaced by
typed local services. Embedded workers should use typed local worker services, not internal worker
endpoints. Do not expose enrollment/CURVE for these internal endpoints:

- no CURVE/ZAP for daemon-to-host traffic
- no enrollment server for the internal host listeners
- no IPC socket cleanup or filesystem path management
- no TCP RPC/events listener unless an explicit advanced option is added later

The host runtime config should use the same internal RPC/events addresses the daemon binds.

This keeps the current FlatBuffer message path:

```text
RpcClient -> FlatBuffer request -> inproc REQ/ROUTER/DEALER/REP -> MessageHandler
MessageHandler -> FlatBuffer reply/event -> inproc PUB/SUB -> host/session code
```

Stage 2 can then add a non-ZeroMQ in-process transport.

### Stage 1 Startup Order

The combined binary should avoid races between daemon bind and host connect:

1. Install process error handling, logging, and signal handlers.
2. Load the combined config.
3. Create one `zmq::Context` and set IO threads once.
4. Create one shared `Arc<AtomicBool>` kill switch.
5. Prepare daemon keys, paths, and existing `Config`.
6. Start daemon runtime on a blocking thread with `inproc://` endpoints.
7. Wait for daemon RPC/events bind readiness.
8. Start enabled telnet and web hosts on the Tokio runtime using the same context and kill switch.
9. Wait until any required host listeners bind successfully.
10. Block until signal, daemon exit, or host task exit, then flip the shared kill switch and join
    spawned work.

The readiness step can be crude in the first pass if needed, but it should be explicit. Prefer a
small readiness channel from daemon startup over sleep-based timing.

### Stage 1 Shutdown

The combined binary should be the only process signal owner. On SIGTERM/SIGINT:

- set the shared kill switch
- let daemon RPC/workers/checkpoint loops observe shutdown through existing mechanisms
- let telnet/web listener tasks observe shutdown through their existing kill switch behavior
- submit daemon scheduler shutdown through the daemon runtime path
- join or await spawned tasks where possible

SIGUSR1 emergency checkpoint should remain daemon-owned behavior, but the signal flag should be
registered by the combined binary and passed into daemon runtime options, matching Phase 0.5.

### Stage 1 Non-Goals

- Do not introduce typed daemon request/reply APIs yet.
- Do not remove FlatBuffers from host/daemon traffic yet.
- Do not refactor `RpcClient` or `tmq::Subscribe` beyond what is required for shared context use.
- Do not change the existing split binaries' CLI/config behavior.
- Do not make single-process mode the only Docker/systemd deployment path. Keep the split examples
  available for clustered deployments.

## Stage 2 Non-ZeroMQ Transport

Add `InProcessTransport` implementing daemon `Transport`.

It should:

- publish narrative and task events into the in-process event bus
- broadcast host listen/unlisten/ping events into the in-process host event channel
- update connection attributes the same way `RpcTransport::publish_narrative_events()` does
- make `start_request_loop()` a no-op or a kill-switch wait loop, because request/reply dispatch is
  direct through `LocalRuntimeClient`

### Library Packaging Extraction

Before adding a combined binary, make the existing process crates usable as runtime libraries while
keeping their current binaries intact. The important boundary is process packaging versus runtime
assembly.

Process packaging stays in binaries:

- CLI `Args` structs, clap derives, and CLI-only defaults
- YAML config file loading and CLI override policy
- logging/tracing setup
- `color_eyre::install()`
- terminal presentation such as banners
- Tokio runtime creation via `#[tokio::main]`
- process signal registration
- calls to `std::process::exit`

Runtime assembly moves into libraries:

- daemon database/runtime/scheduler/RPC/worker construction from already resolved configuration
- telnet listener construction from already resolved telnet host configuration
- web listener/router construction from already resolved web host configuration
- host session startup from already resolved RPC client configuration
- injectable ZeroMQ context and kill switch handles
- returned errors instead of process exits

The library APIs should reuse existing configuration structs where they already represent runtime
configuration. Do not create a parallel config tree just to make the lib split work. Add small
resolved settings structs only for values that currently live only in CLI args, such as paths,
endpoints, keys, injected contexts, and kill switches.

- `moor-daemon`
  - `lib.rs`: use existing `moor_kernel::config::Config` plus resolved daemon paths/endpoints/key
    settings, key setup helpers, database/runtime assembly, daemon runtime handle
  - `main.rs`: parse CLI, load config, initialize logging, print banner, install standalone signal
    handling, and start the existing split daemon through the library API
- `moor-telnet-host`
  - `lib.rs`: telnet listener settings, existing RPC client settings where possible, listener
    startup, session types
  - `main.rs`: parse CLI, load config, initialize logging/Tokio, install standalone signal handling,
    and start the existing ZeroMQ-backed telnet host through the library API
- `moor-web-host`
  - `lib.rs`: web listener settings, existing web config structs such as OAuth2/CORS/rate
    limit/WebRTC, existing RPC client settings where possible, route/listener startup, session types
  - `main.rs`: parse CLI, load config, initialize logging/Tokio, install standalone signal handling,
    and start the existing ZeroMQ-backed web host through the library API

This phase should preserve current package names, binary names, CLI behavior, config loading, Debian
assets, and service behavior. It should not introduce `inproc://` routing yet.

### Runtime Assembly

After the three process crates have library entry points, the Stage 1 single-process binary should
compose those libraries rather than duplicating startup logic.

The combined binary should:

- parse one config surface
- reuse existing daemon `Config`
- convert listener config into `TelnetHostConfig` and `WebHostConfig`
- create one ZeroMQ context
- create one kill switch
- pass the same context and kill switch to daemon, telnet, and web runtime APIs
- use internal `inproc://` RPC/events addresses
- keep standalone split binaries unchanged

The current best location is `crates/daemon/src/bin/moor.rs`. If optional host dependencies make
`moor-daemon` build metadata too noisy, the same assembly can move to a small `crates/moor` package
later.

## Configuration Shape

The single-process binary should have one config namespace:

```yaml
database:
  # existing daemon database config

features:
  # existing daemon features

runtime:
  # existing daemon runtime options

import_export:
  # existing daemon import/export options

services:
  telnet:
    enabled: true
    address: "0.0.0.0"
    port: 8888
    tls_port:
    tls_cert:
    tls_key:
    health_check_port: 9888

  web:
    enabled: true
    listen_address: "0.0.0.0:8080"
    enable_webhooks: true
    oauth2:
      enabled: false
    cors:
      # existing web CORS config
    rate_limit:
      # existing rate limit config
    webrtc:
      enabled: false
```

The existing split configs should remain supported for the existing binaries.

## Implementation Plan

### Phase 0.5: Library Packaging Extraction

Goal: create reusable runtime libraries without moving process packaging into those libraries.

#### Phase 0.5.1: Define Runtime Config Types

- Reuse existing runtime config structs first:
  - `moor_kernel::config::Config`
  - `RuntimeConfig`
  - `ImportExportConfig`
  - `FeaturesConfig`
  - `DatabaseConfig`
  - existing web config structs for OAuth2, CORS, rate limiting, and WebRTC
- Do not create another feature/config layer for daemon runtime behavior.
- Add narrow resolved settings structs only where needed:
  - daemon data/db/tasks/events path settings
  - daemon RPC/events/workers/enrollment endpoint settings
  - daemon key/enrollment-token path settings
  - telnet listen/TLS/health-check settings
  - web listen/trusted-proxy/webhook settings
  - shared host connection settings if `RpcClientArgs` remains too clap-shaped for a library API
  - injected ZeroMQ context and kill switch handles
- Keep clap `Args` structs private to the existing binaries or binary-owned `cli` modules.
- Provide explicit conversion from parsed/resolved binary args into existing config structs plus the
  narrow resolved settings structs.
- Do not derive `Parser` on library config types.
- Do not make library config types responsible for reading YAML files.

#### Phase 0.5.2: Extract Host Runtime Libraries

- Move telnet listener/session startup into library functions that accept existing host connection
  settings plus resolved telnet listener/TLS/health-check settings.
- Move web listener/router/session startup into library functions that accept existing host
  connection settings, existing web config structs, and resolved web listener settings.
- Keep `#[tokio::main]` only in `main.rs`.
- Keep HUP/INT signal handling in `main.rs`; pass a kill switch into the library.
- Replace `std::process::exit` in extracted host runtime paths with returned errors.
- Look for common host setup between telnet and web:
  - host id creation
  - daemon enrollment/CURVE setup
  - `start_host_session`
  - `process_hosts_events`
  - last-daemon-ping tracking
  - listener task shutdown coordination
- Extract common host setup only when it reduces duplication without obscuring host-specific
  listener behavior.

#### Phase 0.5.3: Extract Daemon Runtime Library

- Move daemon runtime assembly into library functions that accept existing `Config`, resolved daemon
  path/endpoint/key settings, and runtime options.
- Keep banner printing, clap parsing, YAML loading, config override policy, logging setup, and
  `color_eyre::install()` in `main.rs`.
- Keep standalone process signal registration in `main.rs`; pass kill switches or shutdown handles
  into library runtime code.
- Keep database open/import/checkpoint, scheduler construction, RPC transport, workers, enrollment,
  and event log assembly in the daemon library because those are daemon runtime responsibilities.
- Avoid exposing raw daemon CLI args as the library API.

#### Phase 0.5.4: Preserve Existing Binaries

- Keep current binary names and package metadata unchanged.
- Keep existing `moor-daemon`, `moor-telnet-host`, and `moor-web-host` CLI behavior unchanged.
- Each `main.rs` should be a process wrapper:
  - install errors/logging
  - parse CLI and config files
  - construct runtime config/options
  - create Tokio runtime where appropriate
  - install standalone signal handling
  - call the library runtime

#### Phase 0.5.5: Verification

- `cargo check -p moor-daemon -p moor-telnet-host -p moor-web-host`
- `cargo test -p moor-daemon -p moor-telnet-host -p moor-web-host --no-run`
- Confirm library modules do not expose clap `Args` as their primary API.
- Confirm library modules do not initialize logging, install `color_eyre`, print banners, create
  Tokio runtimes, or call `std::process::exit`.

This phase should be behavior-preserving and should not introduce the combined binary yet.

### Phase 1: Stage 1 `inproc://` Runtime

Goal: add a single `moor` binary using one ZeroMQ context and internal `inproc://` endpoints while
preserving current daemon/host RPC semantics.

This phase should feel like a packaging and orchestration change, not a protocol rewrite. The hosts
still use `RpcClient`, `tmq::Subscribe`, host registration, pings, dynamic listener updates, and
FlatBuffer request/reply/event messages. The daemon still owns database, scheduler, workers, event
publishing, host tracking, task monitoring, and RPC handling.

#### Phase 1.1: Ownership Boundaries

The `moor` binary owns process-level work for the combined process:

- CLI parsing and command-line defaults
- YAML config file loading
- logging/tracing setup
- `color_eyre::install()`
- banner/output
- Tokio runtime ownership
- signal registration
- shared process kill switch
- shared ZeroMQ context creation
- top-level task/thread joining and exit status

The daemon, telnet, and web libraries continue to own runtime assembly:

- `moor-daemon` opens databases, imports/export-checkpoints data, starts scheduler/RPC/workers, and
  runs the daemon loop from already resolved runtime config.
- `moor-telnet-host` starts telnet/TLS listeners, registers with the daemon, and handles telnet
  sessions from already resolved runtime config.
- `moor-web-host` starts HTTP/WebSocket/WebRTC listeners, registers with the daemon, and handles web
  sessions from already resolved runtime config.

Do not put combined-process CLI args, config-file parsing, logging initialization, banner printing,
Tokio runtime creation, or signal handling into those libraries.

#### Phase 1.2: Config Shape

The single-process binary should reuse the existing daemon config at the top level:

- `database`
- `features`
- `runtime`
- `import_export`

Add one single-process namespace for host listener configuration:

- `services.telnet.enabled`
- `services.telnet.address`
- `services.telnet.port`
- `services.telnet.tls_port`
- `services.telnet.tls_cert`
- `services.telnet.tls_key`
- `services.telnet.health_check_port`
- `services.web.enabled`
- `services.web.listen_address`
- `services.web.enable_webhooks`
- `services.web.oauth2`
- `services.web.cors`
- `services.web.rate_limit`
- `services.web.trusted_proxy_cidrs`
- `services.web.webrtc`

Internal daemon/host RPC settings should not be part of the normal config surface. Single-process
mode should derive them from fixed internal constants. A debug-only override can be added later if
it proves useful.

The combined config loader can be implemented as a small wrapper around the existing daemon `Config`
plus `ServicesConfig`. Avoid cloning the split binaries' clap `Args` structs into a library API.

#### Phase 1.3: Binary Location and Dependency Shape

First cut:

```text
crates/daemon/
  src/bin/moor-daemon.rs # existing moor-daemon split-process binary
  src/bin/moor.rs      # new single-process binary
```

This keeps the first implementation close to daemon setup, where most of the shared process
lifecycle work already exists. The daemon package will need optional or direct dependencies on the
host runtime crates for this binary:

- `moor-telnet-host`
- `moor-web-host`
- Tokio runtime support for the combined binary
- `tmq` if the binary needs to construct host runtime contexts directly

If this makes daemon packaging too noisy, move the same assembly code into a small `crates/moor`
package later. That should be a packaging move, not a redesign.

#### Phase 1.4: Internal Endpoint Wiring

Use fixed internal endpoints for daemon/host traffic:

```text
inproc://moor-services-rpc
inproc://moor-services-events
```

Wire them as follows:

- daemon `DaemonEndpoints.rpc_listen` -> `inproc://moor-services-rpc`
- daemon `DaemonEndpoints.events_listen` -> `inproc://moor-services-events`
- telnet/web `RpcClientConfig.rpc_address` -> `inproc://moor-services-rpc`
- telnet/web `RpcClientConfig.events_address` -> `inproc://moor-services-events`

Users should not need to know these internal endpoint strings.

Enrollment/CURVE/ZAP should be bypassed for internal traffic. Prefer one explicit runtime/auth mode
over repeated endpoint string checks:

```rust
pub enum HostAuthMode {
    EnrolledCurve,
    LocalInProcess,
}
```

Split mode keeps `EnrolledCurve`. Single-process mode uses `LocalInProcess`. If the current
implementation already skips CURVE for non-`tcp://` endpoints, Stage 1 can use that behavior
temporarily, but the plan should be to make local auth explicit.

#### Phase 1.5: Shared Runtime Handles

Create these once in the combined binary:

- `zmq::Context`
- ZeroMQ IO thread count
- `Arc<AtomicBool>` kill switch
- SIGUSR1 emergency-checkpoint flag

Pass cloned handles into the component runtimes:

- `moor_daemon::DaemonRuntime`
- `moor_telnet_host::HostRuntime`
- `moor_web_host::HostRuntime`

Set the IO thread count before any daemon or host sockets are created. Do not let each component
create its own default context in single-process mode.

#### Phase 1.6: Startup Flow

Startup should be deterministic:

1. Install process error handling and logging.
2. Parse CLI and load combined config.
3. Resolve data paths, database paths, key paths, and listener settings.
4. Create the shared ZeroMQ context and kill switch.
5. Prepare daemon signing keys, CURVE keys, and enrollment token files as needed by daemon runtime.
6. Start daemon runtime on a blocking thread.
7. Wait for daemon RPC/events readiness.
8. Start enabled telnet and web host tasks on Tokio.
9. Report listener bind failures as startup failures.
10. Enter the combined process wait loop.

Readiness should come from the daemon transport after the `inproc://` RPC/events sockets are bound.
Do not use sleeps as a synchronization mechanism. A small optional readiness sender in
`DaemonRuntime` or the daemon transport is enough for Stage 1.

Host startup should remain conditional:

- telnet-only mode works
- web-only mode works
- both-host mode works
- no-host mode is allowed only if it is useful for maintenance/import/checkpoint workflows;
  otherwise reject it with a clear config error

#### Phase 1.7: Shutdown Flow

The combined binary is the only signal owner in single-process mode.

On SIGTERM/SIGINT:

- set the shared kill switch
- let daemon RPC/workers/scheduler/checkpoint loops observe shutdown through existing code paths
- let telnet/web listener tasks observe shutdown through existing host kill-switch handling
- await host tasks where possible
- join the daemon blocking thread where possible
- return a non-zero exit only when shutdown exposed an error

SIGUSR1 emergency checkpoint should keep the daemon behavior. The combined binary should register
the signal and pass the flag into `DaemonRuntime`.

Avoid dropping the shared ZeroMQ context while daemon/host tasks are still running.

#### Phase 1.8: Worker Policy

- Keep external worker clustering in the split deployment path.
- Enable selected embedded workers in the single-process binary behind explicit config flags.
- Run embedded workers through typed local worker services.
- Keep embedded curl worker disabled by default.

Do not leave worker behavior implicit.

#### Phase 1.9: Packaging and Examples

Add the `moor` binary to package outputs deliberately:

- Cargo binary target
- Debian/package artifact if the current package scripts enumerate binaries
- install/service docs as a single-process alternative, not a replacement for split deploy yet

Add a minimal sample config showing:

- fresh local data dir
- telnet enabled
- web enabled
- no exposed daemon RPC/events configuration

Do not switch Docker or systemd defaults until smoke tests cover the combined binary.

#### Phase 1.10: Verification

Focused compile checks:

- `cargo check -p moor-daemon -p moor-telnet-host -p moor-web-host`
- `cargo test -p moor-daemon -p moor-telnet-host -p moor-web-host --no-run`

Stage 1 smoke coverage:

- start `moor` with a fresh data dir
- import a core or start from an existing test DB
- confirm daemon readiness gates host startup
- confirm telnet listener binds
- confirm web listener binds
- connect through telnet and run a basic command
- connect through web socket if a lightweight client path exists
- restart against the same DB
- SIGTERM/SIGINT shuts down without hanging
- SIGUSR1 triggers the daemon emergency checkpoint path

Regression checks:

- split `moor-daemon` still starts with its existing CLI/config behavior
- split `moor-telnet-host` still enrolls over TCP/CURVE
- split `moor-web-host` still enrolls over TCP/CURVE

#### Phase 1.11: Done Line

Phase 1 is done when:

- one `moor` binary can run daemon + telnet + web in one process
- all daemon/host RPC and pub/sub traffic stays on one shared ZeroMQ context using `inproc://`
- split binaries keep their current behavior
- single-process config does not expose internal RPC/events endpoints
- startup does not depend on sleeps
- shutdown is signal-driven and uses the shared kill switch
- there is at least one repeatable smoke path for fresh start, listener bind, basic command,
  restart, and shutdown

This phase gives a useful single binary without changing daemon API shape.

### Phase 2: Typed Client Abstraction

- Introduce typed request/reply enums.
- Introduce `RuntimeClient` and adapt `RpcClient` to implement it by encoding/decoding FlatBuffers.
- Parameterize telnet/web code over the client abstraction.
- Keep ZeroMQ subscriptions unchanged initially.

This phase removes direct FlatBuffer request/reply dependence from host/session logic.

### Phase 3: Typed Event Abstraction

- Introduce client and host event subscription traits.
- Wrap existing `tmq::Subscribe` usage behind ZeroMQ implementations.
- Parameterize telnet/web sessions and host lifecycle loops over event subscriptions.

This phase removes direct `tmq::Subscribe` dependence from host/session logic.

### Phase 4: Non-ZeroMQ In-Process Transport

- Add `InProcessEventBus`.
- Add `InProcessTransport`.
- Add `InProcessClient`.
- Wire in-process request/reply dispatch through the typed daemon API.
- Wire session/task/narrative/host broadcasts through `InProcessEventBus`.

At the end of this phase, tests should be able to run daemon + hosts in one process without ZeroMQ.

At this point, the `moor` binary can switch from Stage 1 ZeroMQ `inproc://` plumbing to the typed
local transport.

### Phase 1.7: Packaging

- Add a separate Debian package for `moor`.
- Keep `moor-daemon` focused on the split daemon service.
- Keep LambdaCore assets duplicated in the mutually-exclusive `moor` and `moor-daemon` packages for
  now. A shared data package can come later if the packages need to become co-installable.

### Phase 5: Docs and Deployment Polish

- Keep Docker image support for single-process deployment.
- Add book docs for:
  - single-process deployment
  - split/clustered deployment
  - when to choose each
- Keep current daemon/web/telnet-host docs for advanced deployments.

## Testing Plan

Minimum Stage 1 coverage before shipping:

- `inproc://` request/reply smoke test:
  - establish connection
  - login
  - run command
  - eval/program verb
- `inproc://` event delivery:
  - narrative event
  - task success/error/suspended event
  - request input event
  - disconnect event
  - client broadcast
- `inproc://` host broadcast:
  - dynamic listen
  - dynamic unlisten
  - ping/pong or equivalent liveness update
- End-to-end single-process binary smoke:
  - import objdef core into fresh DB
  - connect via telnet
  - connect via web socket
  - restart with existing DB
- Startup/shutdown checks:
  - daemon readiness gates host startup
  - SIGTERM/SIGINT shuts down daemon and enabled hosts
  - SIGUSR1 triggers daemon emergency checkpoint path
- Config checks:
  - internal RPC/events endpoints do not need user config
  - telnet-only, web-only, and both-host modes work
- Regression check that split ZeroMQ deployment still works.

Stage 2 should add non-ZeroMQ local transport parity tests once `InProcessTransport` exists.

## Risks

### Event Delivery Semantics

The existing pub/sub path has implicit behavior from ZeroMQ, including subscription timing and
broadcast fanout. The in-process event bus should define these semantics explicitly.

Recommended behavior:

- per-client channels are created before attach/connection establishment returns
- bounded channels should drop or disconnect deterministically under backpressure
- broadcast should not block daemon task completion indefinitely

### Host Lifecycle

Current hosts register with the daemon and then respond to daemon pings. In single-process mode,
this can be kept as in-process host calls, but it may be simpler to register listeners directly at
startup and only retain dynamic listen/unlisten events.

Do not remove host registration semantics from split mode.

### Workers

Single-process deployment should not require external worker clustering. The first worker supported
inside `moor` is curl, behind `services.curl_worker.enabled` and `--enable-curl-worker`. When
enabled, the daemon publishes local worker services and the embedded curl worker attaches through
that typed in-process API. The standalone curl worker still uses the ZeroMQ worker transport. The
flag defaults off so deployments that do not need outbound HTTP keep the smaller runtime surface.
Development and example commands opt in so the bundled stack exercises the worker path.

### API Churn

The Stage 1 `inproc://` binary should have limited API churn because it preserves `RpcClient`,
`tmq::Subscribe`, FlatBuffer request/reply encoding, and daemon `MessageHandler`.

Stage 2 trait extraction will touch more files. Keep the first trait minimal and keep conversion
code at the ZeroMQ boundary so host/session logic does not learn schema details again.

### Tokio vs Threaded Daemon

The daemon is mostly threaded/blocking while hosts are Tokio-based. The combined binary needs a
clear ownership model:

- run daemon runtime in blocking threads
- run web/telnet listeners on Tokio
- share a kill switch
- ensure shutdown drains or aborts listener tasks before dropping daemon resources

## Open Questions

- Which additional worker types should be embedded, if any?
- Should the single-process binary expose enrollment/CURVE at all, or only local listeners?
- Should OAuth2 config be reused exactly from `moor-web-host`, or simplified for the first release?
- Should `moor` replace Docker default deployment, or live beside current split compose files?
- Should dynamic listen/unlisten in single-process mode support both web and telnet, including TLS
  listener options?
- Should the in-process event bus use `tokio::sync::broadcast`, `flume`, or custom per-client
  bounded queues?

## Recommended First Cut

Build the first cut around one shared ZeroMQ context and `inproc://` endpoints:

1. Extract libraries without changing behavior.
2. Add `moor` as a single binary that starts daemon + telnet + web.
3. Pass one shared ZeroMQ context into all three components.
4. Use `inproc://` RPC/events endpoints and preserve FlatBuffer message handling.
5. Keep embedded curl-worker support disabled by default in the single-process binary.

That gives a useful single-process deployment while keeping the current clustered architecture
intact and leaves typed API extraction as a follow-up cleanup.
