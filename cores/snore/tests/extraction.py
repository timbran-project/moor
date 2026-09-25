# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
# This program is free software under the GNU General Public License, version 3.
# It is distributed without any warranty. See <https://www.gnu.org/licenses/>.

"""Extract a disposable world, resume after restart, and reimport its objdef export."""

import argparse
import os
import pathlib
import shutil
import socket
import subprocess
import tempfile
import time

from wire import Client


FEATURES = [item for name in (
    "bool-type", "use-boolean-returns", "symbol-type", "use-symbols-in-builtins",
    "custom-errors", "use-uuobjids"
) for item in ("--" + name, "true")] + ["--flyweight-type", "false", "--rich-notify", "false"]


def run(server, moorc, core, evidence):
    with tempfile.TemporaryDirectory(prefix="snore-extraction-") as directory:
        root = pathlib.Path(directory)
        config = root / "moor.yaml"
        config.write_text("""features:
  bool_type: true
  use_boolean_returns: true
  symbol_type: true
  use_symbols_in_builtins: true
  custom_errors: true
  use_uuobjids: true
  flyweight_type: false
  rich_notify: false
services:
  telnet:
    enabled: true
    health_check_port: 0
  web:
    enabled: false
  curl_worker:
    enabled: false
""")
        process = None
        client = None
        output = None
        logs = []

        def start(number):
            nonlocal process, client, output
            if client:
                client.close()
            if output:
                output.close()
            with socket.socket() as reserve:
                reserve.bind(("127.0.0.1", 0))
                port = reserve.getsockname()[1]
            log = root / f"server-{number}.log"
            logs.append(log)
            output = log.open("w")
            argv = [str(server), str(root / "data"), "--config-file", str(config),
                    "--import", str(core), "--import-format", "objdef", "--export",
                    str(root / "export"), "--generate-keypair", "--no-web",
                    "--telnet-address", "127.0.0.1", "--telnet-port", str(port)]
            process = subprocess.Popen(argv, cwd=root, stdout=output, stderr=output,
                env=dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
                         XDG_DATA_HOME=str(root / "state")))
            deadline = time.monotonic() + 40
            while True:
                assert process.poll() is None, "Server exited during startup"
                try:
                    client = Client(port)
                    break
                except ConnectionRefusedError:
                    assert time.monotonic() < deadline, "Server startup timed out"
                    time.sleep(0.05)
            client.command("connect Wizard", "*** Connected ***")
            return client

        def eval_check(code, marker):
            return client.command(';; ' + code + f'; notify(player, "{marker}");', marker)

        def compile_export(source, destination):
            log = root / (destination.name + ".log")
            logs.append(log)
            with log.open("w") as stream:
                result = subprocess.run([str(moorc), *FEATURES, "--src-objdef-dir", str(source),
                    "--out-objdef-dir", str(destination)], stdout=stream, stderr=stream, timeout=45)
            assert result.returncode == 0 and destination.is_dir(), log.read_text()
            assert "Object load failed" not in log.read_text(), log.read_text()

        try:
            start(1)
            eval_check('add_property(#0, "extraction_initial_count", length(objects()), {#2, "r"}); '
                'const kept = create($root_class, #2); '
                'add_property(#0, "extraction_probe", kept, {#2, "r"}); '
                'add_property(kept, "self_ref", kept, {#2, "r"}); '
                'add_verb(kept, {#2, "rxd", "include_for_core"}, {"this", "none", "this"}); '
                'set_verb_code(kept, "include_for_core", {"return {\\\"self_ref\\\"};"}); '
                'const rubbish = create($root_class, #2); '
                'const numbered = renumber(create($root_class, #2), #9000); '
                'add_property(#0, "extraction_rubbish", {rubbish, numbered}, {#2, ""}); '
                'add_verb(#2, {#2, "rxd", "mcd_2"}, {"this", "none", "this"}); '
                'set_verb_code(#2, "mcd_2", {"return true;"})', "FIXTURE_READY")
            client.send("make-core-database")
            client.expect("Is this an isolated disposable copy?")
            client.send("yes")
            client.expect("Really extract the core?")
            client.send("yes")
            eval_check('$wizard_feature.__mcd__state[\'phase] == "prepare" || raise(E_INVARG); '
                'delete_verb(#2, "mcd_2"); '
                'while ($wizard_feature.__mcd__state[\'phase] != "delete") '
                '#2:_mcd_step(); suspend(0); endwhile '
                '#2:_mcd_step(); $wizard_feature.__mcd__state[\'index] == 2 || raise(E_INVARG)',
                "DELETION_CHECKPOINT")
            client.send(';; shutdown("extraction restart test");')
            assert process.wait(timeout=30) == 0, "First shutdown failed"

            start(2)
            eval_check('$wizard_feature.__mcd__state[\'phase] == "delete" || raise(E_INVARG); '
                '$wizard_feature.__mcd__state[\'index] == 2 || raise(E_INVARG)', "RESUME_READY")
            client.send("make-core-database resume")
            client.expect_any(("Core database extraction is complete.", "** Disconnected **"), timeout=45)
            assert process.wait(timeout=30) == 0, "Extraction shutdown failed"
            assert "Core database extraction is complete." in logs[-1].read_text()

            start(3)
            eval_check('length(objects()) == $extraction_initial_count + 1 || raise(E_INVARG); '
                'valid($extraction_probe) && !is_uuobjid($extraction_probe) || raise(E_INVARG); '
                '$extraction_probe.self_ref == $extraction_probe || raise(E_INVARG); '
                '{o for o in ($extraction_rubbish) if valid(o)} == {} || raise(E_INVARG); '
                '{$wiz, $default_player, $wizard_feature} == {#57, #88, #123} || raise(E_INVARG); '
                '`$wizard_feature.__mcd__state ! E_PROPNF => false\' == false || raise(E_INVARG); '
                'dump_database(true)', "EXTRACTED_AND_EXPORTED")
            checkpoints = sorted((root / "export").glob("checkpoint-*.moo"))
            assert checkpoints, "No completed objdef checkpoint"
            source = checkpoints[-1]
            first = root / "normalized"
            second = root / "reimported"
            compile_export(source, first)
            compile_export(first, second)
            left = {p.name: p.read_bytes() for p in first.glob("*.moo")}
            right = {p.name: p.read_bytes() for p in second.glob("*.moo")}
            assert left and left == right, "Extracted export changed across reimport"
            if evidence:
                shutil.copytree(first, evidence / "extracted", dirs_exist_ok=True)
            client.send(';; shutdown("extraction validation complete");')
            assert process.wait(timeout=30) == 0, "Final shutdown failed"
            print("PASS extraction: confirmation, deletion checkpoint, restart/resume, UUID links, stable IDs, export/reimport")
        except Exception:
            for log in logs:
                print(f"{log.name}:\n{log.read_text()[-20000:]}")
            raise
        finally:
            if client:
                client.close()
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if output:
                output.close()
            if evidence:
                for log in logs:
                    shutil.copy2(log, evidence / log.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", required=True, type=pathlib.Path)
    parser.add_argument("--moorc", required=True, type=pathlib.Path)
    parser.add_argument("--core", required=True, type=pathlib.Path)
    parser.add_argument("--evidence-dir", type=pathlib.Path)
    args = parser.parse_args()
    if args.evidence_dir:
        args.evidence_dir.mkdir(parents=True, exist_ok=True)
    run(args.server.resolve(), args.moorc.resolve(), args.core.resolve(), args.evidence_dir)
