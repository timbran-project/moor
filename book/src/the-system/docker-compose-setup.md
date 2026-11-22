# Docker Compose Setup

Docker Compose is one way to deploy a mooR server. The default compose setup runs the combined
`moor` backend plus the Meadow frontend container.

## What is Docker Compose?

Docker Compose is a tool that helps you define and run multi-container applications. For the
single-process setup, it manages the backend container, frontend container, ports, and data mounts.

## Deployment Configurations

mooR provides several Docker Compose configurations to suit different needs:

### Deployment Examples

The `deploy/` directory contains example configurations:

**`deploy/single-process/basic/`** : Combined backend exposing telnet and the embedded web API, with
the embedded curl worker enabled.

**`deploy/single-process/web/`** : Combined backend plus a static file server (nginx) serving
Meadow, curl worker enabled.

Both single-process examples start a new world from the Snore core unless `MOOR_CORE` names another,
such as `cowbell`.

**`deploy/clustered/telnet-only/`** : Split daemon and telnet host.

**`deploy/clustered/web-basic/`** : Split web deployment with HTTP.

**`deploy/clustered/web-ssl/`** : Split web deployment with HTTPS/TLS using Let's Encrypt
certificates.

**`deploy/debian-packages/`** : Native systemd services for Debian/Ubuntu without Docker.

Most deployment examples include:

- Automated testing scripts
- Detailed README with setup instructions
- Services run as your user to avoid permission issues

### Development & Quick Start

**`docker-compose.yml`** (repository root) : For development, testing, and quick evaluation. Builds
the single-process `moor` backend and the Meadow frontend.

**`deploy/clustered/docker-compose.tcp.yml`** : For testing multi-machine deployments with TCP and
CURVE encryption.

## Prerequisites

- Docker and Docker Compose installed (most modern Docker installations include Compose by default)
- At least 1GB RAM recommended
- Ports 8080 (web) and/or 8888 (telnet) available, depending on configuration

You can verify your Docker installation with:

```bash
docker --version
docker compose version
```

## Production Deployment Setup

### Choosing a Configuration

1. **Single-process backend**: Use `deploy/single-process/basic/`
2. **Single-process web**: Use `deploy/single-process/web/`
3. **Split-process telnet**: Use `deploy/clustered/telnet-only/`
4. **Split-process web, behind reverse proxy**: Use `deploy/clustered/web-basic/`
5. **Split-process web with HTTPS**: Use `deploy/clustered/web-ssl/`
6. **Native packages** (no Docker): Use `deploy/debian-packages/`

### Deployment Steps

The root Compose file builds the backend and Meadow images from monorepo-relative contexts. Keep the
repository checkout intact when using that development configuration.

The deployment examples under `deploy/` pull the multi-platform `ghcr.io/timbran-project/moor`
image, so Docker selects x86-64 or arm64 automatically. They use the `latest` tag unless told
otherwise. For a deployment that stays on the version you tested, name a release: the single-process
examples take it from `MOOR_VERSION` in `.env`, and in the clustered examples you edit the image tag
in the compose file. The backend image contains the compiled Meadow assets used by the bundled nginx
configurations. A standalone Meadow image is also published as
`ghcr.io/timbran-project/moor-frontend`.

The deployment examples may be copied to a deployment host when using the published images. Keep a
repository checkout available if you uncomment their monorepo-relative local `build:` sections.

For example, from the repository root:

```bash
cd deploy/single-process/web
cp .env.example .env
docker compose up -d
docker compose ps
docker compose logs -f
```

The single-process examples are operated directly with Docker Compose. Clustered examples include
additional `start.sh` and `test.sh` scripts where enrollment, permissions, or multi-service checks
need automation. Follow the README in the selected configuration directory.

The single-process examples read these settings from `.env`:

| Setting               | What it does                                             | Default        |
| --------------------- | -------------------------------------------------------- | -------------- |
| `USER_ID`, `GROUP_ID` | The user and group the containers run as                 | `1000`, `1000` |
| `MOOR_VERSION`        | The release to run, which is the image tag               | `latest`       |
| `MOOR_BIND`           | The address the published ports listen on                | `0.0.0.0`      |
| `MOOR_CORE`           | The core a new world starts from, a directory in `cores` | `snore`        |

### Before You Open It to Anyone

A new world has a wizard account, which can do anything in it, and its password is one everybody
knows. In a Snore or LambdaCore world the wizard is `wizard` and has no password. In a Cowbell world
it is `archwizard`, with the password `test`. On a machine other people can reach, anyone who
connects first can take the world over.

So change the password before the server is reachable. The simplest way is to start with
`MOOR_BIND=127.0.0.1`, which makes the ports answer only on the machine itself. Connect from that
machine and change it:

```
connect wizard
@password <new-password>
```

or, for Cowbell:

```
connect archwizard test
@password test <new-password>
```

Then remove the setting and run `docker compose up -d` again.
[Starting on a Cloud Machine](cloud-machine.md) walks through the same steps over an SSH tunnel.

## Development Quick Start

For development, testing, and quick evaluation, mooR provides two pre-configured start scripts in
the repository root. These scripts automatically handle Docker permissions and resource isolation.

### 1. Choose a Core

**Cowbell** (Modern core with web-native features):

```bash
./scripts/start-moor-cowbell.sh
```

**Snore** (A classic MOO core, forked from LambdaCore and written for mooR):

```bash
./scripts/start-moor-snore.sh
```

On the first start, the script imports that core's objdef source into a new persistent database. On
later starts, it opens the existing database and skips the import. The source directory is not
watched for changes. See [Starting a MOO from Objdef Source](bootstrapping-from-source.md) for a
step-by-step explanation.

### 2. Isolated Environments

Each script uses its own isolated runtime directory:

- `run-cowbell/`
- `run-snore/`

This ensures that you can switch between cores without database or keypair "pollution". Each
environment maintains its own persistent database, configuration, and host keys.

### 3. Build Profiles

By default, these scripts use a high-performance **release** build (`release-fast`). For a faster
initial compile during development, you can use the `--debug` flag:

```bash
./scripts/start-moor-cowbell.sh --debug
```

Access the system via:

- **Web Client**: http://localhost:8080
- **Telnet Interface**: `telnet localhost 8888`

## Common Operations

These commands work for all Docker Compose configurations:

### Viewing Logs

```bash
# View logs from all services
docker compose logs -f

# View logs from a specific service
docker compose logs -f moor
docker compose logs -f moor-frontend
```

The `-f` flag "follows" the logs, showing new output as it appears.

### Stopping Services

If running in the foreground, press `Ctrl+C`. For background services:

```bash
docker compose down
```

This stops and removes containers but preserves data directories.

### Restarting Services

```bash
docker compose restart
```

This restarts the containers but keeps the existing database. It does not re-import edits made to a
core's `.moo` source files.

### Rebuilding Container Images

```bash
docker compose build --no-cache
docker compose up -d
```

Rebuilding the container also preserves the existing database. If you changed objdef source, choose
one of the update methods in [Starting a MOO from Objdef Source](bootstrapping-from-source.md). Do
not remove a database merely to force an import unless you are prepared to lose changes that exist
only in that database.

## Data Persistence

All Docker Compose configurations store data in local directories. For the development scripts,
these are consolidated under core-specific runtime directories:

- `./run-cowbell/` or `./run-snore/`
  - `moor-data/` - Main database directory
  - `hosts/` - Host-specific state and keys
  - `config/` - Server cryptographic keypairs
  - `export/` - Objdef exports

**Important**: These directories are created with your user permissions. Always backup your data
regularly.

### Automatic Database Exports

When an export path and checkpoint interval are configured, the daemon automatically exports the
database at regular intervals. The command-line option is `--checkpoint-interval-seconds`; a core
can also provide a database checkpoint interval. These exports are written in
**[objdef format](objdef-file-format.md)**, a human-readable representation of the database.

Objdef exports are useful as portable backups because they are:

- **Human-readable and editable**: You can read, understand, and manually edit the exported files
- **Version control friendly**: Text format works well with git, allowing you to track changes over
  time
- **Compression-friendly**: Objdef files compress extremely well, making archives space-efficient
- **Format-stable**: While the binary database format may change between mooR versions, objdef
  remains stable and portable

The persistent database under `moor-data/` is used for normal startup. Objdef checkpoints are
written under the separate `export/` directory. Copy checkpoints regularly to safe storage, compress
them, and consider putting them in revision control for change tracking.

> **Exported files are not live files.** Editing a checkpoint does not change the running MOO, and
> the next checkpoint does not read changes from an earlier one.

## Customization

You can modify `docker-compose.yml` files to suit your needs:

- **Change ports**: Edit the `ports:` mappings
- **Configure services**: Add environment variables or command-line flags
- **Enable workers**: Use `--enable-curl-worker` or config when embedded worker support is needed

For frontend proxy configuration (web deployments), edit the proxy config (e.g. `nginx.conf` in the
provided examples) and restart the frontend:

```bash
docker compose restart moor-frontend
```

## Troubleshooting

### Common Issues

**Port conflicts** : If ports 8080 (web) or 8888 (telnet) are already in use, modify the port
mappings in the compose file.

**Permission denied errors** : The containers run as the user and group named by `USER_ID` and
`GROUP_ID`, and must be able to write to the data directories. Set both to your own (`id -u` and
`id -g`) in `.env`, and create the data directories yourself before the first start, since Docker
creates missing ones as root. The clustered examples have a `./start.sh` that does this for you.

**Services won't start** : Check logs with `docker compose logs <service-name>`. Verify all required
directories exist and are accessible.

**Build failures** : Ensure you have enough disk space and memory. Rust compilation requires
substantial resources.

**Connection issues** : Verify containers are running with `docker compose ps`, then check backend
and frontend logs.

**Database won't import** : Only a new database imports the core source, and the first import can
take several minutes. If a database already exists, mooR deliberately skips import. Check
`docker compose logs moor` for messages showing which path it took. Before creating a fresh
database, preserve the existing one if it contains changes you need.

### Testing Your Deployment

Clustered configurations in `deploy/` include test scripts:

```bash
cd deploy/clustered/web-basic
./test.sh
```

These validate that services are running correctly and can communicate.

### Getting Help

- **Docker Compose docs**: [docs.docker.com/compose/](https://docs.docker.com/compose/)
- **mooR issues**:
  [github.com/timbran-project/moor/issues](https://github.com/timbran-project/moor/issues)
- **Community**: [Discord](https://discord.gg/Ec94y5983z)

## Advanced: Multi-Machine Deployments

For running services across multiple machines, see `deploy/clustered/docker-compose.tcp.yml`, which
demonstrates:

- TCP with CURVE encryption for inter-service communication
- Enrollment token setup for host authentication
- Network configuration for distributed deployments

This is an advanced configuration. Most users should use single-process deployments.
