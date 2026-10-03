// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Launching a daemon with `Test.db` and telnet hosts against it, for the wire tests.

// Each test binary uses a different part of this module.
#![allow(dead_code)]

use moor_moot::test_db_path;
use std::{
    net::TcpListener,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::OnceLock,
};
use uuid::Uuid;

static DAEMON_HOST_BIN: OnceLock<PathBuf> = OnceLock::new();
pub fn daemon_host_bin() -> &'static PathBuf {
    DAEMON_HOST_BIN.get_or_init(|| {
        // Build once per test process so daemon changes are included in wire tests.
        escargot::CargoBuild::new()
            .bin("moor-daemon")
            .manifest_path("../daemon/Cargo.toml")
            .current_release()
            .run()
            .expect("Failed to build moor-daemon")
            .path()
            .to_owned()
    })
}

pub fn telnet_host_bin() -> &'static str {
    env!("CARGO_BIN_EXE_moor-telnet-host")
}

/// Base path for the PUB/SUB IPC sockets used by the daemon, a unique UUID is appended to this.
const NARRATIVE_PATH_ROOT: &str = "ipc:///tmp/narrative-moor-moot-daemon-";
/// Base path for the RPC IPC sockets used by the daemon, a unique UUID is appended to this.
const RPC_PATH_ROOT: &str = "ipc:///tmp/rpc-moor-moot-daemon.sock-";

// Just a keypair generated with openssl to satisfy the daemon for running unit tests...

const SIGNING_KEY: &str = r#"-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEILrkKmddHFUDZqRCnbQsPoW/Wsp0fLqhnv5KNYbcQXtk
-----END PRIVATE KEY-----
"#;

const VERIFYING_KEY: &str = r#"-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAZQUxGvw8u9CcUHUGLttWFZJaoroXAmQgUGINgbBlVYw=
-----END PUBLIC KEY-----
"#;

/// Write the daemon's signing and verifying keys into `workdir`.
pub fn write_keys(workdir: &Path) {
    std::fs::write(workdir.join("moor-signing-key.pem"), SIGNING_KEY)
        .expect("Failed to write signing key file");
    std::fs::write(workdir.join("moor-verifying-key.pem"), VERIFYING_KEY)
        .expect("Failed to write verifying key file");
}

/// The daemon command: imports `Test.db` and listens on IPC sockets named after `uuid`.
pub fn daemon_command(workdir: &Path, uuid: Uuid) -> Command {
    let mut command = Command::new(daemon_host_bin());
    command
        .arg("--import")
        .arg(test_db_path())
        .args(["--import-format", "textdump"])
        .env("XDG_CONFIG_HOME", workdir.join("config"))
        .arg("--private-key")
        .arg(workdir.join("moor-signing-key.pem"))
        .arg("--public-key")
        .arg(workdir.join("moor-verifying-key.pem"))
        .arg("--enrollment-listen")
        .arg(format!("ipc://{}/enrollment.sock", workdir.display()))
        .arg("--workers-request-listen")
        .arg(format!("ipc://{}/workers-request.sock", workdir.display()))
        .arg("--workers-response-listen")
        .arg(format!("ipc://{}/workers-response.sock", workdir.display()))
        .arg("--events-listen")
        .arg(format!("{NARRATIVE_PATH_ROOT}{uuid}"))
        .arg("--rpc-listen")
        .arg(format!("{RPC_PATH_ROOT}{uuid}"))
        .arg("test.db")
        .current_dir(workdir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    command
}

/// The telnet host command for the daemon named by `uuid`, listening on `127.0.0.1:port`.
pub fn telnet_host_command(workdir: &Path, uuid: Uuid, port: u16) -> Command {
    let mut command = Command::new(telnet_host_bin());
    command
        .arg("--events-address")
        .arg(format!("{NARRATIVE_PATH_ROOT}{uuid}"))
        .arg("--rpc-address")
        .arg(format!("{RPC_PATH_ROOT}{uuid}"))
        .arg("--telnet-address")
        .arg("127.0.0.1")
        .arg("--telnet-port")
        .arg(format!("{port}"))
        .args(["--health-check-port", "0"])
        .env("XDG_CONFIG_HOME", workdir.join("config"))
        .arg("--debug")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .current_dir(workdir);
    command
}

/// Ask the OS for an unused port, then release it for a host to bind.
pub fn free_port() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.local_addr().unwrap().port()
}
