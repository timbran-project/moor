# @moor/web-sdk

Shared TypeScript SDK for mooR web-facing clients.

This package is intended to hold protocol-level logic shared by Meadow and other clients, while
UI/application-specific code remains in each client.

It provides TypesScript bindings to call the moor-web-host API.

## Scope

- Auth header helpers for mooR web-host
- HTTP endpoint wrappers
- WebSocket attach/reattach protocol helpers
- FlatBuffer decoding/encoding helpers

## 2.0 Development

This package is a private npm workspace during the 2.0 development cycle. Install dependencies and
run its build from the mooR repository root so npm resolves `@moor/schema` from the same checkout.

External package distribution will be reconsidered when the 2.0 API is ready for independent
clients. The monorepo does not publish development snapshots to an npm registry.

## License

`@moor/web-sdk` is licensed under `LGPL-3.0-or-later`. See `clients/web-sdk/LICENSE`. You can build
on top of it, but must also comply with the LGPL-3.0-or-later license if you modify the source code
to the library itself.

(The remainder of mooR is GPL 3.0)
