# Client Applications

This directory contains the client applications and shared web libraries maintained in the mooR
monorepo.

## Meadow Web Client

[Meadow](./meadow/) is the React web and Tauri client for mooR. Its release version and `meadow-v*`
tags remain independent from the server release line.

## Meadow Flutter

[Meadow Flutter](./meadow_flutter/) is the Flutter client for web, desktop, and mobile targets. Its
release version and `meadow-flutter-v*` tags are also independent.

## Development

Install the root npm workspace and build the TypeScript schema, SDK, and React client from the
repository root:

```bash
npm ci
npm run web:build
```

Run the React development server with the mooR backend:

```bash
npm run full:dev
```

Flutter commands and platform prerequisites are documented in
[`clients/meadow_flutter/README.md`](./meadow_flutter/README.md).
