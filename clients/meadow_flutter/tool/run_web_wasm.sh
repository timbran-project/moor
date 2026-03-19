#!/usr/bin/env bash
# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

# Builds the Flutter web app with WASM (skwasm) and serves it behind the same
# Vite reverse proxy used by run_web.sh, so the API is same-origin.

set -euo pipefail
cd "$(dirname "$0")/.."

proxy_port="${VITE_PROXY_PORT:-3001}"
serve_port="${SERVE_PORT:-9010}"

export MOOR_API_URL="${MOOR_API_URL:-http://localhost:8080}"
export MOOR_WS_URL="${MOOR_WS_URL:-ws://localhost:8080}"
export FLUTTER_WEB_TARGET="http://localhost:${serve_port}"

mode="release"
if [[ "${1:-}" == "--profile" ]]; then
    mode="profile"
    shift
fi

vite_bin="../meadow/node_modules/vite/bin/vite.js"
if [[ ! -f "${vite_bin}" ]]; then
    echo "Missing ${vite_bin}. Install deps in ../meadow first (npm install)."
    exit 1
fi

echo "Building Flutter web (WASM, ${mode})..."
flutter build web --wasm "--${mode}"

echo "Serving build/web/ on :${serve_port}..."
cleanup() {
    if [[ -n "${serve_pid:-}" ]]; then
        kill "${serve_pid}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

python3 -m http.server "${serve_port}" --directory build/web --bind 127.0.0.1 >/dev/null 2>&1 &
serve_pid="$!"

echo "Starting Vite reverse proxy on :${proxy_port}..."
echo "Open: http://localhost:${proxy_port}"
node "${vite_bin}" --config tool/vite_flutter_proxy.config.mjs --port "${proxy_port}" --host 0.0.0.0
