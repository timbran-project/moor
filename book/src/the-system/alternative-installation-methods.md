# Alternative Installation Methods

Docker Compose is the usual way to run mooR. This page covers three ways to run it without
containers: prebuilt binaries, Debian packages, and building from source.

## Prebuilt Binaries

Each mooR release has a tarball of the server programs, ready to run. Use it if you want neither
containers nor a build from source, which needs the Rust toolchain and a good deal of disk space.

The tarballs are on the release's page on
[GitHub](https://github.com/timbran-project/moor/releases), one for each processor type:

- `moor-<release>-linux-x86_64.tar.gz`
- `moor-<release>-linux-aarch64.tar.gz`

They hold the same binaries as the container image for that release.

### What You Need

- 64-bit Linux.
- glibc 2.35 or newer, and the C++ runtime that comes with GCC 12 or newer. Debian 12 and Ubuntu
  22.04 have both, as do later releases of each. RHEL 9 and its rebuilds do not.
- `git`, if you use the Git worker.

### Checking the Download

Each tarball has a `.sha256` file beside it:

```bash
sha256sum -c moor-*.tar.gz.sha256
```

Each also has a build attestation, which shows that the project's release process made it. With a
recent version of the GitHub command-line tool:

```bash
gh attestation verify moor-*.tar.gz --repo timbran-project/moor
```

### What Is in It

```bash
tar xzf moor-<release>-linux-x86_64.tar.gz
cd moor-<release>-linux-x86_64
./moor --version
```

- `moor`: the whole server in one process. Start with this one.
- `moor-daemon`, `moor-telnet-host`, `moor-web-host`: the same server as separate processes, for a
  [clustered deployment](clustered-deployment.md).
- `moor-curl-worker`, `moor-file-worker`, `moor-git-worker`: workers that let MOO code make HTTP
  requests, read and write files, and use Git.
- `moorc`: the compiler. It builds and exports databases and runs tests.
- `moor-emh`: the [repair tool](moor-emh-tool.md) for a database the server cannot start.
- `web-client/`: the files of the web client, to serve with a web server of your choice.

The tarball has no world in it. A new server needs a core to start from; see
[Understanding MOO Cores](understanding-moo-cores.md) and
[Starting a MOO from Objdef Source](bootstrapping-from-source.md). The cores are in the mooR
repository under `cores/`.

### What Is Left to You

A tarball installs nothing. Creating a user for the server, choosing where its data lives, starting
it at boot and upgrading it are yours to arrange. [Server Configuration](server-configuration.md)
lists the options each program takes, and every program prints them with `--help`. If you want those
things done for you, use Docker Compose or the Debian packages.

## Debian Packages

For Debian-based systems (including Ubuntu), mooR provides native `.deb` packages that integrate
cleanly with your system's package management and systemd service management.

### About Debian Packages

mooR can be built as several package types:

- **moor**: The combined single-process binary (daemon, telnet host, web host, and curl worker in
  one process) with a single systemd service. This is the recommended package for most deployments.
- **Split-service packages**: `moor-daemon`, `moor-telnet-host`, `moor-web-host`, and
  `moor-curl-worker` as separate packages with individual systemd services. Use these when you need
  clustered deployment across multiple machines.
- **moor-web-client**: Architecture-independent React Meadow static assets for deployments that
  serve the web frontend from a Debian package.

The server packages integrate with systemd, create the necessary users and directories, and include
the LambdaMOO-based lambda-moor core database by default.

Build the packages from the repository with the scripts it provides. A release's page on GitHub
lists the files that release includes; do not install packages from one release line onto a database
from another, since the database format changes between major versions.

### Building and Installing

The scripts are in `deploy/debian-packages/`:

```bash
cd deploy/debian-packages
./build-all-packages.sh

# Combined package:
sudo apt install ../../target/debian/moor_*.deb

# Or split-service packages:
sudo apt install \
    ../../target/debian/moor-daemon_*.deb \
    ../../target/debian/moor-telnet-host_*.deb \
    ../../target/debian/moor-web-host_*.deb \
    ../../target/debian/moor-curl-worker_*.deb
```

### Detailed Documentation

For detailed installation, configuration, service management, testing, and troubleshooting:

**→ See
[`deploy/debian-packages/README.md`](https://github.com/timbran-project/moor/blob/main/deploy/debian-packages/README.md)**

This includes:

- Complete installation and post-installation configuration
- Service management with systemd
- nginx setup for the web client
- Backup and restore procedures
- Automated testing
- Troubleshooting guide

### When to Use Debian Packages

Debian packages are ideal when:

- You're running a Debian-based Linux distribution
- You want system-level integration (systemd services, standard file locations)
- You prefer traditional package management over containers
- You're setting up a production server on bare metal or VPS

Use the combined `moor` package for a single server. The split-service packages are for the layout
described in [Clustered Deployment](clustered-deployment.md).

## Building from Source

For developers, custom deployments, or platforms without pre-built packages, you can compile mooR
from source code.

### Prerequisites

You'll need the Rust toolchain installed. The recommended way is using `rustup`:

```bash
# Install rustup (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Follow the installation prompts, then restart your shell or run:
source ~/.cargo/env
```

### Building Process

1. **Clone the repository**:
   ```bash
   git clone https://github.com/timbran-project/moor.git
   cd moor
   ```

2. **Build all components**:
   ```bash
   cargo build --release --all-targets
   ```

   This will take some time as Rust compiles all dependencies and mooR components.

3. **Find your binaries**: After building, you'll find the executables in `target/release/`:
   - `moor` — combined single-process binary (recommended for most deployments)
   - `moor-daemon` — daemon only (for clustered deployment)
   - `moor-telnet-host` — telnet host only
   - `moor-web-host` — web host only
   - `moor-curl-worker` — curl worker only

### Manual Configuration

When building from source, you'll need to manually set up:

- **PASETO authentication keys**: The daemon auto-generates these keys with the `--generate-keypair`
  flag (creates `moor-signing-key.pem` and `moor-verifying-key.pem`)
- **Configuration files**: Create appropriate configuration for each component
- **Core database**: Install and configure your chosen MOO core
- **Service coordination**: For single-process deployment, just run `moor` — no coordination needed.
  For clustered deployment, ensure all components can communicate properly (see
  [Server Architecture](server-architecture.md#communication-transport))
  - Single-process: In-process endpoints, no configuration needed
  - Same-machine clustered: IPC (Unix domain sockets), simplest split-process option
  - Multi-machine clustered: TCP with CURVE encryption requires enrollment tokens (see
    `--rotate-enrollment-token` flag)

The `docker-compose.yml` file provides an example of how to configure a single-process deployment.

### When to Build from Source

Source builds are best for:

- Development and testing
- Platforms without Debian package support
- Custom configurations requiring code modifications
- Learning how mooR works internally
- Contributing to the project

## Configuration Reference

Regardless of your installation method, you'll need to configure mooR's components. The arguments
and options for the server executables are documented in the
[Server Configuration](server-configuration.md) chapter.

## Choosing Your Method

| Method                | Best for                           | What you get                                 | What is left to you                  |
| --------------------- | ---------------------------------- | -------------------------------------------- | ------------------------------------ |
| **Docker Compose**    | Most servers                       | A complete, working setup                    | Knowing some Docker                  |
| **Cloud machine**     | A new rented machine               | A running server from first boot             | HTTPS, backups, upgrades             |
| **Prebuilt binaries** | No containers, no compiling        | The programs, ready to run                   | Everything around them               |
| **Debian packages**   | Debian or Ubuntu, managed services | systemd services and standard file locations | Building the packages                |
| **Source build**      | Development, other platforms       | Full control and the latest code             | Toolchain, build time, all the setup |

## Getting Help

For installation issues:

- Check the [mooR GitHub repository](https://github.com/timbran-project/moor) for the latest
  installation instructions
- Review the `docker-compose.yml` file for configuration examples
- Consult the community forums or Discord for platform-specific guidance

Remember that regardless of your installation method, you'll also need to choose and install a MOO
core database - see [Understanding MOO Cores](understanding-moo-cores.md) for guidance on that
crucial next step.
