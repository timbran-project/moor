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

ANDROID_SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager"
EMULATOR="$ANDROID_SDK/emulator/emulator"

AVD_NAME="meadow"
SYSTEM_IMAGE="system-images;android-35;google_apis;x86_64"
DEVICE="pixel_7"

print_usage() {
    cat <<'EOF'
Usage: ./tool/emulator.sh <command>

Commands:
  setup     Install system image and create AVD (first-time setup)
  start     Launch the emulator
  list      List available AVDs
  delete    Delete the meadow AVD
EOF
}

cmd_setup() {
    echo "Installing system image..."
    "$SDKMANAGER" "$SYSTEM_IMAGE"
    echo ""
    echo "Creating AVD '$AVD_NAME' (device: $DEVICE)..."
    "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d "$DEVICE" --force
    echo ""
    echo "Done. Run './tool/emulator.sh start' to launch."
}

cmd_start() {
    if ! "$AVDMANAGER" list avd -c 2>/dev/null | grep -q "^${AVD_NAME}$"; then
        echo "AVD '$AVD_NAME' not found. Run './tool/emulator.sh setup' first." >&2
        exit 1
    fi
    echo "Starting emulator '$AVD_NAME'..."
    exec "$EMULATOR" -avd "$AVD_NAME" -gpu auto
}

cmd_list() {
    "$AVDMANAGER" list avd -c
}

cmd_delete() {
    "$AVDMANAGER" delete avd -n "$AVD_NAME"
}

case "${1:-}" in
    setup)  cmd_setup ;;
    start)  cmd_start ;;
    list)   cmd_list ;;
    delete) cmd_delete ;;
    *)      print_usage; exit 1 ;;
esac
