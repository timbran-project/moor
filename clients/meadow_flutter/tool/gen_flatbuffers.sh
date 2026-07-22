#!/usr/bin/env bash
#
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

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCHEMA_DIR="$ROOT/crates/schema/schema"
OUT_DIR="$ROOT/clients/meadow_flutter/lib/fbs"

mkdir -p "$OUT_DIR"

command -v flatc >/dev/null 2>&1 || {
  echo "flatc not found on PATH" >&2
  exit 1
}

# Generate a single set of Dart libraries rooted at moor_rpc.fbs, including all
# included .fbs files.
flatc \
  --dart \
  --gen-all \
  -I "$SCHEMA_DIR" \
  -o "$OUT_DIR" \
  "$SCHEMA_DIR/moor_rpc.fbs"

echo "Generated Dart FlatBuffers into: $OUT_DIR"

