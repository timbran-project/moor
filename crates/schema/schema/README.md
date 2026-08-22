# mooR Schema Definitions

This directory contains the FlatBuffer schema definition files used for mooR RPC, persistence, and
generated client bindings. During the 2.0 development cycle, `@moor/schema` is a private npm
workspace built directly from the monorepo.

## License

The schema definition files in this directory (`*.fbs`) are licensed under the GNU Lesser General
Public License v3.0 or later. See [LICENSE](./LICENSE).

Generated bindings and other artifacts derived from these schema definitions are intended to be
distributed under the same LGPL terms unless stated otherwise in the distributed artifact.

This licensing applies to the schema definitions and derived published schema artifacts in this
directory. It does not by itself change the license of the surrounding mooR server implementation in
other parts of the repository.

## Code generation

The Rust and TypeScript bindings use different generators.

### Rust

Install the Planus version that the workspace uses. Then run this command from this directory:

```shell
planus rust -o ../src/schemas_generated.rs all_schemas.fbs
```

Commit the updated `../src/schemas_generated.rs` file with the schema change.

### TypeScript

Install `flatc`. Then run this command from the repository root:

```shell
npm run schema:build
```

If `flatc` is not on `PATH`, set `MOOR_FLATC` to the compiler's absolute path:

```shell
MOOR_FLATC=/path/to/flatc npm run schema:build
```

The build compiles the generated bindings against the installed TypeScript FlatBuffers runtime. The
`generated/` and `dist/` directories are build output and are not committed.

The master schema produces `all_schemas_generated.ts`. This file has duplicate export names from
different namespaces. The TypeScript build excludes this file. Import generated types from their
namespace modules, such as `@moor/schema/generated/moor-rpc/client-event`.
