# Single-Process Deployment

## Problem

mooR supports split deployments made of cooperating processes:

- `moor-daemon` owns the database, scheduler, VM, connection registry, task monitor, event log, host
  enrollment, worker routing, and RPC server.
- `moor-telnet-host` listens for line-oriented TCP/Telnet clients and talks to the daemon over
  ZeroMQ request/reply plus pub/sub.
- `moor-web-host` listens for HTTP/WebSocket/WebRTC clients and talks to the daemon over the same
  ZeroMQ RPC and event channels.

That shape remains useful for clustered or split-host deployments, but it is heavier than necessary
for local development, demos, personal servers, and package installs where all components run on one
machine.

## Goal

The `moor` binary runs the daemon runtime, telnet host, web host, and selected embedded workers in
one process while preserving the same daemon/session/auth semantics used by split deployments.

Single-process mode should not bypass connection/session behavior by calling the scheduler directly
from hosts. Hosts still talk to a runtime boundary; the difference is whether that boundary is a
typed in-process adapter or a ZeroMQ/FlatBuffer adapter.

## Current Status

The single-process binary exists at `crates/daemon/src/bin/moor.rs`. The split-process daemon entry
point remains `crates/daemon/src/bin/moor-daemon.rs`.

Single-process mode has moved past the earlier `inproc://` ZeroMQ milestone. It now uses typed
in-process services for daemon/host request-reply and event delivery:

- `moor_runtime_api::api::RuntimeClient` is the host-side typed request client trait.
- `moor_runtime_api::api::HostServices` bundles runtime clients and event subscriptions for host
  code.
- `moor_runtime_api::task_client::TaskClient` provides higher-level verb invocation over
  `HostServices`; it is not tied to ZeroMQ.
- `crates/daemon/src/runtime/api.rs` defines the daemon-side `RuntimeApi`.
- `LocalRuntimeClient`, `LocalEventBus`, and `LocalRuntimeServices` provide the in-process host
  adapter.
- `RpcClient` remains the ZeroMQ-backed split-process adapter and implements `RuntimeClient`.
- `ZmqHostServices` remains in `moor-zmq-client` as the split-process host service factory.

FlatBuffers remain the split-process wire format. Typed request/reply/event definitions live in
`moor-runtime-api`; FlatBuffer conversion lives at adapter boundaries:

- daemon `MessageHandler` methods decode FlatBuffer request refs, call `RuntimeApi`, and encode
  FlatBuffer replies for ZeroMQ callers
- `RpcClient` encodes typed host/client requests to FlatBuffers and decodes replies
- ZeroMQ event subscriptions decode FlatBuffer events into typed event enums
- local event delivery carries typed events directly
- web browser payload edges still encode binary event payloads where the browser protocol expects
  them

The default development workflow is `npm run full:dev`, which runs Meadow plus `npm run moor:dev`.
That script uses checked-in `moor-dev.yaml` unless `MOOR_CONFIG` is set.

## Runtime Shape

```text
               split deployment                         single process

 telnet/web/curl process                                moor process
      |                                                       |
      | ZmqHostServices / Zmq worker services                | LocalRuntimeServices
      v                                                       | LocalWorkerServices
 typed RuntimeClient/EventSubscription                       v
 typed WorkerServices                            typed RuntimeClient/EventSubscription
      |                                           typed WorkerServices
      v                                                       |
 FlatBuffer ZeroMQ adapter                                    v
      |                                             daemon RuntimeApi
      v                                             daemon worker handler
 moor-daemon process                                          |
      |                                                       v
 daemon runtime + scheduler                         daemon runtime + scheduler
```

The same high-level host/session code works in both modes:

- split hosts construct `ZmqHostServices`
- single-process hosts receive `LocalRuntimeServices`
- split workers use the ZeroMQ worker transport
- embedded workers receive `LocalWorkerServices`
- both modes share the typed request/reply/event traits
- schema details stay at the ZeroMQ adapter and explicit browser-payload compatibility boundary

## Current Code Boundaries

### Process Assembly

`crates/daemon/src/bin/moor.rs` owns single-process process-level concerns:

- CLI parsing and combined config loading
- logging/error setup
- banner output
- signal registration
- shared kill switch
- daemon startup on a blocking task
- telnet/web/curl task startup
- shutdown coordination

`crates/daemon/src/bin/moor-daemon.rs` remains the split daemon process wrapper.

### Daemon Runtime

`crates/daemon/src/lib.rs` owns daemon runtime assembly:

- data-directory locking
- database open/import/checkpoint setup
- scheduler construction
- event log setup
- connection registry setup
- host enrollment/CURVE/ZAP for split TCP deployments
- RPC transport or local event bus selection
- worker routing setup
- publication of local runtime/worker services when requested by `moor`

`RpcServer` still coordinates the message handler, session mailbox, task monitor, and transport.
This is a server/runtime concern today, even though it lives under the `rpc` module.

### Typed Runtime API

`moor-runtime-api` is the host/runtime contract crate. It contains:

- typed host/client request and reply enums
- typed event enums and subscription traits
- `RuntimeClient`
- `HostServices`
- `WorkerServices`
- FlatBuffer codec helpers used by adapter layers

`crates/daemon/src/runtime/api.rs` contains the daemon-side `RuntimeApi` trait. `RpcMessageHandler`
implements it.

### Split-Process Adapter

`moor-zmq-client` implements the split-process client side:

- `RpcClient: RuntimeClient`
- `ZmqHostServices: HostServices`
- typed event subscriptions over ZeroMQ subscriptions
- worker transport for standalone workers

The daemon-side ZeroMQ transport lives under `crates/daemon/src/rpc/transport.rs`.

### Local Runtime Adapter

`crates/daemon/src/runtime` contains the in-process adapters:

- `LocalRuntimeClient`
- `LocalRuntimeServices`
- `LocalEventBus`
- `LocalWorkerServices`

The local event bus implements daemon `Transport` for event publication. Request/reply calls do not
serialize through FlatBuffers in single-process mode; `LocalRuntimeClient` calls `RuntimeApi`
directly with a `SchedulerClient`.

### Workers

Split deployments keep the external worker transport. Single-process mode can enable selected
embedded workers through explicit flags/config.

The embedded curl worker path is:

- `moor` enables daemon workers with `services.curl_worker.enabled` or `--enable-curl-worker`
- daemon constructs a local `WorkersMessageHandlerImpl`
- daemon publishes `LocalWorkerServices`
- `moor_curl_worker::run_with_services` attaches a local `curl` worker through `WorkerServices`
- requests and responses use typed local events instead of ZeroMQ

The standalone curl worker still uses the ZeroMQ worker transport.

## Configuration Shape

The single-process binary has one config surface:

```yaml
database:
  # daemon database config

features:
  # daemon feature flags

runtime:
  # daemon runtime options

import_export:
  # daemon import/export options

services:
  telnet:
    enabled: true
    address: "0.0.0.0"
    port: 8888
    health_check_port: 9888
    tls_port:
    tls_cert:
    tls_key:

  web:
    enabled: true
    listen_address: "0.0.0.0:8080"
    enable_webhooks: true
    oauth2:
      enabled: false
    cors:
      # web CORS config
    rate_limit:
      # rate limit config
    trusted_proxy_cidrs: []
    webrtc:
      enabled: false

  curl_worker:
    enabled: false
    health_check_port:
```

Split-process configs remain supported by the split binaries.

Internal daemon/host RPC endpoints are not part of the normal single-process config surface.
`moor.rs` still uses fixed `inproc://` endpoint constants for daemon runtime fields that expect
endpoint strings, but host request/reply/event traffic uses local typed services rather than ZeroMQ
sockets.

## Non-Goals

- Do not remove the existing clustered deployment model.
- Do not remove ZeroMQ RPC, host enrollment, CURVE, workers, or split host binaries.
- Do not rewrite telnet or web sessions to call `SchedulerClient` directly.
- Do not remove the FlatBuffer protocol from split deployments.
- Do not require external worker clustering in single-process deployments.
- Do not expose internal RPC/events addresses as normal single-process config.

## Current Verification

Focused daemon parity coverage exists in `crates/daemon/src/testing/backend_parity_test.rs`.

The current parity tests run these scenarios through both the FlatBuffer/mock transport path and the
local runtime path:

- host registration + ping/pong
- connection + welcome + login
- command execution + event delivery

Useful focused checks:

```text
cargo test -p moor-daemon backend_parity --lib -- --test-threads=1
cargo test -p moor-daemon rpc_integration --lib --no-run
cargo test -p moor-daemon scheduler_integration --lib --no-run
```

## Remaining Work

### 1. Documentation And Naming Cleanup

Keep docs aligned with the implemented architecture. Avoid future-looking stage language that says
typed request/reply/event traits still need to be introduced.

Likely cleanup areas:

- explain `moor` versus `moor-daemon` clearly in the book and deploy docs
- ensure crate READMEs describe `moor-runtime-api`, `moor-zmq-client`, and `moor-daemon`
  consistently
- audit names that still imply local paths are under the FlatBuffer/RPC transport layer when they
  are really runtime/server concerns

### 2. Daemon Crate Boundary Cleanup

The daemon crate still contains both process assembly and server/runtime library concerns. A future
split into a smaller server/runtime library and daemon process package may be useful, but it should
be a packaging/module-boundary cleanup, not a protocol redesign.

Keep these constraints:

- `RuntimeApi` remains the semantic daemon boundary
- `moor-runtime-api` remains transport-neutral
- `moor-zmq-client` remains the split-process adapter
- host crates continue depending on `HostServices`, not daemon internals
- split binaries keep their existing CLI/config behavior

### 3. Worker Naming And Tests

The worker handler supports both ZeroMQ and local delivery, but its names and module location still
read as a transport-specific server. If this becomes confusing, split worker request routing from
worker transport handling.

Additional useful coverage:

- local embedded curl worker attach/ping/request/result
- worker timeout/error behavior through `LocalWorkerServices`
- split worker transport no-run or smoke coverage

### 4. End-To-End Single-Process Smoke Coverage

The parity tests prove daemon API behavior, but the combined binary still needs practical smoke
coverage:

- start `moor` with a fresh data dir and import a core
- confirm daemon readiness gates host startup
- confirm telnet listener binds
- confirm web listener binds
- connect through telnet and run a basic command
- connect through web socket if a lightweight client path exists
- restart against the same DB
- SIGTERM/SIGINT shuts down without hanging
- SIGUSR1 triggers the daemon emergency checkpoint path
- optional curl worker path handles a simple local request

### 5. Packaging

Package outputs should include the `moor` binary deliberately:

- Cargo binary target
- Debian/package artifact if scripts enumerate binaries
- single-process service docs as an alternative to split deployment, not a replacement

Keep split deployment examples available for clustered deployments.

## Risks

### Event Delivery Semantics

ZeroMQ pub/sub has implicit behavior around subscription timing and fanout. The local event bus
should keep its semantics explicit:

- per-client channels are created before attach/connection establishment returns
- backpressure behavior should be deterministic
- broadcast should not block daemon task completion indefinitely

### Host Lifecycle

Host registration, pings, dynamic listen, and dynamic unlisten still matter in single-process mode
because the same host/session code runs in both modes. Do not remove those semantics from the split
path, and do not special-case local hosts unless there is a clear boundary.

### Workers

Embedded workers are opt-in. The first embedded worker is curl, through
`services.curl_worker.enabled` and `--enable-curl-worker`. The standalone curl worker remains the
split-process ZeroMQ worker.

### API Drift

The typed host/runtime boundary is the stable direction. Keep conversion code at adapter boundaries.
Avoid reintroducing RPC address, ZeroMQ context, or FlatBuffer schema details into host/session
logic.
