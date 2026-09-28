# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
# This program is free software under the GNU General Public License, version 3.
# It is distributed without any warranty. See <https://www.gnu.org/licenses/>.

"""Check nested source edits, additions, and deletions in a disposable core."""

from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


command = sys.argv[1:]
if "/" in command[0]:
    command[0] = str(Path(command[0]).resolve())
if "cargo" in command[0] and "run" in command:
    index = command.index("run") + 1
    command[index:index] = ["--manifest-path", str(Path("../../Cargo.toml").resolve())]


def build(core):
    subprocess.run(
        ["make", "-C", str(core), "gen.objdir", "MOORC=" + shlex.join(command)],
        check=True,
        timeout=120,
    )


with tempfile.TemporaryDirectory(prefix="cowbell-inventory-") as temporary:
    core = Path(temporary)
    shutil.copy("Makefile", core)
    shutil.copytree("src", core / "src")
    build(core)
    nested = core / "src" / "inventory" / "nested"
    nested.mkdir(parents=True)
    probe = nested / "probe.moo"
    source = '''object #90200
  name: "inventory probe added"
  parent: #1
  owner: #2
  override import_export_id = "inventory_probe";
  override import_export_hierarchy = {"inventory", "nested"};
endobject
'''
    probe.write_text(source)
    build(core)
    exported = core / "gen.objdir" / "inventory" / "nested" / "inventory_probe.moo"
    assert "inventory probe added" in exported.read_text(), "nested addition missing"
    probe.write_text(source.replace("probe added", "probe edited"))
    build(core)
    assert "inventory probe edited" in exported.read_text(), "nested edit missing"
    probe.unlink()
    build(core)
    assert not exported.exists(), "deleted source survived export"
    assert "#90200" not in (core / "gen.objdir" / "constants.moo").read_text()
print("PASS: nested additions, edits, and deletions rebuild the export")
