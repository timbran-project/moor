#!/bin/bash
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

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if ! gitlint_bin=$(command -v gitlint); then
    echo "Install gitlint first: uv tool install gitlint-core==0.19.1" >&2
    exit 1
fi

# A configured hooks directory can be shared by other repositories.
if git config --get core.hooksPath >/dev/null; then
    echo "core.hooksPath is set. Install the commit-msg hook there manually." >&2
    exit 1
fi

hook_path=$(git rev-parse --git-path hooks/commit-msg)
mkdir -p -- "$(dirname -- "$hook_path")"
hook_tmp=$(mktemp "${hook_path}.XXXXXX")
trap 'rm -f -- "$hook_tmp"' EXIT

{
    printf '#!/bin/bash\nset -euo pipefail\n'
    printf 'exec %q --config "$(git rev-parse --show-toplevel)/scripts/gitlint.cfg" --msg-filename "$1"\n' "$gitlint_bin"
} > "$hook_tmp"
chmod +x "$hook_tmp"

if [[ -e "$hook_path" || -L "$hook_path" ]]; then
    if cmp -s -- "$hook_tmp" "$hook_path"; then
        chmod +x "$hook_path"
        echo "Commit-message hook is already installed."
        exit 0
    fi
    echo "An existing commit-msg hook is present: $hook_path" >&2
    echo "Keep that hook and add the gitlint command manually." >&2
    exit 1
fi

# Link without overwriting a hook installed concurrently.
ln -- "$hook_tmp" "$hook_path"
echo "Installed commit-message hook: $hook_path"
