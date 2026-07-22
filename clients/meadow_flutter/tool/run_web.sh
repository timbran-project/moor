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

set -euo pipefail
cd "$(dirname "$0")/.."

flutter_port="${FLUTTER_WEB_PORT:-9010}"
proxy_port="${VITE_PROXY_PORT:-3001}"

flutter_hostname="${FLUTTER_WEB_HOSTNAME:-}"
if [[ -z "${flutter_hostname}" ]]; then
  # Pick a LAN-reachable IP so DWDS doesn't advertise ws://localhost:... to
  # browsers connecting via http://<lan-ip>:<vite-port>/.
  if command -v ip >/dev/null 2>&1; then
    flutter_hostname="$(
      ip route get 1.1.1.1 2>/dev/null | awk '
        { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }
      '
    )"
  fi
fi
if [[ -z "${flutter_hostname}" ]]; then
  # Fallback for environments without `ip` (or where routing lookup fails).
  flutter_hostname="$(
    hostname -I 2>/dev/null | awk '
      { for (i = 1; i <= NF; i++) if ($i !~ /^127\\./ && $i !~ /:/) { print $i; exit } }
    '
  )"
fi
flutter_hostname="${flutter_hostname:-localhost}"

export MOOR_API_URL="${MOOR_API_URL:-http://localhost:8080}"
export MOOR_WS_URL="${MOOR_WS_URL:-ws://localhost:8080}"
export FLUTTER_WEB_TARGET="${FLUTTER_WEB_TARGET:-http://${flutter_hostname}:${flutter_port}}"

vite_bin="../../node_modules/vite/bin/vite.js"
if [[ ! -f "${vite_bin}" ]]; then
  echo "Missing ${vite_bin}. Run npm ci from the mooR repository root."
  exit 1
fi

cleanup() {
  if [[ -n "${flutter_pgid:-}" ]]; then
    # Kill the entire Flutter process group so child dart/frontend-server
    # processes do not survive script exit.
    kill -- -"${flutter_pgid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${flutter_pid:-}" ]]; then
    kill "${flutter_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting Flutter web-server on :${flutter_port}..."
flutter run -d web-server --web-port "${flutter_port}" --web-hostname "${flutter_hostname}" >/tmp/meadow_flutter_web.log 2>&1 &
flutter_pid="$!"
flutter_pgid="$(
  ps -o pgid= "${flutter_pid}" 2>/dev/null | tr -d ' ' || true
)"

echo "Waiting for Flutter web-server to become ready..."
deadline=$((SECONDS + 60))
probe_hosts=("${flutter_hostname}" "localhost" "127.0.0.1")
while true; do
  if ! kill -0 "${flutter_pid}" >/dev/null 2>&1; then
    echo "Flutter web-server process exited while starting. Recent log:"
    tail -n 80 /tmp/meadow_flutter_web.log || true
    exit 1
  fi

  if [[ "${SECONDS}" -ge "${deadline}" ]]; then
    echo "Flutter web-server did not become ready within 60s. Recent log:"
    tail -n 80 /tmp/meadow_flutter_web.log || true
    exit 1
  fi

  if command -v curl >/dev/null 2>&1; then
    if rg -q "is being served at http://" /tmp/meadow_flutter_web.log; then
      break
    fi
    for h in "${probe_hosts[@]}"; do
      base="http://${h}:${flutter_port}"
      if curl -fsS "${base}/" 2>/dev/null | rg -q "flutter_bootstrap\\.js"; then
        break 2
      fi
    done
  else
    # Fallback: just sleep if curl isn't available.
    sleep 1
  fi
  sleep 0.25
done

echo "Starting Vite reverse proxy on :${proxy_port} (same-origin API proxy; avoids CORS)..."
echo "Open (local): http://localhost:${proxy_port}"
if [[ "${flutter_hostname}" != "localhost" ]]; then
  echo "Open (LAN):   http://${flutter_hostname}:${proxy_port}"
fi
node "${vite_bin}" --config tool/vite_flutter_proxy.config.mjs --port "${proxy_port}" --host 0.0.0.0
