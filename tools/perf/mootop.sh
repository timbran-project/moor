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

INTERVAL=${INTERVAL:-5}
LIMIT=${LIMIT:-10}
TARGET_PID=${TARGET_PID:-}
TARGET_CONTAINER=${TARGET_CONTAINER:-}
BPFTRACE_BIN=${BPFTRACE_BIN:-bpftrace}
BPFTRACE_MAX_MAP_KEYS=${BPFTRACE_MAX_MAP_KEYS:-65536}
BPFTRACE_MAX_STRLEN=${BPFTRACE_MAX_STRLEN:-128}
PYTHON_BIN=${PYTHON_BIN:-python3}
BUILTIN_SOURCE=${BUILTIN_SOURCE:-}
VERB_MAP=${VERB_MAP:-}
VERB_MAP_OUTPUT=${VERB_MAP_OUTPUT:-}
CLI_PID=
CLI_CONTAINER=
ONCE=0
NO_CLEAR=false
WORK_DIR=
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/container-target.sh"

usage() {
    cat <<'EOF'
Usage: tools/perf/mootop.sh [OPTIONS] [PID]

Show live mooR task, MOO verb, builtin, and commit costs. Press Ctrl-C to stop.

Arguments:
  PID         Process to inspect instead of searching for a server

Options:
  -c, --container CONTAINER
              Inspect the mooR process in this Docker container
  -i, --interval SECONDS
              Refresh interval (default: 5)
  -l, --limit ROWS
              Maximum rows in each section (default: 10)
  --verb-map FILE
              JSON object that maps verb UUIDs to names
  --verb-map-output FILE
              Write names from the attached process to this file
              (default: ./moor-verb-map-PID.json)
  --no-clear  Append screens instead of clearing the terminal
  --once      Print one interval and stop
  -h, --help  Show this help text

Environment:
  TARGET_PID, TARGET_CONTAINER, INTERVAL, LIMIT, VERB_MAP, VERB_MAP_OUTPUT
  BPFTRACE_BIN, BPFTRACE_MAX_MAP_KEYS, BPFTRACE_MAX_STRLEN, PYTHON_BIN
  BUILTIN_SOURCE
EOF
}

cleanup() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf -- "${WORK_DIR}"
    fi
}

fail() {
    echo "error: $*" >&2
    exit 1
}

is_active() {
    local pid=$1
    local state

    state=$(ps -o stat= -p "${pid}" 2>/dev/null) || return 1
    state=${state//[[:space:]]/}
    [[ -n "${state}" && "${state}" != T* && "${state}" != Z* && "${state}" != X* ]]
}

find_servers() {
    local name
    local pid

    for name in moor-daemon moor; do
        while IFS= read -r pid; do
            if is_active "${pid}"; then
                printf '%s\n' "${pid}"
            fi
        done < <(pgrep -x "${name}" || true)
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--container)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            [[ -z "${CLI_CONTAINER}" ]] || fail "only one container can be specified"
            CLI_CONTAINER=$2
            shift 2
            ;;
        --container=*)
            [[ -z "${CLI_CONTAINER}" ]] || fail "only one container can be specified"
            CLI_CONTAINER=${1#*=}
            [[ -n "${CLI_CONTAINER}" ]] || fail "missing value for --container"
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
        -l|--limit)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            LIMIT=$2
            shift 2
            ;;
        --limit=*)
            LIMIT=${1#*=}
            shift
            ;;
        --verb-map)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            VERB_MAP=$2
            shift 2
            ;;
        --verb-map=*)
            VERB_MAP=${1#*=}
            [[ -n "${VERB_MAP}" ]] || fail "missing value for --verb-map"
            shift
            ;;
        --verb-map-output)
            [[ $# -ge 2 ]] || fail "missing value for $1"
            VERB_MAP_OUTPUT=$2
            shift 2
            ;;
        --verb-map-output=*)
            VERB_MAP_OUTPUT=${1#*=}
            [[ -n "${VERB_MAP_OUTPUT}" ]] || fail "missing value for --verb-map-output"
            shift
            ;;
        --no-clear)
            NO_CLEAR=true
            shift
            ;;
        --once)
            ONCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage >&2
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "${CLI_PID}" ]] || fail "only one PID can be specified"
            CLI_PID=$1
            shift
            ;;
    esac
done

[[ $# -eq 0 ]] || fail "only one PID can be specified"
if [[ -n "${CLI_PID}" && -n "${CLI_CONTAINER}" ]]; then
    fail "PID and container are mutually exclusive"
fi
if [[ -n "${CLI_PID}" ]]; then
    TARGET_PID=${CLI_PID}
    TARGET_CONTAINER=
elif [[ -n "${CLI_CONTAINER}" ]]; then
    TARGET_CONTAINER=${CLI_CONTAINER}
    TARGET_PID=
fi
if [[ -n "${TARGET_PID}" && -n "${TARGET_CONTAINER}" ]]; then
    fail "TARGET_PID and TARGET_CONTAINER are mutually exclusive"
fi

[[ "${INTERVAL}" =~ ^[1-9][0-9]*$ ]] || fail "INTERVAL must be a positive integer"
[[ "${LIMIT}" =~ ^[1-9][0-9]*$ ]] || fail "LIMIT must be a positive integer"
[[ "${BPFTRACE_MAX_MAP_KEYS}" =~ ^[1-9][0-9]*$ ]] || \
    fail "BPFTRACE_MAX_MAP_KEYS must be a positive integer"
[[ "${BPFTRACE_MAX_STRLEN}" =~ ^[1-9][0-9]*$ ]] || \
    fail "BPFTRACE_MAX_STRLEN must be a positive integer"

for command in "${BPFTRACE_BIN}" "${PYTHON_BIN}" dirname readelf pgrep ps mktemp; do
    command -v "${command}" >/dev/null 2>&1 || fail "required command not found: ${command}"
done

if [[ -n "${TARGET_CONTAINER}" ]]; then
    command -v docker >/dev/null 2>&1 || fail "required command not found: docker"
    TARGET_PID=$(moor_perf_container_pid "${TARGET_CONTAINER}") || exit 1
fi

if [[ -n "${TARGET_PID}" ]]; then
    [[ "${TARGET_PID}" =~ ^[1-9][0-9]*$ ]] || fail "TARGET_PID must be a process ID"
    is_active "${TARGET_PID}" || fail "process ${TARGET_PID} is not active"
    PID=${TARGET_PID}
else
    mapfile -t PIDS < <(find_servers)
    [[ ${#PIDS[@]} -gt 0 ]] || fail "no active moor-daemon or moor process found"
    if [[ ${#PIDS[@]} -gt 1 ]]; then
        echo "error: multiple active server processes found; specify a PID:" >&2
        for pid in "${PIDS[@]}"; do
            ps -o pid=,stat=,comm=,args= -p "${pid}" >&2
        done
        exit 1
    fi
    PID=${PIDS[0]}
fi

PROCESS_NAME=$(tr -d '\n' < "/proc/${PID}/comm")
case "${PROCESS_NAME}" in
    moor-daemon|moor)
        ;;
    *)
        fail "process ${PID} is '${PROCESS_NAME}', not moor-daemon or moor"
        ;;
esac

PROBE_NOTES=$(readelf -n "/proc/${PID}/exe" 2>/dev/null)
for probe_name in \
    diagnostics_attached verb_metadata verb_metadata_done \
    task_run_start verb_run_start builtin_run_start db_commit_start; do
    if ! grep -q "Name: ${probe_name}" <<< "${PROBE_NOTES}"; then
        fail "process ${PID} does not contain the ${probe_name} probe"
    fi
done

if [[ -n "${VERB_MAP}" && ! -f "${VERB_MAP}" ]]; then
    fail "verb map does not exist: ${VERB_MAP}"
fi
if [[ -z "${VERB_MAP_OUTPUT}" ]]; then
    VERB_MAP_OUTPUT="${PWD}/moor-verb-map-${PID}.json"
fi
VERB_MAP_OUTPUT_DIR=$(dirname -- "${VERB_MAP_OUTPUT}")
[[ -d "${VERB_MAP_OUTPUT_DIR}" ]] || \
    fail "verb map output directory does not exist: ${VERB_MAP_OUTPUT_DIR}"

WORK_DIR=$(mktemp -d -t moortop.XXXXXXXX)
trap cleanup EXIT
BUILTIN_MAP="${WORK_DIR}/builtin-map.json"
if [[ -z "${BUILTIN_SOURCE}" ]]; then
    BUILTIN_SOURCE="${SCRIPT_DIR}/../../crates/common/src/builtins.rs"
fi

RENDER_ARGS=(
    --pid "${PID}"
    --interval "${INTERVAL}"
    --limit "${LIMIT}"
    --verb-map-output "${VERB_MAP_OUTPUT}"
)
if [[ -f "${BUILTIN_SOURCE}" ]]; then
    "${PYTHON_BIN}" "${SCRIPT_DIR}/builtin-id-map.py" \
        --source "${BUILTIN_SOURCE}" --format json > "${BUILTIN_MAP}"
    RENDER_ARGS+=(--builtin-map "${BUILTIN_MAP}")
fi
if [[ -n "${VERB_MAP}" ]]; then
    RENDER_ARGS+=(--verb-map "${VERB_MAP}")
fi
if [[ "${NO_CLEAR}" == true ]]; then
    RENDER_ARGS+=(--no-clear)
fi

echo "Attaching mootop to ${PROCESS_NAME} (PID ${PID}); refresh=${INTERVAL}s" >&2
BPFTRACE_MAX_MAP_KEYS="${BPFTRACE_MAX_MAP_KEYS}" \
    BPFTRACE_MAX_STRLEN="${BPFTRACE_MAX_STRLEN}" \
    "${BPFTRACE_BIN}" -q -k -B none -f json -p "${PID}" \
    "${SCRIPT_DIR}/moortop.bt" "${INTERVAL}" "${PID}" "${ONCE}" | \
    "${PYTHON_BIN}" "${SCRIPT_DIR}/render-moortop.py" "${RENDER_ARGS[@]}"
