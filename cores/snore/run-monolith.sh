#!/usr/bin/env bash
# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
# software: you can redistribute it and/or modify it under the terms of the GNU
# Affero General Public License as published by the Free Software Foundation,
# version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: run-monolith.sh [--help]

Run Snore Core in the single-process mooR server with telnet.
The first startup imports src/; later startups resume the saved database.
Stop with Ctrl-C. State is preserved.

Environment:
  MOOR_RUN_DIR         State directory (default: cores/snore/gen.monolith)
  MOOR_TELNET_ADDRESS  Bind address (default: 127.0.0.1)
  MOOR_TELNET_PORT     Telnet port (default: 8888)
  MOOR_PROFILE         Cargo build profile (default: dev; use release for optimization)
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi
if (($#)); then
    usage >&2
    exit 2
fi

core_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$core_dir/../.." && pwd)"
run_dir="${MOOR_RUN_DIR:-$core_dir/gen.monolith}"
telnet_address="${MOOR_TELNET_ADDRESS:-127.0.0.1}"
telnet_port="${MOOR_TELNET_PORT:-8888}"

umask 077
mkdir -p -- "$run_dir"
run_dir="$(cd -- "$run_dir" && pwd)"
mkdir -p -- "$run_dir/config" "$run_dir/data" "$run_dir/export"
export XDG_CONFIG_HOME="$run_dir/config"
export XDG_DATA_HOME="$run_dir/data"

# Match the core Makefile's FEATURES and keep the health listener on a free port.
cat > "$run_dir/config/moor.yaml" <<'YAML'
features:
  bool_type: true
  use_boolean_returns: true
  symbol_type: true
  use_symbols_in_builtins: true
  custom_errors: true
  use_uuobjids: true
  lexical_scopes: true
  list_comprehensions: true
  anonymous_objects: false
  flyweight_type: false
  rich_notify: false
services:
  telnet:
    enabled: true
    health_check_port: 0
  web:
    enabled: false
  curl_worker:
    enabled: false
YAML

printf 'State: %s\nTelnet: %s:%s\nStop with Ctrl-C; restarting preserves your world.\n' \
    "$run_dir" "$telnet_address" "$telnet_port"

cd -- "$repo_root"
exec cargo run --profile "${MOOR_PROFILE:-dev}" -p moor-server --bin moor -- \
    "$run_dir/data" \
    --config-file "$run_dir/config/moor.yaml" \
    --db world.db \
    --import "$core_dir/src" \
    --import-format objdef \
    --export "$run_dir/export" \
    --generate-keypair \
    --no-web \
    --telnet-address "$telnet_address" \
    --telnet-port "$telnet_port"
