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

//! Process-level checks for the data-directory lock.

use super::acquire_data_directory_lock;
use std::process::Command;

#[test]
fn child_lock_probe() {
    let Some(path) = std::env::var_os("MOOR_LOCK_TEST_DIRECTORY") else {
        return;
    };
    let should_acquire = std::env::var("MOOR_LOCK_TEST_EXPECT_ACQUIRED").unwrap() == "true";
    let result = acquire_data_directory_lock(&path.into());
    assert_eq!(result.is_ok(), should_acquire, "{result:?}");
}

#[test]
fn excludes_another_process_and_releases_on_close() {
    let dir = tempfile::tempdir().unwrap();
    let lock = acquire_data_directory_lock(&dir.path().to_path_buf()).unwrap();
    let probe = |should_acquire: bool| {
        let output = Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "directory_lock_tests::child_lock_probe",
                "--nocapture",
            ])
            .env("MOOR_LOCK_TEST_DIRECTORY", dir.path())
            .env("MOOR_LOCK_TEST_EXPECT_ACQUIRED", should_acquire.to_string())
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(String::from_utf8_lossy(&output.stdout).contains("1 passed"));
    };
    probe(false);
    drop(lock);
    probe(true);
}
