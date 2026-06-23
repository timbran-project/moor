# moor-web-host

TLDR: HTTP, WebSocket, and browser-facing host for mooR sessions and web APIs.

Downstream uses:

- Used by `moor-server` as an embedded host in single-process deployments.
- Can talk to a runtime through `moor-runtime-api` and `moor-zmq-client`.
- Keep web protocol, request routing, and browser session handling here; shared runtime contracts
  belong in `moor-runtime-api`.
