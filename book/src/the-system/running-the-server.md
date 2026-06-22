# Running the mooR Server

Once you understand the different ways to get involved with MOO and the importance of cores, you're
ready to tackle the technical aspects of actually running a mooR server. This section covers the
practical mechanics of getting mooR up and running.

## Quick Start Guide

The fastest way to get mooR running is with the provided quick-start scripts, which handle Docker
setup and environment isolation automatically.

1. Clone the mooR repository
2. Run one of the start scripts in the repository root:
   - For the modern Cowbell core: `./scripts/start-moor-cowbell.sh`
   - For classic LambdaCore: `./scripts/start-moor-lambdacore.sh`
3. Connect to your MOO via http://localhost:8080/ -- or `telnet` (or your favourite MUD client) to
   port 8888

For detailed instructions and other installation options, see the sections below.

## Single-Process vs Clustered Deployment

mooR can run in two modes:

**Single-process (default)** runs the combined `moor` binary, which bundles the daemon, telnet host,
web host, and curl worker into one process. This is the simplest path and is what the provided
Docker Compose configurations and Debian packages use by default. Most users should start here.

**Clustered deployment (advanced)** runs the daemon, hosts, and workers as separate processes that
communicate over ZeroMQ sockets. This enables distributing components across multiple machines for
security segmentation, load distribution, or horizontal scaling. See
[Clustered Deployment](clustered-deployment.md) for when and how to use this mode.

## Understanding mooR's Architecture

Before diving into installation, it helps to understand how mooR is structured. mooR is built from
modular components that can run as one process or as separate processes.

👉 **[Server Architecture](server-architecture.md)** - Learn about mooR's components and how they
work together

## Installation Methods

mooR provides several ways to get up and running, each suited for different needs and environments:

### Docker Compose (Recommended)

The easiest and most reliable method for most users. The default Docker Compose configuration runs
the single-process `moor` binary with the Meadow frontend, making it simple to get a complete MOO
environment running.

👉 **[Docker Compose Setup](docker-compose-setup.md)** - Complete guide to running mooR with Docker

### Alternative Methods

For specific environments or use cases, mooR also supports traditional installation approaches,
including Debian packages (single-process or split-service) and building from source.

👉 **[Alternative Installation Methods](alternative-installation-methods.md)** - Debian packages and
building from source

## Next Steps

Once you have mooR running, you'll need to:

1. **Choose and install a MOO core** - See [Understanding MOO Cores](understanding-moo-cores.md)
2. **Configure your server** - See [Server Configuration](server-configuration.md)
3. **Set up player access** - Configure telnet and/or web interfaces
4. **Customize your MOO** - Add content, modify settings, and create your virtual world

## Getting Help

If you run into issues:

- Check the specific installation guide for your chosen method
- Review the server configuration documentation
- Consult the mooR Codeberg repository for troubleshooting tips
- Ask the community for help in the forums or Discord
