# Client Applications

This directory contains the web clients and shared TypeScript libraries used by mooR.

## Meadow Web Client

[Meadow](meadow/) is the React web and Tauri client. It is part of the root npm workspace so clean
checkouts and Docker builds do not need to fetch a second repository.

The shared schema, web SDK, and MCP client are under `crates/schema/schema/`, `clients/web-sdk/`,
and `clients/moor-web-mcp/` respectively.

### Production Deployments

Published deployments use the Meadow assets included in `ghcr.io/timbran-project/moor`.
