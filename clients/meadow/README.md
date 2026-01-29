# Meadow

A rich and beautiful web & mobile client for interacting with mooR worlds.

<p align="center"><img src="./doc/timbran-lobby.png" alt="The Timbran Hotel Lobby" width="600"/></p>

## Overview

Meadow provides a modern browser interface for [mooR](https://codeberg.org/timbran/moor) servers,
communicating with the backend through WebSocket connections and RESTful API calls handled by the
`moor-web-host` binary. It is the default client for the
[Cowbell](https://codeberg.org/timbran/cowbell) core.

## Project Structure

Meadow is a standalone React application built with Vite and TypeScript. It relies on the
`@moor/schema` NPM package for FlatBuffer bindings, which are shared with the mooR backend.

## Development

Meadow is designed to be developed alongside the `moor` backend.

```bash
# Install dependencies
npm install

# Start development server (defaults to http://localhost:3000)
npm run dev

# Start the full stack (requires 'moor' to be in a sibling directory)
npm run full:dev

# Build for production
npm run build

# Type checking
npm run typecheck

# Linting
npm run lint
```

### Environment Variables

- `MOOR_PATH`: Path to the mooR backend repository (defaults to `../moor`).
- `MOOR_API_URL`: URL of the `moor-web-host` API (defaults to `http://localhost:8080`).
- `MOOR_WS_URL`: URL of the WebSocket endpoint (defaults to `ws://localhost:8080`).

## FlatBuffer Schemas

This project uses `@moor/schema` for communication. If you modify schemas in the `moor` repository,
they will be automatically published to the Codeberg registry. To update Meadow to the latest
schema:

```bash
npm install @moor/schema@latest
```

## Deployment

Meadow can be deployed as a Docker container:

```bash
docker build -t meadow .
docker run -p 80:80 meadow
```

For more details on the overall mooR system, see the [mooR Book](https://timbran.org/book/html/).
