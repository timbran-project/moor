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

mode="release"

print_usage() {
    cat <<'EOF'
Usage: ./tool/build_apk.sh [--debug|--profile|--release]

Builds an Android APK. Default is --release.

Output: build/app/outputs/flutter-apk/app-release.apk
EOF
}

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
            echo "Unknown option: $a" >&2
            print_usage
            exit 1
            ;;
    esac
done

flutter build apk "--$mode"

echo ""
echo "APK: build/app/outputs/flutter-apk/app-${mode}.apk"
