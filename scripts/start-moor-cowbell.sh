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

# Start mooR with the Cowbell core
set -e

# Configuration
export RUN_DIR="run-cowbell"
export IMPORT_PATH="/db/cores/cowbell/src"
export BUILD_PROFILE="release-fast"
COMPOSE_ARGS=()
POSTGRES=false
COMPOSE=(docker compose)

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug) export BUILD_PROFILE="debug"; shift ;;
        --release) export BUILD_PROFILE="release-fast"; shift ;;
        --postgres) POSTGRES=true; shift ;;
        --help|-h)
            echo "Usage: $0 [--debug|--release] [--postgres] [docker compose up options]"
            echo "  --postgres  Run a local PostgreSQL world in a persistent Docker volume."
            echo "              Uses run-cowbell-postgres for keys and ancillary databases."
            exit 0 ;;
        *) COMPOSE_ARGS+=("$1"); shift ;;
    esac
done

if [[ "$POSTGRES" == true ]]; then
    export RUN_DIR="run-cowbell-postgres"
    COMPOSE+=(-f docker-compose.yml -f docker-compose.cowbell-postgres.yml)
fi

# Check for root-owned directory
if [ -d "$RUN_DIR" ] && [ "$(stat -c '%u' "$RUN_DIR" 2>/dev/null)" == "0" ]; then
    echo "Error: $RUN_DIR is owned by root. Run: sudo chown -R $(id -u):$(id -g) $RUN_DIR"
    exit 1
fi

echo "Starting mooR with Cowbell core..."
echo "Build profile: $BUILD_PROFILE"
echo "Runtime directory: $RUN_DIR"

# Ensure runtime directories exist
mkdir -p "$RUN_DIR/config" "$RUN_DIR/moor-data" "$RUN_DIR/export" "$RUN_DIR/local-share"

# Install the root npm workspace when needed.
if [ ! -d "node_modules" ]; then
    echo "Installing web workspace dependencies..."
    npm ci
fi

export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
# Rootless Docker maps container root to the host user, so bind-mounted files are
# only writable, and stay owned by the invoking user, when the container runs as root.
if docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q 'name=rootless'; then
    export USER_ID=0
    export GROUP_ID=0
fi
if [[ "$POSTGRES" == true ]]; then
    export MOOR_CONFIG_FILE="${MOOR_CONFIG_FILE:-moor-dev-postgres.yaml}"
    "${COMPOSE[@]}" up -d --wait postgres
    schema_exists=$("${COMPOSE[@]}" exec -T postgres psql -U moor -d moor -At \
        -v ON_ERROR_STOP=1 -c "SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cowbell'")
    if [[ "$schema_exists" != 1 ]]; then
        echo "Initializing PostgreSQL world schema..."
        "${COMPOSE[@]}" build moor
        "${COMPOSE[@]}" run --rm --no-deps moor /moor/moor \
            --config-file="/db/$MOOR_CONFIG_FILE" \
            --storage-backend=postgres --pg-service=cowbell --pg-schema=cowbell \
            --pg-socket-dir=/var/run/postgresql --init-storage
    fi
    echo "World storage: PostgreSQL (schema cowbell; checkpoint export disabled)"
else
    export MOOR_CONFIG_FILE="${MOOR_CONFIG_FILE:-moor-dev.yaml}"
fi

"${COMPOSE[@]}" up --build "${COMPOSE_ARGS[@]}"
