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
PERF_BIN=${PERF_BIN:-perf}
TARGET_PID=${TARGET_PID:-}
CLI_PID=
WORK_DIR=

usage() {
    cat <<'EOF'
Usage: tools/perf/profile-running-moor.sh [-d SECONDS] [PID]

Find an active moor-daemon or moor process, sample it with perf, and create a
tarball containing perf.data and a copy of the process's executable.

Arguments:
  PID         Process to profile instead of searching for a server

Options:
  -d, --duration SECONDS
              Recording duration (default: 10)
  -h, --help  Show this help text

Environment:
  TARGET_PID  Default PID when no PID argument is given
  DURATION    Default recording duration in seconds
  FREQUENCY   Sampling frequency in hertz (default: 99)
  OUT_DIR     Directory for the tarball (default: current directory)
  PERF_BIN    perf executable to use (default: perf)
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

process_name() {
    local pid=$1

    [[ -r "/proc/${pid}/comm" ]] || return 1
    tr -d '\n' < "/proc/${pid}/comm"
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

check_perf_access() {
    local check_output
    local paranoid

    if check_output=$("${PERF_BIN}" stat -e cycles -p "${PID}" -- sleep 0.01 2>&1); then
        return 0
    fi

    is_active "${PID}" || fail "process ${PID} exited before perf could attach"

    if [[ -r /proc/sys/kernel/perf_event_paranoid ]]; then
        read -r paranoid < /proc/sys/kernel/perf_event_paranoid
    else
        paranoid=unknown
    fi

    if [[ "${paranoid}" =~ ^-?[0-9]+$ && ${paranoid} -ge 1 && ${EUID} -ne 0 ]]; then
        cat >&2 <<EOF
error: Linux is blocking access to the CPU performance counters.

kernel.perf_event_paranoid is ${paranoid}. This recording needs a value of 0 or lower.

For a temporary system-wide change:
  sudo sysctl kernel.perf_event_paranoid=0

Then rerun this script. Restore the current setting afterward with:
  sudo sysctl kernel.perf_event_paranoid=${paranoid}

Alternatively, run the script as root. For a persistent change, put
'kernel.perf_event_paranoid = 0' in a file under /etc/sysctl.d/.
See https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
EOF
        return 1
    fi

    echo "error: perf could not open the CPU performance counters:" >&2
    printf '%s\n' "${check_output}" >&2
    echo >&2
    echo "Run with CAP_PERFMON or as root, or adjust the host's perf_event_paranoid setting." >&2
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

if [[ $# -gt 0 ]]; then
    [[ $# -eq 1 && -z "${CLI_PID}" ]] || fail "only one PID may be specified"
    CLI_PID=$1
fi

if [[ -n "${CLI_PID}" ]]; then
    TARGET_PID=${CLI_PID}
fi

[[ "${DURATION}" =~ ^[1-9][0-9]*$ ]] || fail "DURATION must be a positive integer"
[[ "${FREQUENCY}" =~ ^[1-9][0-9]*$ ]] || fail "FREQUENCY must be a positive integer"

for command in "${PERF_BIN}" pgrep ps tar mktemp cp; do
    command -v "${command}" >/dev/null 2>&1 || fail "required command not found: ${command}"
done

if [[ -n "${TARGET_PID}" ]]; then
    [[ "${TARGET_PID}" =~ ^[1-9][0-9]*$ ]] || fail "TARGET_PID must be a process ID"
    is_active "${TARGET_PID}" || fail "process ${TARGET_PID} is not active"
    PID=${TARGET_PID}
else
    mapfile -t PIDS < <(find_servers)
    if [[ ${#PIDS[@]} -eq 0 ]]; then
        fail "no active moor-daemon or moor process found"
    fi
    if [[ ${#PIDS[@]} -gt 1 ]]; then
        echo "error: multiple active server processes found; set TARGET_PID to select one:" >&2
        for pid in "${PIDS[@]}"; do
            ps -o pid=,stat=,comm=,args= -p "${pid}" >&2
        done
        exit 1
    fi
    PID=${PIDS[0]}
fi

PROCESS_NAME=$(process_name "${PID}") || fail "cannot read the name of process ${PID}"
case "${PROCESS_NAME}" in
    moor-daemon|moor)
        ;;
    *)
        fail "process ${PID} is '${PROCESS_NAME}', not moor-daemon or moor"
        ;;
esac

check_perf_access

mkdir -p -- "${OUT_DIR}"
OUT_DIR=$(cd -- "${OUT_DIR}" && pwd)
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BUNDLE_NAME="moor-perf-${PROCESS_NAME}-${PID}-${TIMESTAMP}"
ARCHIVE="${OUT_DIR}/${BUNDLE_NAME}.tar.gz"
[[ ! -e "${ARCHIVE}" ]] || fail "output already exists: ${ARCHIVE}"

WORK_DIR=$(mktemp -d -t moor-perf.XXXXXXXX)
trap cleanup EXIT
BUNDLE_DIR="${WORK_DIR}/${BUNDLE_NAME}"
mkdir -- "${BUNDLE_DIR}"

# Copy through /proc so the archive contains the exact executable image, even
# when the original path has been replaced since the process was started.
cp --dereference --preserve=mode -- "/proc/${PID}/exe" "${BUNDLE_DIR}/${PROCESS_NAME}"

echo "Recording ${PROCESS_NAME} (PID ${PID}) for ${DURATION} seconds..."
"${PERF_BIN}" record \
    -F "${FREQUENCY}" \
    -g \
    --call-graph dwarf,16384 \
    -o "${BUNDLE_DIR}/perf.data" \
    -p "${PID}" \
    -- sleep "${DURATION}"

tar -C "${WORK_DIR}" -czf "${ARCHIVE}" "${BUNDLE_NAME}"

echo "Wrote ${ARCHIVE}"
