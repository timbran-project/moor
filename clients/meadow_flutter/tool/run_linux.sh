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

# Flutter doesn’t support passing arbitrary args after `--` to the Dart entrypoint.
# Desktop uses `--dart-entrypoint-args` (`-a`) instead, one flag per arg.
entry_args=()
for a in "$@"; do
    entry_args+=( -a "$a" )
done

exec flutter run -d linux "${entry_args[@]}"

