# Copyright (C) 2026 The mooR Authors
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise Cowbell Git wrappers through real daemon, telnet, and worker processes."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlsplit

from wire import Client, PASSWORD_HASH


def free_port():
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        return reservation.getsockname()[1]


def run(bin_dir, core_dir):
    with tempfile.TemporaryDirectory(prefix="cowbell-git-") as directory:
        root = Path(directory)
        core = root / "src"
        shutil.copytree(core_dir, core)
        arch = core / "arch_wizard.moo"
        source, count = re.subn(
            r"(override password(?:\s*\([^;\n]*\))?\s*=\s*).*?;",
            lambda match: match[1] + "<PASSWORD, {" + json.dumps(PASSWORD_HASH) + "}>;",
            arch.read_text(),
        )
        assert count == 1
        arch.write_text(source)
        repo = root / "repo.git"
        repo.mkdir()
        git_env = dict(
            os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull
        )

        def git(*args):
            return subprocess.check_output(
                [
                    "git",
                    "-C",
                    str(repo),
                    "-c",
                    "user.name=Cowbell Test",
                    "-c",
                    "user.email=test@example.invalid",
                    *args,
                ],
                env=git_env,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=15,
            ).strip()

        git("init", "--initial-branch=main")
        (repo / "src").mkdir()
        (repo / "src/Readme").write_bytes(b"Original\r\n")
        (repo / "src/README").write_bytes(b"\x00\xff\r\n")
        (repo / "src/link").symlink_to("../outside")
        git("add", ".")
        git("commit", "-m", "Initial fixture")
        initial = "sha1:" + git("rev-parse", "HEAD")

        class GitHTTP(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def setup(self):
                super().setup()
                self.connection.settimeout(15)

            def do_GET(self):
                body = b""
                if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
                    while True:
                        size = int(self.rfile.readline().split(b";", 1)[0], 16)
                        if not size:
                            while self.rfile.readline() not in (b"\r\n", b""):
                                pass
                            break
                        body += self.rfile.read(size)
                        assert self.rfile.read(2) == b"\r\n"
                else:
                    body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                url = urlsplit(self.path)
                env = dict(
                    git_env,
                    GIT_PROJECT_ROOT=str(root),
                    GIT_HTTP_EXPORT_ALL="1",
                    PATH_INFO=url.path,
                    QUERY_STRING=url.query,
                    REQUEST_METHOD=self.command,
                    CONTENT_LENGTH=str(len(body)),
                    CONTENT_TYPE=self.headers.get("Content-Type", ""),
                    HTTP_GIT_PROTOCOL=self.headers.get("Git-Protocol", ""),
                )
                result = subprocess.run(
                    ["git", "http-backend"],
                    input=body,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    check=True,
                    timeout=15,
                )
                headers, content = result.stdout.split(b"\r\n\r\n", 1)
                pairs = [line.decode().split(":", 1) for line in headers.split(b"\r\n")]
                status = next(
                    (int(v.strip().split()[0]) for k, v in pairs if k == "Status"), 200
                )
                self.send_response(status)
                for key, value in pairs:
                    if key != "Status":
                        self.send_header(key, value.strip())
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)

            do_POST = do_GET

        http = ThreadingHTTPServer(("127.0.0.1", 0), GitHTTP)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{http.server_port}/repo.git"
        config = root / "config.yaml"
        config.write_text(
            "features:\n"
            + "".join(
                f"  {name}: true\n"
                for name in (
                    "rich_notify",
                    "type_dispatch",
                    "flyweight_type",
                    "bool_type",
                    "use_boolean_returns",
                    "custom_errors",
                    "use_uuobjids",
                    "anonymous_objects",
                    "symbol_type",
                    "use_symbols_in_builtins",
                )
            )
        )
        sockets = {
            name: f"ipc://{root}/{name}.sock"
            for name in ("rpc", "events", "workers-request", "workers-response")
        }
        enrollment = f"tcp://127.0.0.1:{free_port()}"
        token = root / "enrollment-token"
        port = free_port()
        processes = []
        client = None

        def start(name, args):
            log = root / f"{name}.log"
            with log.open("w") as output:
                process = subprocess.Popen(
                    [str(bin_dir / name), *map(str, args)],
                    cwd=root,
                    stdout=output,
                    stderr=output,
                    env=dict(
                        os.environ,
                        XDG_CONFIG_HOME=str(root / "config"),
                        XDG_DATA_HOME=str(root / "state"),
                    ),
                )
            processes.append((process, log))
            return process

        try:
            start(
                "moor-daemon",
                [
                    root / "data",
                    "--config-file",
                    config,
                    "--generate-keypair",
                    "--private-key",
                    root / "signing.pem",
                    "--public-key",
                    root / "verifying.pem",
                    "--enrollment-token-file",
                    token,
                    "--enrollment-listen",
                    enrollment,
                    "--import",
                    core,
                    "--import-format",
                    "objdef",
                    *[
                        arg
                        for name, address in sockets.items()
                        for arg in (f"--{name}-listen", address)
                    ],
                ],
            )
            deadline = time.monotonic() + 60
            while not token.exists() or not (root / "rpc.sock").exists():
                assert processes[0][0].poll() is None, "Daemon exited during startup"
                assert time.monotonic() < deadline, "Daemon startup timed out"
                time.sleep(0.05)
            common = [
                "--enrollment-address",
                enrollment,
                "--enrollment-token-file",
                token,
                *[
                    arg
                    for name, address in sockets.items()
                    for arg in (f"--{name}-address", address)
                ],
            ]
            start(
                "moor-git-worker",
                [
                    *common,
                    "--data-dir",
                    root / "git-identity",
                    "--work-dir",
                    root / "jobs",
                ],
            )
            start(
                "moor-telnet-host",
                [
                    *common,
                    "--data-dir",
                    root / "telnet-identity",
                    "--telnet-address",
                    "127.0.0.1",
                    "--telnet-port",
                    port,
                    "--health-check-port",
                    "0",
                ],
            )
            while client is None:
                assert all(p.poll() is None for p, _ in processes), (
                    "Service exited during startup"
                )
                assert time.monotonic() < deadline, "Telnet startup timed out"
                try:
                    client = Client(port)
                except ConnectionRefusedError:
                    time.sleep(0.05)
            client.command("connect ArchWizard cowbell-wire-test", "*** Connected ***")
            # Registration is asynchronous. Capabilities also proves the real worker round trip.
            while True:
                marker = client.eval_marker(
                    "const caps = `$git:capabilities() ! E_QUOTA => false'; "
                    'notify(connection(), typeof(caps) == TYPE_MAP ? "GIT_READY" | "GIT_WAIT");',
                    ("GIT_READY", "GIT_WAIT"),
                    timeout=35,
                )
                if marker == "GIT_READY":
                    break
                assert time.monotonic() < deadline, "Git worker registration timed out"
                time.sleep(0.1)
            client.eval_marker(
                f"const repo = $git:repository({json.dumps(url)}); "
                'const refs = repo:refs(); refs[1][\'name] == "refs/heads/main" || raise(E_ASSERT); '
                'const snap = repo:snapshot([\'ref -> "refs/heads/main"], "src"); '
                f"snap.commit == {json.dumps(initial)} || raise(E_ASSERT); "
                'snap:entry("Readme"):text() == "Original\\r\\n" || raise(E_ASSERT); '
                'snap:entry("README"):bytes() == decode_base64("AP8NCg==") || raise(E_ASSERT); '
                'snap:entry("link"):text() == "../outside" || raise(E_ASSERT); '
                'const tree = repo:tree([\'commit -> snap.commit], "src"); '
                '!tree.complete && !tree:entry("Readme"):has_content() || raise(E_ASSERT); '
                'notify(connection(), "SNAPSHOT_OK");',
                "SNAPSHOT_OK",
                timeout=40,
            )
            (repo / "src/Readme").write_text("Changed\n")
            git("add", ".")
            git("commit", "-m", "Move branch")
            client.eval_marker(
                f"const repo = $git:repository({json.dumps(url)}); "
                f'const entry = repo:read([\'commit -> {json.dumps(initial)}], "src/Readme"); '
                'entry:text() == "Original\\r\\n" || raise(E_ASSERT); '
                'repo:read([\'ref -> "refs/heads/main"], "src/Readme"):text() == "Changed\\n" || raise(E_ASSERT); '
                'try repo:read([\'ref -> "refs/heads/main"], "missing"); raise(E_ASSERT); '
                'except error (E_GIT) error[3][\'code] == "path_not_found" || raise(E_ASSERT); endtry '
                'notify(connection(), "PIN_AND_ERROR_OK");',
                "PIN_AND_ERROR_OK",
                timeout=40,
            )
            print(
                "PASS Cowbell Git capabilities, refs, tree, snapshot, binary data, commit pin, and errors",
                flush=True,
            )
        except BaseException:
            for _, log in processes:
                print(f"{log.name}:\n{log.read_text()[-8000:]}", flush=True)
            raise
        finally:
            if client is not None:
                client.close()
            for process, _ in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            http.shutdown()
            http.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, default=Path("../../target/debug"))
    parser.add_argument("--core-dir", type=Path, default=Path("src"))
    args = parser.parse_args()
    run(args.bin_dir.resolve(), args.core_dir.resolve())
