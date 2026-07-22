# mooR Deployment Guide

This directory contains deployment configurations and guides for various mooR deployment scenarios.
Choose the approach that best fits your needs.

## Single-Process vs Clustered Deployments

The default deployment path is the combined `moor` binary. It runs the daemon, telnet host, and web
host in one process.

_Clustered_ deployments run the daemon, hosts, and workers as separate processes. The clustered
examples under `clustered/` use IPC for _same_-machine deployments and TCP/CURVE for _multi_-machine
testing.

- **Single-process deployments** use the `moor` binary and are the intended default for one-host
  installs.
- **Same-machine clustered deployments** use separate binaries with IPC sockets.
- **Multi-machine clustered deployments** use TCP sockets with CURVE encryption and enrollment
  tokens.

## Quick Decision Guide

**Are you...**

- **Just getting started or developing?** → Use the [root docker-compose.yml](../docker-compose.yml)
  for a quick single-process setup.
- **Testing TCP/CURVE enrollment flows?** → Use
  [clustered/docker-compose.tcp.yml](clustered/docker-compose.tcp.yml) for multi-machine deployment
  testing.

- **Deploying with web access on a local network?** → See [single-process/web/](single-process/web/)
  for a single-process web deployment.

- **Running only telnet plus the embedded API?** → See
  [single-process/basic/](single-process/basic/) for the minimal single-process Docker deployment.

- **Need the split-process examples?** → See [clustered/](clustered/).

- **Running a public web-enabled MOO on the internet?** → See
  [clustered/web-ssl/](clustered/web-ssl/) for the existing HTTPS Docker deployment with Let's
  Encrypt.

- **Installing on a traditional Linux server?** → See [debian-packages/](debian-packages/) for
  systemd-based deployment

- **Need Kubernetes?** → See [clustered/kubernetes/](clustered/kubernetes/).

## Deployment Options

### 1. Development Options

Several tools are available for local development and testing:

#### Docker Compose (Containerized)

**Location**: [../docker-compose.yml](../docker-compose.yml)

**Purpose**: Quick containerized development setup

Uses a local build of the combined backend plus the Meadow frontend container.

**Quick start**:

```bash
docker compose up
```

#### process-compose (Native)

**Location**: [../process-compose.yaml](../process-compose.yaml) and
[../process-compose-dev.yaml](../process-compose-dev.yaml)

**Purpose**: Run all mooR services natively on your host using process orchestration

Runs all mooR services natively on your host with no Docker overhead, managing them as local
processes using IPC for inter-service communication. The `process-compose-dev.yaml` variant uses
debug builds for faster iteration, while `process-compose.yaml` uses release builds (slow build
times but optimized runtime performance).

**Prerequisites**: Install [process-compose](https://github.com/F1bonacc1/process-compose)

**More info**:
[process-compose documentation](https://f1bonacc1.github.io/process-compose/launcher/)

**Quick start**:

```bash
# Development mode (debug builds)
process-compose -f process-compose-dev.yaml up

# Production-like mode (release builds)
process-compose up
```

#### bacon (File-Watching Development)

**Location**: [../bacon.toml](../bacon.toml)

**Purpose**: File-watching development with automatic restarts

Watches source files for changes and automatically rebuilds and restarts services. The default job
runs the combined `moor` binary; split-service jobs are still available for work on individual
components.

**Prerequisites**: Install bacon (`cargo install bacon`)

**More info**: [bacon documentation](https://dystroy.org/bacon/)

**Available jobs**:

```bash
bacon moor            # Run single-process moor with file watching
bacon daemon          # Run daemon with file watching (release build)
bacon daemon-debug    # Run daemon with file watching (debug build)
bacon daemon-debug-traced  # Run daemon with tracing enabled
bacon telnet          # Run telnet host with file watching
bacon web             # Run web host with file watching
bacon test            # Run tests with file watching
bacon curl-worker     # Run curl worker with file watching
```

#### npm Scripts (Web Client Development)

**Location**: [../package.json](../package.json)

**Purpose**: Workflows for Meadow development in [clients/meadow/](../clients/meadow/)

Starts the combined backend and Vite dev server together using concurrently, providing hot module
reloading for web client changes. Includes tracing variants for debugging backend issues while
working on the UI.

**Available scripts**:

```bash
# Development servers
npm run meadow:dev           # Meadow dev server only (port 3000)
npm run moor:dev             # Single-process backend
npm run moor:traced          # Single-process backend with tracing enabled
npm run web-host:dev         # Web host only

# Full stack
npm run full:dev             # Web client + single-process backend
npm run full:dev-traced      # Web client + traced single-process backend

# Build
npm run web:build            # Build schema, SDK, and Meadow
npm run full:build           # Build web client + single-process backend (release)
```

**Recommended Development Workflow**:

1. **First time / Quick demo**: Use Docker Compose
   ```bash
   docker compose up
   ```

2. **Active web client development** (working in `clients/meadow/`): Use npm scripts
   ```bash
   npm run full:dev      # Starts daemon, web-host, and Vite dev server with HMR
   ```

3. **Active backend development** (working on Rust code): Use bacon for file watching
   ```bash
   bacon moor            # Terminal 1: single-process backend with file watching
   npm run meadow:dev    # Terminal 2: Meadow dev server only
   ```

4. **Testing full stack natively**: Use process-compose
   ```bash
   process-compose -f process-compose-dev.yaml up
   ```

---

### 2. Single-Process Basic Deployment

**Location**: [single-process/basic/](single-process/basic/)

**Purpose**: One backend process with telnet, the embedded web API, and the embedded curl worker

Runs the combined `moor` binary in one container. Telnet is exposed on port 8888, the embedded web
API is exposed on port 8080, and the embedded curl worker is enabled.

**Quick start**:

```bash
cd single-process/basic
cp .env.example .env
docker compose up -d
telnet localhost 8888
```

[Read full guide →](single-process/basic/README.md)

---

### 3. Single-Process Web Deployment

**Location**: [single-process/web/](single-process/web/)

**Purpose**: One backend process with nginx serving Meadow

Runs the combined `moor` backend in one container and an nginx container for the Meadow frontend.
The browser UI is exposed on port 8080.

**Quick start**:

```bash
cd single-process/web
cp .env.example .env
docker compose up -d
# Visit http://localhost:8080
```

[Read full guide →](single-process/web/README.md)

---

### 4. Clustered Docker Examples

**Location**: [clustered/](clustered/)

**Purpose**: Split-process deployments

These examples run separate daemon, host, frontend, and worker containers. They are useful when
testing the clustered architecture or deploying with separate service boundaries.

- [clustered/telnet-only/](clustered/telnet-only/)
- [clustered/web-basic/](clustered/web-basic/)
- [clustered/web-ssl/](clustered/web-ssl/)
- [clustered/kubernetes/](clustered/kubernetes/)
- [clustered/docker-compose.tcp.yml](clustered/docker-compose.tcp.yml)

---

### 5. Debian Package Deployment

**Location**: [debian-packages/](debian-packages/)

**Purpose**: Traditional Linux installation with systemd services

Native Linux installation using standard Debian/Ubuntu package management with systemd service
control. Provides a `moor` single-process package and split-service packages for `moor-daemon`,
`moor-telnet-host`, `moor-web-host`, and web client assets. Best suited for traditional Linux server
administration, integration with existing system management tools, and users comfortable with
systemd on Debian/Ubuntu based systems.

**Quick start**:

```bash
./deploy/debian-packages/build-all-packages.sh

# Single-process service:
sudo dpkg -i target/debian/moor_*.deb
sudo systemctl start moor

# Or split services:
sudo dpkg -i target/debian/moor-daemon_*.deb
sudo dpkg -i target/debian/moor-telnet-host_*.deb
sudo dpkg -i target/debian/moor-web-host_*.deb
sudo dpkg -i target/debian/moor-web-client_*.deb
sudo systemctl start moor-daemon
```

[Read full guide →](debian-packages/README.md)

---

### 6. Kubernetes Deployment

**Location**: [clustered/kubernetes/](clustered/kubernetes/)

**Purpose**: Cloud-native deployment with horizontal scaling and distributed architecture

Production Kubernetes deployment with TCP/CURVE communication, enrollment-based authentication, and
horizontal pod autoscaling. Includes StatefulSet for daemon, Deployments for hosts/workers,
Services, Ingress, NetworkPolicies, and support for cert-manager TLS certificates. Best suited for
cloud environments, multi-datacenter deployments, organizations using Kubernetes, and deployments
requiring horizontal scaling and high availability.

**Quick start**:

```bash
cd clustered/kubernetes
# Configure image registry in kustomization.yaml
# Build and push images, or load into kind/minikube
kubectl apply -k .
```

**Test locally with kind**:

```bash
cd clustered/kubernetes
./test.sh
```

[Read full guide →](clustered/kubernetes/README.md)

---

## Architecture Overview

All deployment options use the same mooR architecture:

```
┌─────────────────┐
│   Web Client    │ (Optional: Browser-based interface)
│  (nginx + JS)   │
└────────┬────────┘
         │ HTTP/WebSocket
┌────────▼────────┐
│  moor-web-host  │ or embedded web host
└────────┬────────┘
         │
         │ ZeroMQ RPC
┌────────▼────────┐        ┌──────────────┐
│  moor-daemon    │◄───────┤ Telnet users │
│  (Core MOO VM)  │        └──────────────┘
└────────┬────────┘             ▲
         │                      │
    ┌────▼───────┐     ┌────────┴────────┐
    │ moor-curl- │     │ moor-telnet-host│
    │   worker   │     │   (Telnet API)  │
    └────────────┘     └─────────────────┘
```

**Components**:

- **moor**: Combined daemon, telnet host, web host, and optional embedded workers for single-process
  deployments
- **moor-daemon**: Core MOO server (database, VM, task scheduler)
- **moor-telnet-host**: Traditional telnet interface
- **moor-web-host**: Web API and WebSocket server
- **moor-frontend**: Static web client (HTML/CSS/JS)
- **moor-curl-worker**: Handles outbound HTTP from MOO code

Single-process deployments use in-process ZeroMQ endpoints inside `moor`. Clustered same-machine
deployments use IPC sockets, and multi-machine clustered deployments use TCP/CURVE.

## Common Configuration

### Ports

Default ports used across deployments:

- **8080**: Web interface (HTTP)
- **443**: Web interface (HTTPS, SSL deployments only)
- **8888**: Telnet interface
- **8081**: Web API server (internal)

**Note**: Single-process deployments do not expose internal ZeroMQ endpoints. Clustered deployments
only expose extra TCP ports when explicitly configured to do so.

### Environment Variables

Common environment variables across deployments:

- `BUILD_PROFILE`: `debug` or `release` (Docker only)
- `DATABASE_NAME`: Database filename (default: `production.db` for production, `development.db` for
  dev)
- `RUST_BACKTRACE`: Rust backtrace level for debugging (`0`, `1`, or `full`)
- `TELNET_PORT`: Telnet listen port (default: `8888`)
- `WEB_PORT`: Web listen port (default: `8080`, or `80`/`443` with SSL)

## Data Management

### Backups

All deployments store data in similar locations:

**Docker deployments**:

```bash
# Backup
tar czf moor-backup-$(date +%Y%m%d).tar.gz ./moor-data/

# Restore
tar xzf moor-backup-YYYYMMDD.tar.gz
```

**Debian packages**:

```bash
# Backup
sudo systemctl stop moor-daemon
sudo tar czf moor-backup-$(date +%Y%m%d).tar.gz /var/spool/moor-daemon/
sudo systemctl start moor-daemon
```

### Restore from Export

All deployments can use the [restore-from-export.sh](scripts/restore-from-export.sh) script to
restore from a mooR export snapshot.

See [scripts/restore-from-export.sh](scripts/restore-from-export.sh) documentation.

## Upgrading

### Docker Deployments

```bash
# 1. Backup data
tar czf backup-$(date +%Y%m%d).tar.gz moor-data/

# 2. Pull latest changes (if using git)
git pull

# 3. Rebuild and restart
docker compose down
docker compose build --no-cache
docker compose up -d
```

### Debian Package Deployments

```bash
# 1. Backup data
sudo systemctl stop moor-daemon
sudo tar czf backup-$(date +%Y%m%d).tar.gz /var/spool/moor-daemon/
sudo systemctl start moor-daemon

# 2. Install new packages
sudo dpkg -i moor-daemon_*.deb
sudo dpkg -i moor-telnet-host_*.deb
sudo dpkg -i moor-web-host_*.deb

# 3. Restart services
sudo systemctl restart moor-daemon moor-telnet-host moor-web-host
```

## Security Considerations

### General Recommendations

Always change the wizard password after first login, and use a firewall to restrict access to
necessary ports. Keep mooR and system packages updated, implement regular automated backups, and
monitor logs for suspicious activity.

### Docker-Specific

1. **Limit port exposure**: Only expose necessary ports to host
2. **Use secrets**: Store sensitive data in Docker secrets (not in compose files)
3. **Network isolation**: Use Docker networks to isolate services
4. **Read-only volumes**: Mount sensitive data as read-only where possible

### Production Deployments

1. **SSL/TLS**: Always use HTTPS for internet-facing deployments
2. **Certificate monitoring**: Monitor certificate expiration
3. **Rate limiting**: Implement rate limiting on web endpoints
4. **Intrusion detection**: Consider IDS/IPS for public servers
5. **Regular audits**: Audit user permissions and access logs

## Utilities and Scripts

### Available in This Directory

- [scripts/restore-from-export.sh](scripts/restore-from-export.sh) - Restore database from export
  snapshot
- [debian-packages/build-all-packages.sh](debian-packages/build-all-packages.sh) - Build all Debian
  packages
- [../clients/meadow/deploy/debian-packages/build-web-client-deb.sh](../clients/meadow/deploy/debian-packages/build-web-client-deb.sh)
  - Build the Meadow package

### Other Files

- [Dockerfile-forgejo-builder](Dockerfile-forgejo-builder) - CI/CD builder image (for Forgejo
  Actions)

## Testing Deployments

Automated test scripts are provided to validate that deployment configurations work correctly.

### Running All Tests

To test all Docker-based deployments:

```bash
cd deploy/
./test-all.sh
```

This runs automated tests for:

- `clustered/telnet-only/` - Split telnet-only deployment
- `clustered/web-basic/` - Split HTTP web deployment
- `clustered/web-ssl/` - Split HTTPS web deployment

### Testing Individual Deployments

Each deployment directory has its own `test.sh` script:

```bash
# Test telnet-only deployment
cd deploy/clustered/telnet-only/
./test.sh

# Test web-basic deployment
cd deploy/clustered/web-basic/
./test.sh

# Test web-ssl deployment
cd deploy/clustered/web-ssl/
./test.sh
```

### What the Tests Check

The automated tests verify:

- Services start successfully
- Containers become healthy
- Network ports are accessible
- HTTP/telnet endpoints respond
- Basic connectivity works
- No critical errors in logs

### Test Requirements

The test scripts require:

- `docker` and `docker compose`
- `curl` for HTTP testing
- `nc` (netcat) for port checking
- `telnet` for telnet protocol testing
- `jq` for JSON parsing (optional but recommended)

### Testing Debian Packages

Debian package deployment requires `cargo-deb` and `incus`:

```bash
cargo install cargo-deb
# Install incus from your distribution
```

See [debian-packages/README.md](debian-packages/README.md) for testing procedures.

### Testing Kubernetes

Kubernetes deployment testing requires `kind` and `kubectl`:

```bash
# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/

# Install kubectl
# See https://kubernetes.io/docs/tasks/tools/
```

The test creates a local kind cluster, builds and loads images, deploys manifests, and validates all
components.

### SSL Certificate Testing

The `clustered/web-ssl/` test cannot validate SSL certificates in automated testing because Let's
Encrypt requires a real domain with valid DNS. To fully test SSL:

1. Deploy on a server with a real domain name
2. Configure DNS to point to your server
3. Set proper `VIRTUAL_HOST` and `LETSENCRYPT_HOST` in `.env`
4. Run `docker compose up` and verify certificates are obtained
5. Test HTTPS access with a browser

## Getting Help

### Documentation

- **mooR Book**: [https://timbran.org/book/html/](https://timbran.org/book/html/)
- **Repository**: [https://codeberg.org/timbran/moor](https://codeberg.org/timbran/moor)
- **Issues**: [https://codeberg.org/timbran/moor/issues](https://codeberg.org/timbran/moor/issues)

### Community

- **Discord**: [https://discord.gg/Ec94y5983z](https://discord.gg/Ec94y5983z)

### Reporting Issues

When reporting deployment issues, please include:

1. Deployment method used (Docker, Debian packages, etc.)
2. Operating system and version
3. mooR version (from logs or `moor --version`)
4. Relevant error messages or logs
5. Steps to reproduce

## Contributing

Contributions to deployment configurations are welcome! Please:

1. Test thoroughly in your environment
2. Document prerequisites and setup steps
3. Follow existing style and structure
4. Submit pull requests to [Codeberg](https://codeberg.org/timbran/moor)

See [CONTRIBUTING.md](../CONTRIBUTING.md) for more details.

## License

mooR is free software licensed under AGPL-3.0-only. See [../LICENSE](../LICENSE) for details.

Note: Core databases in `../cores/` have separate licensing. See
[../cores/LICENSING.md](../cores/LICENSING.md).
