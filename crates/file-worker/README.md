# moor-file-worker

A standalone mooR worker that performs filesystem operations on behalf of the server, confined to a
single sandbox directory. Like the split-process curl worker, it attaches to the daemon over ZMQ and
services requests dispatched from MOO code via `worker_request`. It is not embedded in the `moor`
single-process server and must be started separately.

## Sandbox model

The worker is started with a single sandbox root (`--sandbox-dir` / `MOOR_FILE_WORKER_SANDBOX`).
Every request path is interpreted relative to that root, and all I/O is confined to it:

- Absolute paths are rejected.
- `..` traversal that would climb above the root is rejected.
- Symlinks whose targets resolve outside the root are rejected.

The root is retained as an open directory capability, and every operation is performed relative to
that handle. Containment therefore remains in force if a directory or symlink is changed while an
operation is starting. Error messages only mention the caller-supplied relative path, never host
paths outside the sandbox.

## Command-line arguments

Worker-specific:

| Argument                     | Environment                | Default    | Description                                                                                                  |
| ---------------------------- | -------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------ |
| `--sandbox-dir <DIR>`        | `MOOR_FILE_WORKER_SANDBOX` | (required) | Root directory all file operations are confined to. Must exist and be a directory; canonicalized at startup. |
| `--debug`                    |                            | `false`    | Enable debug logging.                                                                                        |
| `--health-check-port <PORT>` |                            | `9999`     | TCP port for a health probe that responds `OK`/`UNHEALTHY`.                                                  |

Shared RPC client arguments (from `RpcClientArgs`, identical to the other hosts/workers):

| Argument                            | Default                                 | Description                                                                 |
| ----------------------------------- | --------------------------------------- | --------------------------------------------------------------------------- |
| `--rpc-address <ADDR>`              | `ipc:///tmp/moor_rpc.sock`              | Daemon RPC address (used to decide whether CURVE is required).              |
| `--events-address <ADDR>`           | `ipc:///tmp/moor_events.sock`           | Daemon events address (unused by this worker but accepted for consistency). |
| `--workers-request-address <ADDR>`  | `ipc:///tmp/moor_workers_request.sock`  | SUB socket where the daemon broadcasts work requests and pings.             |
| `--workers-response-address <ADDR>` | `ipc:///tmp/moor_workers_response.sock` | REQ socket used to attach and to return results/errors.                     |
| `--enrollment-address <ADDR>`       | `tcp://localhost:7900`                  | Enrollment endpoint for CURVE key exchange (TCP transports only).           |
| `--data-dir <DIR>`                  | `./.moor-host-data`                     | Directory for worker identity / CURVE keys.                                 |
| `--enrollment-token-file <FILE>`    | (optional)                              | Path to an enrollment token file.                                           |

Environment:

| Variable                   | Description                                         |
| -------------------------- | --------------------------------------------------- |
| `MOOR_FILE_WORKER_SANDBOX` | Alternative to `--sandbox-dir`.                     |
| `MOOR_ENROLLMENT_TOKEN`    | Enrollment token for CURVE authentication over TCP. |

When the daemon is reached over IPC, no CURVE enrollment is performed. Over TCP the worker enrolls
using service type `file-worker`.

## Operations

Invoke from MOO with `worker_request` (wizard-only). The first request element is the operation
symbol; the second is a sandbox-relative path. The call suspends the task until the worker replies.

```moo
worker_request('file, {'read, "notes.txt"});
```

An optional third argument to `worker_request` is an options map/alist; `timeout_seconds` bounds how
long the worker may spend on the operation.

### File operations

| Operation      | Arguments                               | Returns                                                                                       |
| -------------- | --------------------------------------- | --------------------------------------------------------------------------------------------- |
| `read`         | `{'read, path}`                         | File contents as a string.                                                                    |
| `read` (range) | `{'read, path, start_line[, end_line]}` | List of strings for the 1-based inclusive line range. `end_line` defaults to the end of file. |
| `write`        | `{'write, path, content}`               | Number of bytes written. Creates or overwrites; the parent directory must exist.              |
| `append`       | `{'append, path, content}`              | Number of bytes written. Creates the file if absent.                                          |
| `delete`       | `{'delete, path}`                       | `1` on success. Removes a file (not a directory).                                             |
| `stat`         | `{'stat, path}`                         | Metadata map (see below).                                                                     |
| `line_count`   | `{'line_count, path}`                   | Number of lines as an integer.                                                                |

`content` may be a string or a list of strings; a list is joined with newlines.

`stat` returns a map with keys:

- `type` — `"file"`, `"directory"`, or `"symlink"`.
- `size` — size in bytes.
- `mode` — octal permission string (Unix, e.g. `"644"`).
- `readonly` — `1` if the read-only bit is set, else `0`.
- `modified` / `created` / `accessed` — Unix timestamps (seconds), when available on the platform.

### Directory operations

| Operation | Arguments        | Returns                                           |
| --------- | ---------------- | ------------------------------------------------- |
| `mkdir`   | `{'mkdir, path}` | `1` on success. Creates intermediate directories. |
| `rmdir`   | `{'rmdir, path}` | `1` on success. Removes an empty directory only.  |
| `list`    | `{'list, path}`  | List of `{name, type, size}` maps, one per entry. |

`rmdir` does not permit removing the sandbox root itself.

### Examples

```moo
worker_request('file, {'write, "logs/today.txt", {"line one", "line two"}});
worker_request('file, {'append, "logs/today.txt", "line three"});
worker_request('file, {'read, "logs/today.txt", 2, 3});
worker_request('file, {'stat, "logs/today.txt"});
worker_request('file, {'list, "logs"});
worker_request('file, {'mkdir, "archive/2026"});
```

## Docker Compose

The [clustered web-basic deployment](../../deploy/clustered/web-basic) includes the worker as an
optional Compose profile:

```bash
cd deploy/clustered/web-basic
COMPOSE_PROFILES=file-worker ./start.sh
```

The profile maps `./moor-file-worker-sandbox/` into the container as `/sandbox`. The worker remains
disabled when the profile is not selected.
