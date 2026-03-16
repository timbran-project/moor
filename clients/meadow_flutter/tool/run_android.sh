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
Usage: ./tool/run_android.sh [--debug|--profile|--release] [entrypoint args...]

Runs the app on a connected Android device or emulator.
Args are passed via --dart-define (Android doesn't support --dart-entrypoint-args).

Examples:
  ./tool/run_android.sh --server=http://10.0.2.2:8080 --login
  ./tool/run_android.sh --release --server=http://10.0.2.2:8080 --login

Note: Android emulators use 10.0.2.2 to reach the host machine's localhost.
EOF
}

dart_defines=()
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
        --login)
            dart_defines+=( --dart-define=LOGIN=true )
            ;;
        --server=*)
            dart_defines+=( --dart-define=SERVER="${a#--server=}" )
            ;;
        --username=*)
            dart_defines+=( --dart-define=USERNAME="${a#--username=}" )
            ;;
        --password=*)
            dart_defines+=( --dart-define=PASSWORD="${a#--password=}" )
            ;;
        --mode=*)
            dart_defines+=( --dart-define=MODE="${a#--mode=}" )
            ;;
        *)
            echo "Unknown option: $a" >&2
            print_usage
            exit 1
            ;;
    esac
done

# Find the first connected Android device/emulator.
device=$(flutter devices 2>/dev/null \
    | grep -i 'android' \
    | head -1 \
    | sed 's/.*• *\([^ ]*\) *• *android.*/\1/')

if [[ -z "$device" ]]; then
    echo "No Android device or emulator found. Start one with ./tool/emulator.sh start" >&2
    exit 1
fi

exec flutter run -d "$device" "--$mode" "${dart_defines[@]}"
