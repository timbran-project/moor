Directory layout for `crates/`

Binaries:

- `daemon` - the split-process daemon. Brings up the database, VM, task scheduler, worker routing,
  and ZeroMQ/FlatBuffer RPC interface. It does not expose player-facing network protocols directly;
  those are provided by host processes.
- `server` - the single-process `moor` binary. Runs the daemon runtime plus telnet/web hosts and
  selected embedded workers in one process, using typed in-process runtime services instead of
  ZeroMQ between local components.
- `telnet-host` - a binary which connects to `daemon` and provides a classic LambdaMOO-style telnet
  interface. The idea being that the `daemon` can go up and down, or be located on a different
  physical machine from the\
  network `host`s
- `web-host` - like the above, but hosts an HTTP server which provides a websocket interface to the
  system. as well as various web APIs.
- `testing/load-tools` - tools for inducing load for transactional consistency test (via jepsen's
  `elle` tool), or for performance testing.
- `testing/moot` - a comprensive test suite for verifying the correctness of the MOO implementation,
  including a battery of tests ported from ToastStunt.

Libraries:

- `var` - implements the basic moor/MOO value types and exports common constants and error structs
  associated with them
- `common` - common model objects and utilities such as WorldState, command matching, and utilities
- `db` - implementation of the `WorldState` object database overtop of `rdb`
- `compiler` - the MOO language grammar, parser, AST, and codegen, as well as the decompiler &
  unparser
- `vm` - the VM execution core: stack frames, activations, environment storage, and unwind logic.
  Pure types with no host/scheduler dependencies.
- `kernel` - the kernel of the MOO driver: task scheduler, builtin functions, and host services that
  wire the VM into the transactional database
- `runtime-api` - typed host/runtime and worker API, shared message types, and wire codec helpers
- `zmq-client` - ZeroMQ-backed runtime client, host service, and worker transport implementation
