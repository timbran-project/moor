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
FREQUENCY=${FREQUENCY:-99}
OUT_DIR=${OUT_DIR:-"${PWD}"}
TARGET_PID=${TARGET_PID:-}
TARGET_CONTAINER=${TARGET_CONTAINER:-}
BPFTRACE_BIN=${BPFTRACE_BIN:-bpftrace}
BPFTRACE_MAX_MAP_KEYS=${BPFTRACE_MAX_MAP_KEYS:-65536}
BPFTRACE_MAX_STRLEN=${BPFTRACE_MAX_STRLEN:-128}
PYTHON_BIN=${PYTHON_BIN:-python3}
CLI_PID=
CLI_CONTAINER=
WORK_DIR=
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/container-target.sh"

usage() {
    cat <<'EOF'
Usage: tools/perf/snapshot-running-moor.sh [-d SECONDS] [-c CONTAINER | PID]

Attach to an active moor-daemon or moor process. Record task, verb, and database
commit probes. The command writes a report and the aggregate data to a tarball.

Arguments:
  PID         Process to inspect instead of searching for a server

Options:
  -c, --container CONTAINER
              Inspect the moor process in this Docker container
  -d, --duration SECONDS
              Recording duration (default: 10)
  -h, --help  Show this help text

Environment:
  TARGET_PID  Default PID when no PID argument is given
  TARGET_CONTAINER
              Default Docker container when no PID argument is given
  DURATION    Default recording duration in seconds
  FREQUENCY   MOO program-counter sample rate in hertz (default: 99)
  OUT_DIR     Directory for the tarball (default: current directory)
  BPFTRACE_BIN
              bpftrace executable to use (default: bpftrace)
  BPFTRACE_MAX_MAP_KEYS
              Maximum entries in each BPF map (default: 65536)
  BPFTRACE_MAX_STRLEN
              Maximum captured verb-name length (default: 128)
  PYTHON_BIN  Python executable to use (default: python3)
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
            [[ -z "${CLI_CONTAINER}" ]] || fail "only one container may be specified"
            CLI_CONTAINER=$2
            shift 2
            ;;
        --container=*)
            [[ -z "${CLI_CONTAINER}" ]] || fail "only one container may be specified"
            CLI_CONTAINER=${1#*=}
            [[ -n "${CLI_CONTAINER}" ]] || fail "missing value for --container"
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
            [[ -z "${CLI_PID}" ]] || fail "only one PID may be specified"
            CLI_PID=$1
            shift
            ;;
    esac
done

[[ $# -eq 0 ]] || fail "only one PID may be specified"
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

[[ "${DURATION}" =~ ^[1-9][0-9]*$ ]] || fail "DURATION must be a positive integer"
[[ "${FREQUENCY}" =~ ^[1-9][0-9]*$ ]] || fail "FREQUENCY must be a positive integer"
[[ "${BPFTRACE_MAX_MAP_KEYS}" =~ ^[1-9][0-9]*$ ]] || \
    fail "BPFTRACE_MAX_MAP_KEYS must be a positive integer"
[[ "${BPFTRACE_MAX_STRLEN}" =~ ^[1-9][0-9]*$ ]] || \
    fail "BPFTRACE_MAX_STRLEN must be a positive integer"

for command in "${BPFTRACE_BIN}" "${PYTHON_BIN}" readelf pgrep ps tar mktemp cp; do
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

if ! readelf -n "/proc/${PID}/exe" 2>/dev/null | grep -q 'Provider: moor_v1'; then
    fail "process ${PID} does not contain the moor_v1 probes"
fi

mkdir -p -- "${OUT_DIR}"
OUT_DIR=$(cd -- "${OUT_DIR}" && pwd)
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BUNDLE_NAME="moor-snapshot-${PROCESS_NAME}-${PID}-${TIMESTAMP}"
ARCHIVE="${OUT_DIR}/${BUNDLE_NAME}.tar.gz"
[[ ! -e "${ARCHIVE}" ]] || fail "output already exists: ${ARCHIVE}"

WORK_DIR=$(mktemp -d -t moor-snapshot.XXXXXXXX)
trap cleanup EXIT
BUNDLE_DIR="${WORK_DIR}/${BUNDLE_NAME}"
mkdir -- "${BUNDLE_DIR}"
AGGREGATES="${BUNDLE_DIR}/aggregates.jsonl"
REPORT="${BUNDLE_DIR}/report.txt"
ANALYSIS_ERROR="${BUNDLE_DIR}/analysis-error.txt"
COLLECTOR_ERROR="${BUNDLE_DIR}/collector-error.txt"

cp --dereference --preserve=mode -- "/proc/${PID}/exe" "${BUNDLE_DIR}/${PROCESS_NAME}"

echo "Recording ${PROCESS_NAME} (PID ${PID}) for ${DURATION} seconds..."
if ! BPFTRACE_MAX_MAP_KEYS="${BPFTRACE_MAX_MAP_KEYS}" \
    BPFTRACE_MAX_STRLEN="${BPFTRACE_MAX_STRLEN}" \
    "${BPFTRACE_BIN}" -q -k -f json -p "${PID}" -o "${AGGREGATES}" \
    "${SCRIPT_DIR}/moor-snapshot.bt" "${DURATION}" "${PID}" "${FREQUENCY}" \
    2> "${COLLECTOR_ERROR}"; then
    tar -C "${WORK_DIR}" -czf "${ARCHIVE}" "${BUNDLE_NAME}"
    cat "${COLLECTOR_ERROR}" >&2
    echo >&2
    echo "Capture failed. Partial data was preserved in ${ARCHIVE}" >&2
    exit 1
fi

if ! "${PYTHON_BIN}" "${SCRIPT_DIR}/analyze-moor-snapshot.py" "${AGGREGATES}" \
    > "${REPORT}" 2> "${ANALYSIS_ERROR}"; then
    tar -C "${WORK_DIR}" -czf "${ARCHIVE}" "${BUNDLE_NAME}"
    cat "${ANALYSIS_ERROR}" >&2
    echo >&2
    echo "Analysis failed. Aggregate data was preserved in ${ARCHIVE}" >&2
    exit 1
fi
rm -- "${ANALYSIS_ERROR}"
if [[ ! -s "${COLLECTOR_ERROR}" ]]; then
    rm -- "${COLLECTOR_ERROR}"
fi
tar -C "${WORK_DIR}" -czf "${ARCHIVE}" "${BUNDLE_NAME}"

cat "${REPORT}"
echo
echo "Wrote ${ARCHIVE}"
