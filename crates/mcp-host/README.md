# moor-mcp-host

TLDR: Model Context Protocol host for exposing mooR runtime operations to MCP clients.

Downstream uses:

- Leaf host crate; no production runtime crate depends on it.
- Uses `moor-runtime-api` and `moor-zmq-client` to talk to a running mooR runtime.
- Keep MCP protocol translation here; shared runtime requests and events belong in
  `moor-runtime-api`.
