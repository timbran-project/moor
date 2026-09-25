# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

"""Exercise Snore Core through real daemon and telnet processes in a temporary world."""

import argparse
import contextlib
import json
import pathlib
import os
import socket
import subprocess
import tempfile
import time


class Client:
    def __init__(self, port):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.socket.settimeout(0.2)
        self.buffer = b""

    def close(self):
        self.socket.close()

    def send(self, command):
        self.socket.sendall((command + "\r\n").encode())

    def expect(self, text, timeout=15):
        return self.expect_any((text,), timeout)[1]

    def expect_any(self, texts, timeout=15):
        deadline = time.monotonic() + timeout
        while True:
            matches = [(self.buffer.index(text.encode()), text) for text in texts
                       if text.encode() in self.buffer]
            if matches:
                offset, text = min(matches)
                end = offset + len(text.encode())
                received = self.buffer[:end].decode(errors="replace")
                self.buffer = self.buffer[end:]
                assert "Traceback" not in received, f"Unexpected task exception: {received}"
                assert "Confunc failed:" not in received, f"Connection hook failed: {received}"
                return text, received
            assert time.monotonic() < deadline, (
                f"Timed out waiting for {texts!r}; received {self.buffer.decode(errors='replace')!r}"
            )
            try:
                data = self.socket.recv(65536)
            except socket.timeout:
                continue
            assert data, f"Connection closed waiting for {texts!r}: {self.buffer!r}"
            self.buffer += data

    def expect_closed(self, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                data = self.socket.recv(65536)
            except socket.timeout:
                continue
            if not data:
                return
            self.buffer += data
        raise AssertionError("Connection remained open after @quit")

    def command(self, command, expected):
        self.send(command)
        return self.expect(expected)


def run(daemon, host, core):
    with tempfile.TemporaryDirectory(prefix="snore-wire-") as directory:
        root = pathlib.Path(directory)
        with contextlib.ExitStack() as stack:
            processes = []
            logs = []

            def launch(name, argv):
                path = root / (name + ".log")
                output = stack.enter_context(path.open("w"))
                process = subprocess.Popen(argv, stdout=output, stderr=output, cwd=root,
                    env=dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
                             XDG_DATA_HOME=str(root / "state")))
                processes.append(process)
                logs.append(path)
                return process

            endpoints = {key: f"ipc://{root}/{key}.sock" for key in (
                "rpc", "events", "workers-request", "workers-response", "enrollment"
            )}
            try:
                daemon_args = [str(daemon), str(root / "data"), "--import", str(core),
                               "--import-format", "objdef", "--generate-keypair",
                               "--private-key", str(root / "signing.pem"),
                               "--public-key", str(root / "verifying.pem"),
                               "--enrollment-token-file", str(root / "enrollment-token")]
                for key, address in endpoints.items():
                    daemon_args += ["--" + key + "-listen", address]
                for feature in ("bool-type", "use-boolean-returns", "symbol-type",
                                "use-symbols-in-builtins", "custom-errors", "use-uuobjids"):
                    daemon_args += ["--" + feature, "true"]
                daemon_args += ["--flyweight-type", "false", "--rich-notify", "false"]
                server = launch("daemon", daemon_args)
                deadline = time.monotonic() + 30
                while not (root / "rpc.sock").exists():
                    assert server.poll() is None, "Daemon exited before becoming ready"
                    assert time.monotonic() < deadline, "Daemon startup timed out"
                    time.sleep(0.05)
                with socket.socket() as reserve:
                    reserve.bind(("127.0.0.1", 0))
                    port = reserve.getsockname()[1]
                telnet = launch("telnet", [str(host), "--rpc-address", endpoints["rpc"],
                    "--events-address", endpoints["events"], "--telnet-address", "127.0.0.1",
                    "--telnet-port", str(port), "--health-check-port", "0",
                    "--data-dir", str(root / "host"),
                    "--enrollment-address", endpoints["enrollment"],
                    "--enrollment-token-file", str(root / "enrollment-token"),
                    "--workers-request-address", endpoints["workers-request"],
                    "--workers-response-address", endpoints["workers-response"]])
                deadline = time.monotonic() + 15
                while True:
                    assert telnet.poll() is None, "Telnet host exited before becoming ready"
                    try:
                        wizard = Client(port)
                        break
                    except ConnectionRefusedError:
                        assert time.monotonic() < deadline, "Telnet startup timed out"
                        time.sleep(0.05)
                stack.callback(wizard.close)
                wizard.expect("Welcome to Snore Core")
                wizard.expect("just boring enough")
                wizard.command("connect Wizard", "*** Connected ***")
                wizard.command(';; $player_db:insert("testplayer", #101); '
                    '$player_db:insert("testprog", #102); '
                    '$quota_utils:initialize_quota(#102); #102.owned_objects = {}; '
                    'add_property(#0, "wire_reconnects", 0, {#2, "r"}); '
                    'set_verb_code(#0, "user_reconnected", '
                    '{"$wire_reconnects = $wire_reconnects + 1;", '
                    '@verb_code(#0, "user_reconnected")}); '
                    'notify(player, "WIRE_SETUP_OK");', "WIRE_SETUP_OK")

                wizard.command("@who", "Wizard (#2)")
                wizard.expect("Total: 1 player")
                wizard.command("@wizards all", "Wizard (#2)")
                wizard.expect("Total: 1 player")
                login = Client(port)
                try:
                    login.command("who", "Wizard (#2)")
                    login.expect("Total: 1 player")
                finally:
                    login.close()

                ordinary = Client(port)
                stack.callback(ordinary.close)
                wizard.command(';; #101.password = argon2("wire-test-password", salt()); '
                    'notify(player, "WIRE_PASSWORD_SET");', "WIRE_PASSWORD_SET")
                ordinary.command("connect testplayer wrong-password",
                                 "Either that player does not exist, or has a different password.")
                ordinary.command("connect testplayer", "Password: ")
                ordinary.command("wire-test-password", "*** Connected ***")
                ordinary.command("look", "A bare room used by the automated tests.")
                ordinary.command("say wire speech", 'You say, "wire speech"')
                ordinary.command("@uptime", "Snore Core has been up for")
                ordinary.command("@version", "The database uses Snore Core, a LambdaCore fork for mooR.")
                ordinary.command("news", "WELCOME TO SNORE CORE")
                ordinary.expect("just boring enough")
                ordinary.command("@who #101", "Test Player (#101)")
                ordinary.expect("Total: 1 player")
                programmer = Client(port)
                stack.callback(programmer.close)
                programmer.command("connect testprog", "*** Connected ***")
                ordinary.command("page testprog wire private message", "Your message has been sent.")
                programmer.expect("wire private message")

                ordinary.command("@send testprog", "Subject:")
                ordinary.command("wire subject", "Composing")
                ordinary.command("say wire mail body", "Line 1 added.")
                ordinary.command("send", "Mail actually sent")
                programmer.expect("You have new mail")
                programmer.command("@read 1", "wire mail body")

                programmer.command("@create $thing called WireNote", "You now have WireNote")
                programmer.command("@notedit WireNote", "Now editing")
                programmer.command("say wire note body", "Line 1 added.")
                programmer.command("subst /wire/wire/gr1", "No changes in line 1.")
                programmer.command("s/body/body body/gr1", "wire note body body")
                programmer.command("find /wire/1", "wire note body body")
                programmer.command("list 1-$ nonum", "wire note body body")
                programmer.command("list 1-$ nonsense", "Don't understand this:  nonsense")
                programmer.command("print", "wire note body body")
                programmer.expect("--------------------------")
                programmer.command("publish", "Your text is now globally readable.")
                wizard.command(';; move(player, #102.location); notify(player, "WIRE_EDITOR_READER");',
                               "WIRE_EDITOR_READER")
                wizard.command("view", "Test Programmer")
                wizard.command("view testprog 1-$ nonum", "wire note body body")
                programmer.command("unpublish", "Your text is read protected.")
                wizard.command("view testprog", "has not published anything in this editor.")
                wizard.command("view", "No one has published anything in this editor.")
                wizard.command(';; move(player, #103); notify(player, "WIRE_EDITOR_READER_DONE");',
                               "WIRE_EDITOR_READER_DONE")
                wizard.command(';; const editor = #102.location; '
                    'let lines = {}; for n in [1..2000] '
                    'lines = {@lines, tostr("WIRE_LINE_", n)}; endfor '
                    'editor:load(editor:loaded(#102), lines); '
                    'notify(player, "WIRE_LONG_BUFFER_READY");', "WIRE_LONG_BUFFER_READY")
                listing = programmer.command("list 1-$", "^^^^")
                assert listing.count("WIRE_LINE_") == 2000, "Incomplete numbered listing"
                assert "WIRE_LINE_2000" in listing, "Missing final buffer line"
                wizard.command(';; const editor = #102.location; '
                    'editor:load(editor:loaded(#102), {"wire note body body"}); '
                    'notify(player, "WIRE_BUFFER_RESTORED");', "WIRE_BUFFER_RESTORED")
                # Reload identical text while read() is pending: content equality is insufficient.
                programmer.command("enter", "[Type")
                wizard.command(';; const editor = #102.location; '
                    'editor:load(editor:loaded(#102), {"wire note body body"}); '
                    'notify(player, "WIRE_REPLACED_DURING_READ");', "WIRE_REPLACED_DURING_READ")
                programmer.send("stale input")
                programmer.send(".")
                outcome, _ = programmer.expect_any(("Input discarded", "Line 2 added."))
                wizard.command(';; notify(player, tostr("WIRE_INPUT_TEXT=", '
                    'toliteral(#102.location:text(#102.location:loaded(#102)))));',
                    'WIRE_INPUT_TEXT={"wire note body body"}')
                assert outcome == "Input discarded", "Pending input reached a replacement buffer"
                programmer.command("enter", "[Type")
                programmer.send("cancelled partial input")
                programmer.command("@abort", ">> Command Aborted <<")
                wizard.command(';; notify(player, tostr("WIRE_CANCEL_TEXT=", '
                    'toliteral(#102.location:text(#102.location:loaded(#102)))));',
                    'WIRE_CANCEL_TEXT={"wire note body body"}')

                programmer.command("enter", "[Type")
                wizard.command(';; const editor = #102.location; '
                    'editor:reset_session(editor:loaded(#102)); '
                    'notify(player, "WIRE_CLEARED_DURING_READ");', "WIRE_CLEARED_DURING_READ")
                programmer.send("discard after reset")
                programmer.command(".", "Input discarded")
                programmer.command("abort", "No changes to throw away.  Editor cleared.")
                wizard.command(';; const editor = #102.location; '
                    'editor:load(#102 in editor.active, {"wire note body body"}); '
                    'notify(player, "WIRE_BUFFER_RELOADED");', "WIRE_BUFFER_RELOADED")

                programmer.command("enter", "[Type")
                wizard.command(';; const editor = #102.location; '
                    'editor:kill_session(editor:loaded(#102)); '
                    'notify(player, "WIRE_REMOVED_DURING_READ");', "WIRE_REMOVED_DURING_READ")
                programmer.send("discard after removal")
                programmer.command(".", "Input discarded")
                programmer.command("abort", "Use the EDIT command to select a note.")
                programmer.command("done", "You are not actually in")
                wizard.command(';; move(#102, #103); move(player, $note_editor); '
                    'notify(player, "WIRE_EDITOR_EXITED");',
                               "WIRE_EDITOR_EXITED")
                programmer.command("@notedit WireNote", "Now editing")
                wizard.command(';; const editor = #102.location; '
                    'editor:load(editor:loaded(#102), {"wire note body body"}); '
                    'notify(player, "WIRE_BUFFER_FINAL");', "WIRE_BUFFER_FINAL")
                # Removing the earlier reader's session shifts the index, not the buffer identity.
                programmer.command("enter", "[Type")
                wizard.command(';; move(player, #103); notify(player, "WIRE_SESSION_SHIFTED");',
                               "WIRE_SESSION_SHIFTED")
                programmer.send("shifted input")
                programmer.command(".", "Line 2 added.")
                wizard.command(';; notify(player, tostr("WIRE_SHIFT_TEXT=", '
                    'toliteral(#102.location:text(#102.location:loaded(#102)))));',
                    'WIRE_SHIFT_TEXT={"wire note body body", "shifted input"}')
                wizard.command(';; const editor = #102.location; '
                    'editor:load(editor:loaded(#102), {"wire note body body"}); '
                    'notify(player, "WIRE_SHIFT_RESTORED");', "WIRE_SHIFT_RESTORED")
                programmer.command("save", "Text written")
                programmer.command("done", "Test Chamber")
                programmer.command("look WireNote", "wire note body body")
                programmer.command("@recycle WireNote", "recycled.")

                # New accounts follow the UUID creation path and retain password authentication.
                created = Client(port)
                stack.callback(created.close)
                created.command("create WireNew wire-new-password", "*** Created ***")
                created.command("say wire new account", 'You say, "wire new account"')
                wizard.command(';; const account = $player_db:find_exact("WireNew"); '
                    'notify(player, tostr("WIRE_ACCOUNT=", '
                    'typeof(account) == typeof(#2) && !match(tostr(account), "^#[0-9]+$") && is_player(account) && parent(account) == $player_class '
                    '&& argon2_verify(account.password, "wire-new-password")));', "WIRE_ACCOUNT=true")
                created.close()
                created_again = Client(port)
                stack.callback(created_again.close)
                created_again.command("connect WireNew", "Password: ")
                created_again.command("wire-new-password", "*** Connected ***")
                created_again.command("say wire new reconnect", 'You say, "wire new reconnect"')
                created_again.command("@last-connection all", "Previous connections have been from the following sites:")
                created_again.close()

                guest = Client(port)
                stack.callback(guest.close)
                guest.command("connect Guest", "*** Connected ***")
                guest.command("say wire guest", 'You say, "wire guest"')
                guest.command("@uptime", "has been up for")
                guest.close()
                ordinary.close()
                reconnected = Client(port)
                stack.callback(reconnected.close)
                reconnected.command("connect testplayer wire-test-password", "*** Connected ***")
                reconnected.command("say wire reconnect", 'You say, "wire reconnect"')
                wizard.command(';; add_property(#0, "wire_primary", connections(#101)[1][1], {#2, ""}); '
                    'add_property(#0, "wire_wizard", connection(), {#2, "r"}); '
                    'notify(player, "WIRE_CONNECTIONS_SAVED");', "WIRE_CONNECTIONS_SAVED")
                additional = Client(port)
                stack.callback(additional.close)
                # Additional connections use the merged runtime's Connected hook.
                additional.command("connect testplayer wire-test-password", "*** Connected ***")
                additional.command("say wire simultaneous", 'You say, "wire simultaneous"')
                reconnected.expect('You say, "wire simultaneous"')
                wizard.command(';; notify(player, tostr("WIRE_RECONNECTS=", $wire_reconnects));',
                               "WIRE_RECONNECTS=0")
                def install_command(name, source):
                    code = "{" + ", ".join(json.dumps(line) for line in source) + "}"
                    wizard.command(';; add_verb(#101, {#101, "rd", ' + json.dumps(name) + '}, '
                        '{"none", "none", "none"}); set_verb_code(#101, ' + json.dumps(name) + ', '
                        + code + '); notify(player, "WIRE_VERB_INSTALLED");', "WIRE_VERB_INSTALLED")

                install_command("wire-current", ['this:tell_current("WIRE_CURRENT_ONLY");', 'notify(player, "WIRE_CURRENT_DONE");'])
                install_command("wire-lines", ['this:tell_current_lines({"WIRE_LINE_ONE", "WIRE_LINE_TWO"});'])
                install_command("wire-world", ['this:tell("WIRE_WORLD_ALL");', 'notify(player, "WIRE_WORLD_DONE");'])
                install_command("wire-denials", [
                    'const foreign = `this:tell_connection($wire_wizard, "WIRE_LEAK_FOREIGN") ! E_INVARG\';',
                    'const denied = `#2:tell_connection(connection(), "WIRE_LEAK_DENIED") ! E_PERM\';',
                    'const helper = `#2:_notify_connection(connection(), {"WIRE_LEAK_HELPER"}) ! E_PERM\';',
                    'this:tell_current(tostr("WIRE_DENIALS=", foreign == E_INVARG && denied == E_PERM && helper == E_PERM));',
                ])
                install_command("wire-read", [
                    'const line = $command_utils:read("wire input");',
                    'this:tell_current("WIRE_READ_RESULT=", line);',
                ])

                marker = 0

                def barrier(forbidden_a=(), forbidden_b=()):
                    nonlocal marker
                    marker += 1
                    label = f"WIRE_BARRIER_{marker}_END"
                    wizard.command(';; for c in (connections(#101)) notify(c[1], '
                        + json.dumps(label) + '); endfor notify(player, "WIRE_BARRIER_SENT");',
                        "WIRE_BARRIER_SENT")
                    for client, forbidden in ((reconnected, forbidden_a), (additional, forbidden_b)):
                        received = client.expect(label)
                        for text in forbidden:
                            assert text not in received, f"Output leaked to sibling connection: {text!r} in {received!r}"

                barrier()
                reconnected.command("wire-current", "WIRE_CURRENT_ONLY")
                barrier(forbidden_b=("WIRE_CURRENT_ONLY",))
                additional.command("wire-lines", "WIRE_LINE_ONE")
                additional.expect("WIRE_LINE_TWO")
                barrier(forbidden_a=("WIRE_LINE_ONE", "WIRE_LINE_TWO"))
                wizard.command(';; #101:tell_connection($wire_primary, "WIRE_EXPLICIT_ONLY"); '
                    '#101:tell_connection_lines($wire_primary, {"WIRE_EXPLICIT_LINE"}); '
                    'notify(player, "WIRE_EXPLICIT_SENT");', "WIRE_EXPLICIT_SENT")
                reconnected.expect("WIRE_EXPLICIT_ONLY")
                reconnected.expect("WIRE_EXPLICIT_LINE")
                barrier(forbidden_b=("WIRE_EXPLICIT_ONLY", "WIRE_EXPLICIT_LINE"))
                reconnected.command("wire-world", "WIRE_WORLD_ALL")
                additional.expect("WIRE_WORLD_ALL")
                reconnected.command("wire-denials", "WIRE_DENIALS=true")
                barrier(forbidden_a=("WIRE_LEAK_",), forbidden_b=("WIRE_LEAK_", "WIRE_DENIALS="))

                # Local delivery retains both gagging and anti-spoofing.
                wizard.command(';; #101.gaglist = {#101}; notify(player, "WIRE_GAG_SET");', "WIRE_GAG_SET")
                gagged_output = reconnected.command("wire-current", "WIRE_CURRENT_DONE")
                gagged_output += reconnected.command("wire-world", "WIRE_WORLD_DONE")
                for forbidden in ("WIRE_CURRENT_ONLY", "WIRE_WORLD_ALL"):
                    assert forbidden not in gagged_output, gagged_output
                barrier(forbidden_a=("WIRE_CURRENT_ONLY", "WIRE_WORLD_ALL"),
                        forbidden_b=("WIRE_CURRENT_ONLY", "WIRE_WORLD_ALL"))
                wizard.command(';; #101.gaglist = {}; #101.paranoid = 1; '
                    '$paranoid_db:erase_data(#101); notify(player, "WIRE_PARANOID_SET");', "WIRE_PARANOID_SET")
                reconnected.command("wire-current", "WIRE_CURRENT_ONLY")
                additional.command("wire-lines", "WIRE_LINE_ONE")
                additional.expect("WIRE_LINE_TWO")
                wizard.command(';; notify(player, tostr("WIRE_PARANOID_RECORDS=", '
                    'length($paranoid_db:get_data(#101)))); #101.paranoid = 2;', "WIRE_PARANOID_RECORDS=2")
                additional.command("wire-lines", "[start text by")
                additional.expect("[end text by")
                barrier(forbidden_a=("WIRE_LINE_ONE", "[start text by", "[end text by"))
                wizard.command(';; #101.paranoid = 0; notify(player, "WIRE_PARANOID_CLEARED");', "WIRE_PARANOID_CLEARED")

                reconnected.command("@who", "Total:")
                barrier(forbidden_b=("Feature Name", "Total:"))
                reconnected.command("help @who", "Syntax: @who")
                barrier(forbidden_b=("Syntax: @who",))
                reconnected.send("wire-read")
                reconnected.expect("[Type wire input")
                barrier(forbidden_b=("[Type wire input",))
                additional.command("say WIRE_WHILE_READING", 'You say, "WIRE_WHILE_READING"')
                reconnected.expect('You say, "WIRE_WHILE_READING"')
                reconnected.send("WIRE_ANSWER")
                reconnected.expect("WIRE_READ_RESULT=WIRE_ANSWER")
                barrier(forbidden_b=("WIRE_READ_RESULT=",))

                reconnected.send("@quit")
                reconnected.expect_closed()
                additional.command("say WIRE_STILL_CONNECTED", 'You say, "WIRE_STILL_CONNECTED"')
                wizard.command(';; notify(player, tostr("WIRE_REMAINING=", length(connections(#101)))); '
                    'const stale = `#101:tell_connection($wire_primary, "WIRE_STALE_LEAK") ! E_INVARG\'; '
                    'notify(player, tostr("WIRE_STALE_REJECTED=", stale == E_INVARG));', "WIRE_REMAINING=1")
                wizard.expect("WIRE_STALE_REJECTED=true")
                print("PASS wire: local/world delivery, explicit destinations, permissions, gagging, attribution, prompts, single-connection quit")
                assert all(process.poll() is None for process in processes), "A server exited"
                print("PASS wire: password rejection/prompt, account creation/login, who listings, guest, reconnect, speech, private page, mail, editing, create/recycle")
            except Exception:
                for path in logs:
                    print(f"{path.name}:\n{path.read_text()[-24000:]}")
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=pathlib.Path, required=True)
    parser.add_argument("--host", type=pathlib.Path, required=True)
    parser.add_argument("--core", type=pathlib.Path, required=True)
    args = parser.parse_args()
    run(args.daemon.resolve(), args.host.resolve(), args.core.resolve())
