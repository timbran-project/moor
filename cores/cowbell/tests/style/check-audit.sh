#!/usr/bin/env bash
# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.
set -euo pipefail

audit=${1:?Usage: check-audit.sh STYLE_AUDIT_BINARY}
audit=$(realpath "$audit")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/src/a" "$fixture/src/b"
printf 'define FIRST = #1;\ndefine SECOND = #2;\n' > "$fixture/src/constants.moo"
cat > "$fixture/src/a/shared.moo" <<'MOO'
object FIRST
  name: "First"
  parent: #-1
  owner: FIRST
  method clean owner: FIRST
    "Return a fixed value.";
    const value = 1;
    return value;
  endmethod
endobject
MOO
cat > "$fixture/src/b/shared.moo" <<'MOO'
object SECOND
  name: "Second"
  parent: #-1
  owner: SECOND
  method debt owner: SECOND
    value = 1;
    if (value = 2)
      return value;
    endif
  endmethod
endobject
MOO

must_fail() {
  if "$audit" "$fixture/src" "$@" > "$fixture/report.tsv" 2> "$fixture/summary"; then
    echo "Unexpected audit success: $*" >&2
    exit 1
  fi
}

# Nested duplicate basenames must retain both compiled bodies and their findings.
"$audit" "$fixture/src" --write-baseline "$fixture/baseline.tsv" > "$fixture/report.tsv"
"$audit" "$fixture/src" --baseline "$fixture/baseline.tsv" > /dev/null
"$audit" "$fixture/src" --strict --check a/shared.moo:clean > /dev/null
must_fail --strict
must_fail --strict --check b/shared.moo:debt
must_fail --strict --check a/shared.moo:clean --check a/shared.moo:missing
must_fail --check missing.moo

# Existing allowances must not cover a newly introduced local in the same method.
sed -i '/value = 1;/a\    extra = 3;' "$fixture/src/b/shared.moo"
must_fail --baseline "$fixture/baseline.tsv"
echo "Recursive audit, strict selection, empty selection, and debt regression checks passed."
