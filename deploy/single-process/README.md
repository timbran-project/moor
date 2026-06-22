# Single-Process Deployments

These examples run the combined `moor` binary. The daemon, telnet host, and web host share one
process and communicate over in-process ZeroMQ endpoints.

- `basic/`: one backend container exposing telnet and the embedded web API, with curl worker
  enabled.
- `web/`: one backend container plus nginx serving the Meadow frontend, with curl worker enabled.

The clustered examples that run separate daemon, host, and worker processes live under
`../clustered/`.
