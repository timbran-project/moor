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

DURATION=${DURATION:-10}
INTERVAL=${INTERVAL:-5}
OUT_DIR=${OUT_DIR:-"${PWD}"}
MOOR_PERF_IMAGE=${MOOR_PERF_IMAGE:-moor-perf-tools:local}
MODE=
TARGET_CONTAINER=
BUILD_IMAGE=false
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd)
source "${SCRIPT_DIR}/container-target.sh"

usage() {
    cat <<'EOF'
Usage: tools/perf/run-containerized-moor-perf.sh [OPTIONS] MODE CONTAINER

Run a mooR performance tool in a diagnostic container. The target server stays
in its existing container.

Modes:
  snapshot    Record mooR task, verb, and database probes
  profile     Record sampled stacks with perf
  top         Show live five-second probe deltas

Options:
  -b, --build Build or rebuild the diagnostic image
  -d, --duration SECONDS
              Snapshot or profile duration (default: 10)
  -i, --interval SECONDS
              Top refresh interval (default: 5)
  -o, --output DIRECTORY
              Archive directory (default: current directory)
  -h, --help  Show this help text

Environment:
  DURATION        Default recording duration in seconds
  INTERVAL        Default top refresh interval in seconds
  OUT_DIR         Default archive directory
  MOOR_PERF_IMAGE Diagnostic image name (default: moor-perf-tools:local)
  FREQUENCY       Sampling frequency in hertz
  BPFTRACE_MAX_MAP_KEYS
                  Maximum entries in each BPF map
  BPFTRACE_MAX_STRLEN
                  Maximum captured verb name length
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        snapshot|profile|top)
            [[ -z "${MODE}" ]] || fail "only one mode may be specified"
            MODE=$1
            shift
            ;;
        -b|--build)
            BUILD_IMAGE=true
            shift
            ;;
        -d|--duration)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            DURATION=$2
            shift 2
            ;;
        --duration=*)
            DURATION=${1#*=}
            shift
            ;;
        -i|--interval)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            INTERVAL=$2
            shift 2
            ;;
        --interval=*)
            INTERVAL=${1#*=}
            shift
            ;;
        -o|--output)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            OUT_DIR=$2
            shift 2
            ;;
        --output=*)
            OUT_DIR=${1#*=}
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage >&2
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "${TARGET_CONTAINER}" ]] || fail "only one container may be specified"
            TARGET_CONTAINER=$1
            shift
            ;;
    esac
done

[[ -n "${MODE}" ]] || fail "snapshot, profile, or top mode is required"
[[ -n "${TARGET_CONTAINER}" ]] || fail "Docker container is required"
[[ "${DURATION}" =~ ^[1-9][0-9]*$ ]] || fail "DURATION must be a positive integer"
[[ "${INTERVAL}" =~ ^[1-9][0-9]*$ ]] || fail "INTERVAL must be a positive integer"
command -v docker >/dev/null 2>&1 || fail "required command not found: docker"

mkdir -p -- "${OUT_DIR}"
OUT_DIR=$(cd -- "${OUT_DIR}" && pwd)
TARGET_PID=$(moor_perf_container_pid "${TARGET_CONTAINER}") || exit 1

if [[ "${BUILD_IMAGE}" == true ]] || \
    ! docker image inspect "${MOOR_PERF_IMAGE}" >/dev/null 2>&1; then
    docker build \
        --file "${SCRIPT_DIR}/Dockerfile" \
        --tag "${MOOR_PERF_IMAGE}" \
        "${REPO_ROOT}"
fi

docker_args=(
    run
    --rm
    --privileged
    --pid=host
    --ulimit memlock=-1:-1
    --mount "type=bind,src=${OUT_DIR},dst=/output"
    --mount type=bind,src=/sys/kernel/tracing,dst=/sys/kernel/tracing
    --mount type=bind,src=/sys/kernel/debug,dst=/sys/kernel/debug
    --env OUT_DIR=/output
)
if [[ "${MODE}" == top && -t 0 && -t 1 ]]; then
    docker_args+=(--interactive --tty)
fi
for variable in FREQUENCY BPFTRACE_MAX_MAP_KEYS BPFTRACE_MAX_STRLEN; do
    if [[ -n "${!variable:-}" ]]; then
        docker_args+=(--env "${variable}")
    fi
done

case "${MODE}" in
    snapshot)
        collector=/moor/tools/perf/snapshot-running-moor.sh
        ;;
    profile)
        collector=/moor/tools/perf/profile-running-moor.sh
        ;;
    top)
        collector=/moor/tools/perf/mootop.sh
        ;;
esac

if [[ "${MODE}" == top ]]; then
    docker "${docker_args[@]}" "${MOOR_PERF_IMAGE}" \
        "${collector}" --interval "${INTERVAL}" \
        --verb-map-output "/output/moor-verb-map-${TARGET_PID}.json" \
        "${TARGET_PID}"
else
    docker "${docker_args[@]}" "${MOOR_PERF_IMAGE}" \
        "${collector}" --duration "${DURATION}" "${TARGET_PID}"
fi
