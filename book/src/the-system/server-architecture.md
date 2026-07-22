# Server Architecture

Understanding mooR's architecture is key to successfully running and maintaining a mooR server.

## Components

mooR is built from several specialized components that work together:

- **Daemon** (`moor-daemon`): The core of the system. Manages the MOO database, executes verbs,
  handles object manipulation, and coordinates all MOO operations. Think of it as the "brain" that
  understands MOO code and maintains the virtual world's state.

- **Telnet host** (`moor-telnet-host`): Provides traditional telnet access for players. Handles the
  classic MOO experience that players familiar with LambdaMOO expect — text-based connections over
  port 8888 (by default).

- **Web host** (`moor-web-host`): Provides RESTful API endpoints and WebSocket connections for web
  clients. Handles authentication, property access, verb execution, and real-time communication via
  WebSockets.

- **Curl worker** (`moor-curl-worker`): Handles outbound HTTP requests from MOO code. When your MOO
  needs to fetch data from external APIs, send webhooks, or interact with web services, this
  component manages those network operations safely.

- **Frontend** (`moor-frontend`): A static file server or reverse proxy that serves the React Meadow
  application in production. Vite fills this role during development. The frontend communicates with
  the web host but is not embedded in the `moor` binary.

The daemon, hosts, and workers can run either inside a single `moor` process or as separate
processes. How you choose to run those backend components is the main deployment decision.

## Single-Process Deployment (Default)

The default way to run mooR is a single binary, `moor`, which runs the daemon, telnet host, web
host, and curl worker together in one process. This is the simplest deployment path: backend
communication uses in-process endpoints, so it needs no external RPC sockets, transport encryption,
or host enrollment. The provided single-process Docker Compose configurations use this layout. A
combined Debian package can be built locally, but the published `1.0.2` channel uses split-service
packages. This is the closest analogue to running a traditional LambdaMOO or ToastStunt server: one
process, one database, telnet and (optionally) web access built in.

```
┌─────────────────────────────────────────────┐
│                   moor                      │
│  ┌──────────┐  ┌────────────┐  ┌──────────┐ │
│  │ daemon   │  │ telnet host│  │ web host │ │
│  │ (VM, DB) │  │ (port 8888)│  │(:8081)   │ │
│  └──────────┘  └────────────┘  └──────────┘ │
│  ┌──────────────────────────────────────┐   │
│  │ curl worker (embedded)               │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
        ↑                    ↑
   telnet clients         web clients
```

The one piece that does not run inside `moor` is the web frontend client (Meadow). Meadow is a
static-served browser application: any static file server or reverse proxy (nginx, Apache, Caddy, a
CDN, etc.) serves its HTML/CSS/JS and proxies API and WebSocket requests to `moor`'s web host port
(8081 by default). Telnet-only deployments can skip the frontend entirely; web-enabled deployments
pair `moor` with a frontend server, as shown in the deployment examples (which use nginx).

### When to Use Single-Process

Single-process deployment is the right choice for:

- Getting started and development
- Single-server production deployments
- Any deployment where you don't need to split components across machines

Most users should start here.

## Split-Process and Clustered Deployment (Advanced)

The same components introduced above can run as independent processes that communicate over ZeroMQ
sockets. This is the advanced path, and there are two variants:

**Same-machine split-process** runs the daemon, hosts, and workers as separate processes on one
host, communicating over IPC (Unix domain sockets). Reasons to do this even when everything is on
one machine:

- **Process or privilege isolation**: Run the daemon under a restricted user with no network access,
  while the telnet host and web host run under separate users that only have the privileges they
  need. A compromise of a host process does not directly expose the database.
- **Independent restarts**: Restart or update a host or worker without taking down the daemon or
  dropping existing connections on other hosts.
- **Resource isolation**: Apply separate resource limits (cgroups, systemd units, containers) per
  component.

**Multi-machine clustered** distributes components across separate machines, communicating over TCP
with CURVE encryption. Reasons to do this:

- **Geographic distribution**: Place web hosts and telnet hosts in different availability zones,
  regions, or datacentres to reduce latency for users in different locations.
- **Differing firewall and network policies**: Run the daemon on a private network with strict
  inbound rules while exposing only the web host or telnet host to the public internet. Put the curl
  worker in a segment with outbound-only access.
- **Scaling hosts independently**: Run multiple web-host or telnet-host instances behind a load
  balancer. (Note: WebSocket connections are long-lived and stateful, so load balancing the web host
  requires sticky sessions or a Layer 4 balancer that supports connection affinity.)

### How Components Communicate

All components communicate through authenticated RPC (Remote Procedure Call) connections:

- The **daemon** acts as the central coordinator
- **Hosts** (telnet and web) connect to the daemon to relay player commands and receive responses
- **Workers** (like curl-worker) connect to the daemon to handle specific tasks
- Client/player authentication uses PASETO tokens signed by the daemon

### Communication Transport

mooR supports two communication modes between its components:

**In-process** (default, single-process) — Components run inside the `moor` binary and communicate
through in-process ZeroMQ endpoints. No sockets, no encryption, no configuration needed.

**IPC (Unix Domain Sockets)** — Used for same-machine clustered deployments where components run as
separate processes but on the same host. Uses filesystem permissions for security, no encryption
needed.

**TCP with CURVE Encryption** — Required when services run on separate machines. Uses CURVE
encryption with enrollment-based authentication. See `deploy/clustered/docker-compose.tcp.yml` for
an example configuration.

### When to Use Clustered Deployment

Clustered deployment is the advanced path. Use it when you have specific requirements that
single-process can't meet:

- **Security segmentation**: Isolate the daemon on a private network while exposing only hosts to
  the public internet
- **Load distribution**: Spread network I/O across multiple machines for high-traffic deployments
- **Functional isolation**: Run curl-worker in a restricted network with outbound-only access
- **Multi-datacenter**: Distribute hosts geographically for latency or redundancy
- **Horizontal scaling**: Scale hosts and workers independently (the daemon itself is a singleton)

For a complete guide to clustered deployment, see [Clustered Deployment](clustered-deployment.md).

## Advantages of the Modular Design

**Flexibility**: Start with a single process, split into components when needed, and distribute
across machines when your requirements demand it.

**Security**: Network operations are isolated in separate workers, reducing security risks to the
core MOO environment.

**Modernization**: The modular design allows adding new connection types (like web interfaces)
without changing the core MOO logic.

**Reliability**: If a host crashes, only that connection type is affected — the core MOO world
continues running.

## Build and Performance Considerations

### Build Profiles

mooR supports configurable build profiles to balance compilation time with runtime performance:

**Debug Profile (Default)**

- Optimized for fast builds during development
- Includes debug symbols for troubleshooting
- Suitable for development, testing, and small-scale deployments
- Significantly faster Docker builds (minutes vs. tens of minutes)

**Release Profile**

- Optimized for production performance
- Aggressive compiler optimizations and link-time optimization (LTO)
- Smaller binary sizes and maximum runtime performance
- Longer build times due to optimization passes

The frontend (web-based) component always uses optimized builds via Vite, regardless of the backend
build profile.

### Deployment Approaches

Regardless of whether you choose single-process or clustered, mooR provides several approaches to
manage the deployment:

- **Docker Compose**: Orchestrates everything automatically (recommended for most users)
- **Debian Packages**: Handles system integration for Debian-based systems
- **Manual Setup**: For custom deployments or development environments

**Docker Compose Examples:**

```bash
# Development build (fast compilation)
docker compose up

# Production build (optimized performance)
BUILD_PROFILE=release docker compose up
```

The next sections cover each of these deployment approaches in detail.
