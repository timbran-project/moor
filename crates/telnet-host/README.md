# moor-telnet-host

TLDR: Line-oriented TCP/Telnet host for interactive MOO sessions.

Downstream uses:

- Used by `moor-server` as an embedded host in single-process deployments.
- Can also talk to a runtime through `moor-runtime-api` and `moor-zmq-client`.
- Keep Telnet parsing, listener handling, and session I/O here; runtime semantics stay in
  `moor-kernel`.
