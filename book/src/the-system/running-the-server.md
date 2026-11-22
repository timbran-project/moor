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
   - For Snore, a classic MOO core: `./scripts/start-moor-snore.sh`
3. Connect to your MOO via http://localhost:8080/ -- or `telnet` (or your favourite MUD client) to
   port 8888

On the first start, the script imports the selected core's human-readable objdef source into a new
persistent database. Later starts use that database directly. See
[Starting a MOO from Objdef Source](bootstrapping-from-source.md) for how this process works and
what happens when you edit the source files.

For detailed instructions and other installation options, see the sections below.

## Single-Process vs Clustered Deployment

mooR can run in two modes:

**Single-process (default)** runs the combined `moor` binary, which bundles the daemon, telnet host,
web host, and curl worker into one process. This is the simplest path, and it is what the quick
start, the single-process Docker Compose configurations and the cloud machine setup all use. Most
people should start here.

**Clustered deployment (advanced)** runs the daemon, hosts, and workers as separate processes that
communicate over ZeroMQ sockets. This enables distributing components across multiple machines for
security segmentation, load distribution, or horizontal scaling. See
[Clustered Deployment](clustered-deployment.md) for when and how to use this mode.

## Understanding mooR's Architecture

Before diving into installation, it helps to understand how mooR is structured. mooR is built from
modular components that can run as one process or as separate processes.

👉 **[Server Architecture](server-architecture.md)** - Learn about mooR's components and how they
work together

## Ways to Install

Pick the row that matches what you are doing.

| You want to...                                 | Use                                                                              |
| ---------------------------------------------- | -------------------------------------------------------------------------------- |
| Try mooR on your own computer                  | The [quick start](#quick-start-guide) above                                      |
| Run a server with Docker                       | [Docker Compose Setup](docker-compose-setup.md)                                  |
| Start a server on a rented cloud machine       | [Starting on a Cloud Machine](cloud-machine.md)                                  |
| Run without containers, and without compiling  | [Prebuilt binaries](alternative-installation-methods.md#prebuilt-binaries)       |
| Install as system services on Debian or Ubuntu | [Debian packages](alternative-installation-methods.md#debian-packages)           |
| Build it yourself, or work on mooR             | [Building from source](alternative-installation-methods.md#building-from-source) |
| Spread the server across several machines      | [Clustered Deployment](clustered-deployment.md)                                  |

All of them end with the same server. They differ in how much is set up for you.

### What a Release Includes

Each mooR release publishes three things, built and checked by the project:

- **Container images**, for x86-64 and arm64. The Docker Compose configurations use these.
- **Prebuilt binaries**, as a tarball for each of the two processor types.
- **A cloud-init file**, which sets up a new cloud machine on its first boot.

Everything else in the repository's `deploy/` directory is an example to adapt: the Docker Compose
configurations, the nginx configurations, the Kubernetes manifests and the Debian packaging. They
are tested and kept working, but your deployment will differ from them, and you are expected to
change them to fit.

## Next Steps

Once you have mooR running, you'll need to:

1. **Change the wizard's password** - The wizard account can do anything in the world, and a new
   world's wizard has a password everybody knows: none at all in Snore and LambdaCore, and `test`
   for Cowbell's `archwizard`. Change it with `@password` before anyone else can reach the server.
   [Docker Compose Setup](docker-compose-setup.md#before-you-open-it-to-anyone) has the steps.
2. **Understand the selected MOO core** - See [Understanding MOO Cores](understanding-moo-cores.md)
3. **Configure your server** - See [Server Configuration](server-configuration.md)
4. **Set up player access** - Configure telnet and/or web interfaces
5. **Customize your MOO** - Add content, modify settings, and create your virtual world

## Getting Help

If you run into issues:

- Check the specific installation guide for your chosen method
- Review the server configuration documentation
- Consult the [mooR GitHub repository](https://github.com/timbran-project/moor) for troubleshooting
  tips
- Ask the community for help in the forums or Discord
