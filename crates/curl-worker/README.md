# moor-curl-worker

TLDR: Worker implementation for outbound HTTP requests initiated by MOO code.

Downstream uses:

- Used by `moor-daemon` as the built-in curl worker in single-process deployments.
- Can communicate with the runtime through the transport-neutral runtime API and the ZeroMQ client
  implementation.
- Keep HTTP worker behavior here; the typed runtime contracts belong in `moor-runtime-api`.
