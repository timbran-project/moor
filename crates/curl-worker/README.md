# moor-curl-worker

TLDR: Worker implementation for outbound HTTP requests initiated by MOO code.

Downstream uses:

- Used by `moor-server` as the built-in curl worker in single-process deployments.
- Uses transport-neutral worker services when embedded in `moor`.
- Uses `moor-zmq-client` only for the standalone split-process worker path.
- Keep HTTP worker behavior here; typed worker contracts belong in `moor-runtime-api`.
