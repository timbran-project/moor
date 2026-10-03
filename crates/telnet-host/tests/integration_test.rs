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

#![cfg(target_os = "linux")]
#![cfg_attr(coverage_nightly, feature(coverage_attribute))]
#[cfg_attr(coverage_nightly, coverage(off))]
mod common;

use moor_moot::{MootOptions, telnet::ManagedChild};
use serial_test::serial;
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use uuid::Uuid;

fn start_daemon(workdir: &Path, uuid: Uuid) -> ManagedChild {
    ManagedChild::new(
        "daemon",
        common::daemon_command(workdir, uuid)
            .spawn()
            .expect("Failed to start daemon"),
    )
}

fn start_telnet_host(workdir: &Path, uuid: Uuid, port: u16) -> ManagedChild {
    ManagedChild::new(
        "telnet-host",
        common::telnet_host_command(workdir, uuid, port)
            .spawn()
            .expect("Failed to start telnet host"),
    )
}

// These tests all listen on the same port, so we need to make sure
// only one runs at a time.

fn test_moot_with_telnet_host<P: AsRef<Path>>(moot_file: P) {
    use moor_moot::{execute_moot_test, telnet::TelnetMootRunner};

    // Assign our unique identifier for this test run to be used in the paths for the IPC sockets.
    let uuid = Uuid::new_v4();

    let test_workdir = tempfile::TempDir::new().expect("Failed to create temporary directory");

    // Write the private and public key files in the test workdir
    common::write_keys(test_workdir.path());

    let daemon = Arc::new(Mutex::new(start_daemon(test_workdir.path(), uuid)));
    daemon.lock().unwrap().assert_running().unwrap();

    // Ask the OS for a random unused port for the telnet host.
    let port = common::free_port();
    let telnet_host = Arc::new(Mutex::new(start_telnet_host(
        test_workdir.path(),
        uuid,
        port,
    )));

    let daemon_clone = daemon.clone();
    let telnet_host_clone = telnet_host.clone();
    let validate_state = move || {
        daemon_clone.lock().unwrap().assert_running()?;
        telnet_host_clone.lock().unwrap().assert_running()
    };

    let moot_options = MootOptions::default();
    execute_moot_test(
        TelnetMootRunner::new(port),
        &moot_options,
        &PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/moot")
            .join(moot_file)
            .with_extension("moot"),
        validate_state,
    );

    drop(daemon);
    drop(telnet_host);
}

#[test]
#[serial(telnet_host)]
fn test_echo() {
    test_moot_with_telnet_host("echo");
}

#[test]
#[serial(telnet_host)]
fn test_suspend_read_notify() {
    test_moot_with_telnet_host("suspend_read_notify");
}

#[test]
#[serial(telnet_host)]
fn test_huh() {
    test_moot_with_telnet_host("huh");
}
