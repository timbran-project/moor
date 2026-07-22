# Client Applications

The mooR monorepo contains browser, desktop, and mobile-oriented clients alongside shared protocol
libraries. The default container image includes the React Meadow web assets. Debian packages for the
web client can be built from the monorepo, but a matching Meadow package was not published in the
final 1.0.2 release.

## Client Projects

- **Meadow** (`clients/meadow/`) is the React web client and optional Tauri desktop application. It
  is the client served by the provided Docker Compose configurations.
- **Meadow Flutter** (`clients/meadow_flutter/`) is an alternative Flutter client for web and Linux
  desktop targets. Mobile targets are present but do not yet have release packaging.
- **Web SDK** (`clients/web-sdk/`) contains shared TypeScript protocol and API support for
  web-facing clients.
- **Schema package** (`crates/schema/schema/`) generates the TypeScript FlatBuffers bindings used by
  the SDK and React Meadow.
- **Web MCP client** (`clients/moor-web-mcp/`) provides an MCP stdio server backed by the mooR web
  API.

Client release versions and tags are independent from the server release line. Use client and server
versions built from compatible branches. The remainder of this section primarily documents the React
Meadow client and the common web-host protocol.

## What It Is

The web client is a rich React application that connects to `moor-web-host` over HTTPS and
WebSockets. It provides a modern MOO experience with:

- **Persistent History**: Encrypted event logs that follow you across sessions and devices
- **Rich Content Rendering**: Support for plain text, Djot markup, and sanitized HTML
- **Server-Driven UI**: Panels and dialogs that can be opened and controlled from MOO code
- **Integrated Building Tools**: Object browser, verb editor, property editor, and eval panel
- **Accessibility**: Screen reader support with TTS text alternatives

The web client is _optional_. mooR still supports classical telnet/MUD clients, and the web client
exists to demonstrate what is possible with richer protocols and UI surfaces, and to support the
capabilities of the `cowbell` core and the mooR author's own projects.

## Quick Tour

When you connect with the web client, you'll see:

- **Main Narrative Area**: Where output from the world appears, with support for grouped messages,
  collapsible "look" output, and inline links
- **Command Input**: A text field at the bottom for entering commands, with command history (up/down
  arrows)
- **Verb Palette**: An optional toolbar of quick-tap buttons for common verbs like "look",
  "inventory", "say"
- **Top Navigation**: Account menu, settings, and (for programmers) the object browser

### Settings

Open settings via the gear icon to customize:

| Setting            | Description                                        |
| ------------------ | -------------------------------------------------- |
| **Theme**          | Light or dark mode                                 |
| **Font**           | Serif, sans-serif, or monospace for narrative text |
| **Font Size**      | Increase or decrease narrative text size           |
| **Command Echo**   | Show your typed commands in the output             |
| **Speech Bubbles** | Visual treatment for "say" messages                |
| **Say Mode**       | Shortcut for quick chat input                      |
| **Verb Palette**   | Show/hide the quick-tap verb buttons               |

### Rich Input Prompts

MOO code can request structured input from players. When a rich input prompt is active, the client
displays context-appropriate controls:

| Input Type           | Appearance                                    |
| -------------------- | --------------------------------------------- |
| `text`               | Simple text field                             |
| `text_area`          | Multi-line textarea with Ctrl+Enter to submit |
| `number`             | Number input with optional min/max            |
| `choice`             | Buttons (4 or fewer choices) or dropdown      |
| `yes_no`             | Yes and No buttons                            |
| `yes_no_alternative` | Yes, No, and Alternative... buttons           |
| `confirmation`       | Single OK button                              |
| `image` / `file`     | File picker with preview                      |

See [Client Output and Presentations](./client-output-and-presentations.md) for how to trigger these
from MOO code.

## How It Is Served

In production deployments, the static web client assets are served by nginx (or another reverse
proxy), which also proxies API requests to `moor-web-host`. In development, Vite serves the web
client directly with hot module replacement.

See [Deployment](./deployment.md) for proxy configuration examples.

## Communication Model

The web client integrates tightly with the `moor-web-host` API:

- **REST endpoints** for authentication, session management, and data operations
- **WebSockets** for real-time narrative events and command input
- **FlatBuffers** encoding for efficient, schema-evolving payloads

The default container image includes the React Meadow assets. A locally built `moor-web-client`
Debian package installs the same static assets; the published `1.0.2` Debian channel does not
include a matching package.

## Web Client Topics

- [Deployment](./deployment.md) - Proxy setup and production configuration
- [OAuth2 Authentication](./oauth2-authentication.md) - External identity providers
- [Authoring and Programming Tools](./authoring-tools.md) - Object browser, verb editor, eval panel
- [Client Output and Presentations](./client-output-and-presentations.md) - Rich content and
  server-driven UI
- [Accessibility](./accessibility.md) - Screen reader support and TTS
- [Presentations](./presentations.md) - Presentation targets and attributes

## Related Documentation

- [Server Architecture](../the-system/server-architecture.md)
- [Event Logging](../the-system/event-logging.md)
- [Networking](../the-moo-programming-language/networking.md)
- [Server Builtins](../the-moo-programming-language/built-in-functions/server.md)
