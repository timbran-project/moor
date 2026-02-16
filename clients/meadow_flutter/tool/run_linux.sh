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

mode="debug"

print_usage() {
    cat <<'EOF'
Usage: ./tool/run_linux.sh [--debug|--profile|--release] [entrypoint args...]

Examples:
  ./tool/run_linux.sh --server=http://localhost:8080 --username=foo --password=bar --login
  ./tool/run_linux.sh --profile --server=http://localhost:8080 --login
  ./tool/run_linux.sh --release --server=http://localhost:8080 --login
EOF
}

# Flutter doesn’t support passing arbitrary args after `--` to the Dart entrypoint.
# Desktop uses `--dart-entrypoint-args` (`-a`) instead, one flag per arg.
entry_args=()
for a in "$@"; do
    case "$a" in
        --debug)
            mode="debug"
            ;;
        --profile)
            mode="profile"
            ;;
        --release)
            mode="release"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            entry_args+=( -a "$a" )
            ;;
    esac
done

exec flutter run -d linux "--$mode" "${entry_args[@]}"
