# mooR prebuilt binaries

These are the mooR server programs, built for 64-bit Linux. They are the same files that the
official container image holds, taken from it when the release was published.

They are for running mooR without containers and without building it from source. Nothing here
installs a service, creates a user or sets up a data directory: that part is yours.

## What is here

- `moor`: the whole server in one process. Start with this one.
- `moor-daemon`, `moor-telnet-host`, `moor-web-host`: the same server as separate processes, for
  deployments that split them up.
- `moor-curl-worker`, `moor-file-worker`, `moor-git-worker`: workers that let MOO code make HTTP
  requests, read and write files, and use Git.
- `moorc`: the compiler. It builds and exports databases and runs tests.
- `moor-emh`: a tool for repairing a database when the server cannot start it.
- `web-client/`: the files of the web client, to serve with a web server of your choice.
- `LICENSE`: the GNU Affero General Public License, version 3.

There is no world here. A new server needs a core to start from, such as Cowbell or Snore, both of
which are in the mooR source repository under `cores/`.

## What you need

- 64-bit Linux, on the processor type named in the file you downloaded (`x86_64` or `aarch64`).
- glibc 2.35 or newer, and the C++ runtime that comes with GCC 12 or newer. Debian 12 and Ubuntu
  22.04 have both, as do later releases of each. RHEL 9 and its rebuilds do not.
- `git`, if you use the Git worker.

## Checking what you downloaded

Each tarball comes with a `.sha256` file:

```sh
sha256sum -c moor-*.tar.gz.sha256
```

Each also has a build attestation, which shows that the project's release workflow made it. With a
recent version of the GitHub command-line tool:

```sh
gh attestation verify moor-*.tar.gz --repo timbran-project/moor
```

## Running it

The book explains how to start a server and what its options mean:

- Running the server: <https://timbran.org/book/html/the-system/running-the-server.html>
- Other ways to install:
  <https://timbran.org/book/html/the-system/alternative-installation-methods.html>

Every program prints its options with `--help`.

## Debugging information

The debugging information has been removed to keep the download small. Function names are kept, so a
crash report still shows where it happened.
