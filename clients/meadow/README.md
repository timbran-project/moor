# Meadow

A rich and beautiful web & mobile client for interacting with mooR worlds.

<p align="center"><img src="./doc/timbran-lobby.png" alt="The Timbran Hotel Lobby" width="600"/></p>

## Overview

Meadow provides a modern interface for [mooR](https://github.com/timbran-project/moor) servers,
communicating with the backend through WebSocket connections and RESTful API calls handled by the
`moor-web-host` binary. It is the default client for the
[Cowbell](https://github.com/timbran-project/moor/tree/main/cores/cowbell) core.

Meadow can run as a web application served alongside a mooR backend, or as a standalone desktop
application built with [Tauri](https://v2.tauri.app/) that connects to any remote mooR server.

## Version Lines

Meadow and `moor` currently have two active version lines:

- `v1.0-release`: the stable 1.0 line
- `main`: the post-1.0 development line

Use matching branches across the stack. A Meadow checkout on `v1.0-release` should be used with the
`v1.0-release` line of `moor` and the corresponding `1.0.0-rc1-dev...` published packages. A Meadow
checkout on `main` should be used with `moor` `main` and the corresponding `1.1.0-dev...` published
packages.

`main` in the `moor` repository tracks post-1.0 development. If you want the stable 1.0 setup, use
the `v1.0-release` line rather than `main`.

## Features

### Rich Presentation

- **Multimedia Content:** Renders a rich HTML subset and **Djot** (a modern, faster Markdown-like
  format) for complex styling, tables, and integrated media.
- **Terminal Heritage:** Full support for **ANSI colors** and styles inline in content.
- **Image presentation:** Inline image thumbnails in object descriptions.
- **Interactive Narrative:** Inline links for executing commands directly from the text and
  automatic
- **URL previews**. Slack/Discord-style embeds for links to external sites, with thumbnails.
- **Infinite History:** Seamless "infinite" backscroll through mooR's **encrypted and secure event
  log**, allowing you to retrieve your entire character history.

... and more coming.

### User Experience

- **Identity Management:** Integrated profile picture uploader and built-in player description
  editor.
- **Personalization:** Multiple themes (dark, light, and more) to suit your aesthetic.
- **Dynamic Command Entry:** A "verb palette" that provides real-time suggestions and
  autocompletions as you type, alongside a full, searchable command history.

### Developer Tools (MOO IDE)

Meadow is not just a user facing client; it's a development environment for MOO programmers, for
authoring persistent worlds and building objects in the MOO using modern development tools:

- **Object Browser:** A Smalltalk-style browser for navigating the list of objects, their verbs, and
  their properties.
  - Can create new objects and edit existing ones, add new verbs and properties, and edit them using
    the GUI without using the MOO command line.

<p align="center"><img src="./doc/browser.png" alt="The Meadow Object Browser" width="600"/></p>

- **Monaco-powered Editor:** The same core editor that powers **VS Code**, featuring:
  - Syntax highlighting for MOO code.
  - Dynamic autocompletion based on the live world state.
  - Integrated compiler feedback and error reporting.
  - Verb editor highlights compile errors.

<p align="center"><img src="./doc/verb-editor.png" alt="The Meadow Verb Editor" width="600"/></p>

## Project Structure

Meadow is a React application built with Vite and TypeScript, with an optional
[Tauri 2.0](https://v2.tauri.app/) shell for desktop packaging. It relies on the `@moor/schema` NPM
package for FlatBuffer bindings, which are shared with the mooR backend.

```
├── src/                  # React frontend (TypeScript)
├── src-tauri/            # Tauri desktop shell (Rust)
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── src/
│   ├── capabilities/
│   └── icons/
├── public/               # Static assets (WASM, etc.)
├── deploy/               # Debian packaging scripts
└── vite.config.ts
```

## Development

Run these commands from the mooR repository root so npm resolves the local schema and SDK
workspaces:

```bash
# Install dependencies
npm ci

# Start development server (defaults to http://localhost:3000)
npm run meadow:dev

# Start the full stack with the single-process moor server
npm run full:dev

# Build for production
npm run meadow:build

# Type checking
npm run typecheck --workspace meadow

# Linting
npm run lint --workspace meadow
```

### Environment Variables

- `MOOR_PATH`: Path to the mooR repository root (defaults to `../..`).
- `MOOR_API_URL`: URL of the mooR web API (defaults to `http://localhost:8080`).
- `MOOR_WS_URL`: URL of the WebSocket endpoint (defaults to `ws://localhost:8080`).

## FlatBuffer Schemas

Within the monorepo, Meadow uses the local `@moor/schema` and `@moor/web-sdk` workspaces. Published
packages remain available for external consumers, which must use versions compatible with their
server release.

Do not use `latest` blindly across the branch split.

```bash
npm install @moor/schema@1.0.0-rc1-dev...
```

## Running Stable 1.0

To run the stable 1.0 line, use:

- `moor` on `v1.0-release`
- Meadow on `v1.0-release`
- `@moor/schema` and `@moor/web-sdk` from the `1.0.0-rc1-dev...` package line

If you use `main` checkouts or `1.1.0-dev...` packages, you are on the post-1.0 development line
instead.

## Desktop App (Tauri)

Meadow can be built as a native desktop application using Tauri. This wraps the web frontend in a
lightweight WebKit-based window and allows connecting to any remote mooR server.

### Prerequisites

In addition to Node.js, building the desktop app requires:

- **Rust** (1.70+): Install via [rustup](https://rustup.rs/)
- **Linux system libraries:**
  ```bash
  sudo apt-get install -y \
    libglib2.0-dev \
    libwebkit2gtk-4.1-dev \
    libjavascriptcoregtk-4.1-dev \
    libsoup-3.0-dev \
    libgtk-3-dev
  ```

### Building

```bash
# Development mode (opens app with hot-reload)
npm run tauri:dev

# Production build
npm run tauri:build
```

The release binary is output to `src-tauri/target/release/meadow`.

### Usage

```bash
# Connect to a remote mooR server
./meadow --server https://moo.example.com

# Short flag form
./meadow -s https://moo.example.com
```

Without `--server`, the app attempts to connect to the same origin (useful during development with
the Vite proxy).

## Web Deployment

Meadow can also be deployed as a web application via Docker:

```bash
docker build -t meadow .
docker run -p 80:80 meadow
```

For more details on the overall mooR system, see the [mooR Book](https://timbran.org/book/html/).
