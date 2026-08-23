#!/usr/bin/env python3
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

import argparse
import json
import re
from pathlib import Path

TABLE_START = "fn mk_builtin_table() -> Vec<Builtin> {"
TABLE_END = "\n}\n// BuiltinId is now defined"
GROUP_SIZE = re.compile(r"const BUILTIN_GROUP_SIZE: usize = ([0-9]+);")
TABLE_TOKEN = re.compile(
    r'mk_builtin\s*\(\s*"((?:[^"\\]|\\.)*)"'
    r"|pad_group\s*\(\s*&mut builtins"
)


def builtin_names(source_path: Path) -> dict[int, str]:
    source = source_path.read_text(encoding="utf-8")
    group_match = GROUP_SIZE.search(source)
    if group_match is None:
        raise ValueError("BUILTIN_GROUP_SIZE is absent")
    group_size = int(group_match.group(1))

    start = source.index(TABLE_START) + len(TABLE_START)
    end = source.index(TABLE_END, start)
    table = source[start:end]

    names: dict[int, str] = {}
    next_id = 0
    group_end = group_size
    for match in TABLE_TOKEN.finditer(table):
        encoded_name = match.group(1)
        if encoded_name is not None:
            name = json.loads(f'"{encoded_name}"')
            if next_id in names:
                raise ValueError(f"duplicate builtin ID {next_id}")
            names[next_id] = name
            next_id += 1
            continue

        if next_id > group_end:
            raise ValueError(f"builtin group exceeds {group_size} entries")
        next_id = group_end
        group_end += group_size

    if not names:
        raise ValueError("builtin table contains no entries")
    return names


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Resolve stable mooR builtin IDs from the registry source"
    )
    parser.add_argument("ids", nargs="*", type=int, help="builtin IDs to show")
    parser.add_argument(
        "--source",
        type=Path,
        default=repo_root / "crates/common/src/builtins.rs",
        help="path to crates/common/src/builtins.rs",
    )
    parser.add_argument(
        "--format",
        choices=("table", "json"),
        default="table",
        help="output format (default: table)",
    )
    args = parser.parse_args()

    names = builtin_names(args.source)
    selected_ids = args.ids or sorted(names)
    selected = {
        builtin_id: names[builtin_id]
        for builtin_id in selected_ids
        if builtin_id in names
    }

    if args.format == "json":
        print(json.dumps(selected, sort_keys=True, separators=(",", ":")))
        return

    for builtin_id in selected_ids:
        name = names.get(builtin_id, "<reserved or unknown>")
        print(f"{builtin_id:>5}  {name}")


if __name__ == "__main__":
    main()
