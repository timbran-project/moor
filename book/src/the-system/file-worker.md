# File Worker

MOO code normally stores its data in the MOO database. It does not have general access to files on
the computer running the server. This is a useful default: a programming mistake—or a verb written
by someone who should not have host access—cannot overwrite configuration, read private keys, or
fill an arbitrary filesystem.

Some worlds do need to exchange files with other software. They may generate reports for another
service, import data placed in a shared directory, or write files that are published by a separate
web server. `moor-file-worker` provides that bridge. It lets MOO code work with files inside one
directory chosen by the server operator. MOO code sends requests to it with `worker_request()`,
using the worker type `'file`.

## Why it is not enabled by default

The file worker is an explicit opt-in feature. It is not embedded in the single-process `moor`
server and a normal installation does not start it.

Most worlds do not need filesystem access. Enabling it creates a new connection between code in the
MOO and resources outside the database. File changes are durable, are not part of a MOO database
transaction, and may be consumed by other programs. The right directory, permissions, storage
limits, and backup policy are different for every installation, so mooR cannot choose safe defaults
on the operator's behalf.

Before enabling the worker, an operator should decide:

- Which files the world actually needs.
- Whether MOO code should have read-write or read-only access.
- Which operating-system account or container should run the worker.
- How much disk space the worker may consume.
- Whether the worker belongs on the daemon host or in a separate environment.

Start with a new, otherwise empty directory. Do not use `/`, the mooR database directory, the
server's configuration directory, a source checkout, or a directory containing credentials as the
sandbox.

## Why it is a separate process

The worker is separate from the daemon on purpose. The daemon never needs to mount or open the
worker's files. It sends a request such as “read `reports/today.txt`” and receives the result. The
worker alone performs the filesystem operation.

Slow filesystem work happens outside the daemon. The MOO task that made the request waits, but the
server can continue running other tasks. The worker can also be stopped, restarted, or upgraded
without stopping the daemon. While no file worker is available, file requests fail rather than
taking down the rest of the server.

This gives system administrators several ways to limit risk:

- Run the worker as a dedicated operating-system user with access only to its sandbox.
- Give its container only one narrow bind mount instead of the daemon's volumes.
- Mount the sandbox read-only when the world only needs `read`, `stat`, `line_count`, and `list`.
  Write operations will then be rejected by the operating system.
- Apply disk quotas, resource limits, AppArmor, SELinux, or other controls to the worker without
  changing the daemon.
- Place the worker in a network zone appropriate for the files it handles.

Isolation also provides deployment flexibility. The worker may run:

- As another process on the daemon host, communicating over local IPC sockets.
- In its own container on the same machine.
- On a different machine entirely, communicating with the daemon over TCP.

A remote worker can live next to the storage it serves rather than exposing that storage to the
daemon host. For example, a daemon in an application network could send file requests to a worker in
a restricted document-processing zone. Only the worker communication endpoints need to cross the
network boundary. TCP connections use mooR's CURVE enrollment and encryption, just like other
split-process hosts and workers.

Remember that paths refer to the worker's environment. If a remote worker is configured with
`--sandbox-dir /srv/moor-files`, that is a directory on the worker machine, not on the daemon
machine.

## Security model

The configured directory is called the _sandbox_. To the MOO, it looks like the top of the
filesystem. If the sandbox is `/srv/moor-files`, a request for `"reports/today.txt"` refers to
`/srv/moor-files/reports/today.txt`, but the MOO never needs to know the host path.

Internally, the worker keeps the sandbox open as a directory capability. This means each operation
starts from that already-open directory instead of checking a textual path and then asking the
operating system to open it later. Every request path is interpreted relative to that capability:

- Absolute paths are rejected.
- `..` components may normalize an interior path, but cannot climb above the sandbox root.
- Symlinks that resolve outside the sandbox are rejected.
- File lookup and access remain confined while directories or symlinks are changed concurrently.
- Errors returned to MOO code identify the request path without exposing the sandbox's host path.

The capability prevents a request from escaping the configured root, including when another process
changes a directory or symbolic link at the same time. Operating-system controls still matter. The
sandbox limits which paths the worker can name; filesystem ownership, permissions, mount options,
and container controls determine what it may do with those paths.

`worker_request()` is wizard-only. The file worker does not provide a second authorization layer
between MOO principals: any code permitted to submit a file-worker request can address the entire
configured sandbox.

## Sending requests

The general form is:

```moo
result = worker_request('file, {operation, path, @arguments});
```

`operation` may be a symbol or string. `path` must be a sandbox-relative string. The calling task
suspends until a file worker returns a result or an error.

The optional third argument to `worker_request()` is a map or association list of request options.
Use `timeout_seconds` to limit how long the task waits:

```moo
contents = worker_request(
    'file,
    {'read, "reports/current.txt"},
    ["timeout_seconds" -> 5.0]
);
```

Use `workers()` to check whether a file worker is attached:

```moo
for worker in (workers())
    if (worker[1] == 'file)
        player:tell("File worker is available.");
    endif
endfor
```

Both `worker_request()` and `workers()` require wizard permissions.

## File operations

### Reading

Read an entire UTF-8 text file:

```moo
contents = worker_request('file, {'read, "notes.txt"});
```

The result is a string. Invalid UTF-8 produces an error.

To read a 1-based inclusive range of lines, supply a starting line and an optional ending line:

```moo
lines = worker_request('file, {'read, "logs/server.log", 100, 125});
remaining_lines = worker_request('file, {'read, "logs/server.log", 100});
```

A ranged read returns a list of strings without newline terminators. The starting line must be at
least 1, and the ending line cannot precede it.

### Writing and appending

`write` creates or replaces a file:

```moo
bytes = worker_request('file, {'write, "status.txt", "ready"});
```

`append` creates a file if necessary and otherwise adds to its end:

```moo
bytes = worker_request('file, {'append, "events.log", "connected\n"});
```

Content may be a string or a list of strings. List items are joined with newline characters, with no
additional trailing newline:

```moo
bytes = worker_request(
    'file,
    {'write, "players.txt", {"Munchkin", "Frand", "Ezekiel"}}
);
```

Both operations return the number of bytes written. The parent directory must already exist.

### Deleting

`delete` removes a file and returns `1`:

```moo
worker_request('file, {'delete, "cache/old-result.txt"});
```

If the path names a symbolic link, the link is removed rather than its target. Use `rmdir` for
directories.

### Counting lines

`line_count` returns the number of lines in a UTF-8 text file:

```moo
count = worker_request('file, {'line_count, "events.log"});
```

### File metadata

`stat` returns a map describing a file, directory, or symbolic link:

```moo
metadata = worker_request('file, {'stat, "events.log"});
```

The map contains:

| Key                                         | Value                                                          |
| ------------------------------------------- | -------------------------------------------------------------- |
| `"type"`                                    | `"file"`, `"directory"`, or `"symlink"`                        |
| `"size"`                                    | Size in bytes                                                  |
| `"readonly"`                                | `1` when the filesystem read-only bit is set, otherwise `0`    |
| `"mode"`                                    | Unix permission mode as an octal string, when available        |
| `"modified"`, `"created"`, and `"accessed"` | Unix timestamps in seconds, when available from the filesystem |

`stat` describes a symbolic link itself rather than following it.

## Directory operations

`mkdir` creates a directory and any missing parents:

```moo
worker_request('file, {'mkdir, "archive/2026/july"});
```

`rmdir` removes an empty directory:

```moo
worker_request('file, {'rmdir, "archive/2025"});
```

Recursive directory deletion is not supported, and the sandbox root cannot be removed.

`list` returns a list of maps containing each entry's `"name"`, `"type"`, and `"size"`:

```moo
entries = worker_request('file, {'list, "archive"});
```

Directory listing order is filesystem-dependent and should not be treated as stable.

## A few operational details

Invalid arguments, rejected paths, missing files, permission failures, and other filesystem errors
are raised in the suspended MOO task with a descriptive message.

Filesystem changes happen outside the MOO database. If a verb writes a file and then its database
transaction fails, the file is not automatically restored. A timeout also does not undo an operation
that the operating system has already performed. Design verbs so running them again cannot silently
duplicate or corrupt external state.

Requests may run concurrently, and the worker does not add file locking or transaction semantics.
Use application-level coordination when multiple tasks can modify the same path.

The daemon sends a request to a worker type, not to a particular worker process. If several
`moor-file-worker` processes are attached, any one of them may receive the next request. Run one
file worker, or give every instance the same shared filesystem, when MOO code expects all requests
to see the same files.

## Running the worker

For a local IPC deployment using the default daemon socket paths:

```bash
moor-file-worker --sandbox-dir /srv/moor/files
```

Run the worker under an account that can access the sandbox but does not have broader privileges it
does not need.

The repository's `deploy/clustered/web-basic` Compose example includes an optional file-worker
profile:

```bash
cd deploy/clustered/web-basic
COMPOSE_PROFILES=file-worker ./start.sh
```

That profile maps `./moor-file-worker-sandbox/` on the host to `/sandbox` in the worker container.
Without the profile, the file worker remains disabled.

### Running on another host

For a remote worker, use TCP addresses for the daemon's worker sockets and enroll the worker for
CURVE authentication:

```bash
moor-file-worker \
  --sandbox-dir /srv/moor-files \
  --data-dir /var/lib/moor-file-worker \
  --rpc-address tcp://daemon.internal:7899 \
  --workers-request-address tcp://daemon.internal:7896 \
  --workers-response-address tcp://daemon.internal:7897 \
  --enrollment-address tcp://daemon.internal:7900 \
  --enrollment-token-file /etc/moor/enrollment-token
```

The daemon does not need direct access to `/srv/moor-files`, and it does not initiate a connection
to the worker. The worker host needs outbound access to the daemon's worker request, worker
response, and enrollment endpoints. Protect the enrollment token, restrict those endpoints with
firewall rules, and keep the worker's data directory private because it contains its identity and
CURVE keys.

Run `moor-file-worker --help` for all command-line options. See
[Clustered Deployment](clustered-deployment.md) for more about TCP endpoints, enrollment, and CURVE
authentication.
