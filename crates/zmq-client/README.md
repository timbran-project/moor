# moor-zmq-client

TLDR: ZeroMQ-backed implementation of the typed runtime client, host services, event subscription,
and worker transport.

Downstream uses:

- Used by standalone hosts, workers, MCP tooling, and load tools that communicate with a separate
  runtime process.
- Implements the transport for contracts defined in `moor-runtime-api`.
- Single-process daemon paths can use local runtime services instead of this transport.
