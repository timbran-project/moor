# meadow_flutter

Flutter client for [mooR](../../README.md), replacing the React/Vite `meadow` SPA.

Goals over the original web client:

- Shared codebase across web, desktop, and (eventually) mobile
- Connection management fully under our control (WebSocket with reconnect, keepalive)
- Cleaner code structure without React
- Better look and feel (Material 3, light/dark themes)
- Better A11Y/TTS (partially realized — still needs work)

## Platforms

- **Web** — Flutter web, served behind a Vite reverse proxy for same-origin API access
- **Linux desktop** — GTK via Flutter Linux
- iOS and Android are structurally possible but there are no build/packaging scripts yet, and the
  UX will need significant testing and adaptation for mobile form factors

## Features

Supports most of what the original SPA client does:

- Command input with history and auto-completion
- Verb palette
- Djot, HTML, and plain-text rendering (plus ANSI escape codes and tracebacks)
- Room HUD with command and inspect links
- Object browser with verb and property editors (syntax-highlighted MOO code via `re_editor`)
- Account settings: profile picture, pronouns, description
- Light and dark Material 3 themes
- Input prompt composer (for in-game prompts to the player)
- Editor dock for concurrent verb/property editing sessions
- OAuth2 PKCE authentication
- Encrypted event log support (Argon2id KDF, X25519, AGE encryption)
- Link previews, history export

### Known gaps

- Verb editor lacks autocompletion, suggestion, and syntax template features
- Encrypted event log retrieval of existing web logs is broken
- Event log does not support infinite backscroll
- TTS still needs work

## Run

### Linux desktop

```bash
cd clients/meadow_flutter
./tool/run_linux.sh --server=http://localhost:8080 --username=archwizard --password=potrzebie --login
```

The helper script wraps `flutter run -d linux` and translates positional args into
`-a`/`--dart-entrypoint-args` flags. Pass `--profile` or `--release` before the entrypoint args
to change the build mode.

Without the helper:

```bash
flutter run -d linux \
  -a --server=http://localhost:8080 \
  -a --username=archwizard \
  -a --password=test \
  -a --login
```

### Web

```bash
cd clients/meadow_flutter
./tool/run_web.sh
```

This starts a Flutter web-server (default port 9010) and a Vite reverse proxy (default port 3001)
that forwards API/WebSocket requests to the mooR daemon, avoiding CORS issues. Open
`http://localhost:3001` in a browser.

Requires `node_modules` installed in the sibling `../meadow/` directory (for Vite).

Environment variables:

| Variable              | Default                    | Purpose                              |
|-----------------------|----------------------------|--------------------------------------|
| `MOOR_API_URL`        | `http://localhost:8080`    | mooR HTTP API base                   |
| `MOOR_WS_URL`         | `ws://localhost:8080`      | mooR WebSocket base                  |
| `FLUTTER_WEB_PORT`    | `9010`                     | Flutter dev server port              |
| `VITE_PROXY_PORT`     | `3001`                     | Vite proxy port (what you open)      |
| `FLUTTER_WEB_HOSTNAME`| LAN IP (auto-detected)     | Hostname Flutter binds to            |

### Launch arguments

Accepted by both desktop and web (via `--dart-define` for web):

| Argument                  | Description                                  |
|---------------------------|----------------------------------------------|
| `--server=URL`            | mooR server base URL                         |
| `--username=USER`         | Pre-fill username                            |
| `--password=PASS`         | Pre-fill password                            |
| `--mode=connect\|create`  | Login vs. account creation                   |
| `--login`                 | Trigger login immediately on startup         |

## Deploy (web)

```bash
./tool/deploy_timbran_web.sh
```

Builds in release mode and copies the output to `~/timbran-site/public/meadow/`. See
`./tool/deploy_timbran_web.sh --help` for options (`--subpath`, `--api-base`,
`--skip-site-build`, etc.).

## Development

### Check (format + lint + test)

```bash
./tool/check.sh        # runs fmt.sh, lint.sh, test.sh in sequence
./tool/fmt.sh          # dart format .
./tool/lint.sh         # flutter analyze
./tool/test.sh         # flutter test
```

## Project layout

```
lib/
  main.dart                 App entry point, theme, top-level wiring
  fbs/                      Generated FlatBuffers Dart code
  moor/                     Core logic: models, controllers, API, crypto
    types/                  Extension types for mooR values
    djot/                   Djot markup → Flutter widget rendering
  theme/                    Material 3 light/dark theme definitions
  widgets/                  UI components (narrative list, editors, sheets, etc.)
test/                       Unit and widget tests
tool/                       Shell scripts for running, building, linting, deploying
web/                        Web platform assets (index.html, Argon2 WASM vendor)
linux/                      Linux GTK platform shell
fonts/                      Bundled fonts (Comic Mono, Glass TTY VT220)
third_party/flat_buffers/   Vendored FlatBuffers Dart package
```
