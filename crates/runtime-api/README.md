# moor-runtime-api

TLDR: Transport-neutral typed API for host/runtime communication, including request, response,
event, worker, and codec-facing types.

Downstream uses:

- Used by `moor-daemon` for local runtime and worker services, and by host/worker crates that
  communicate with a runtime.
- Used by `moor-zmq-client` as the typed contract for the ZeroMQ transport implementation.
- Keep concrete transport details out of this crate; ZeroMQ-specific code belongs in
  `moor-zmq-client`.
