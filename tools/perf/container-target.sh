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

moor_perf_container_pid() {
    local container=$1
    local output
    local pid
    local process_name
    local -a matches=()

    if ! output=$(docker top "${container}" -eo pid,comm 2>&1); then
        echo "error: cannot inspect Docker container '${container}': ${output}" >&2
        return 1
    fi
    while read -r pid process_name; do
        [[ "${pid}" =~ ^[1-9][0-9]*$ ]] || continue
        case "${process_name}" in
            moor-daemon|moor)
                matches+=("${pid}")
                ;;
        esac
    done <<< "${output}"

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "error: Docker container '${container}' has no moor-daemon or moor process" >&2
        return 1
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        echo "error: Docker container '${container}' has multiple server processes:" >&2
        docker top "${container}" -eo pid,comm >&2 || true
        return 1
    fi
    printf '%s\n' "${matches[0]}"
}
