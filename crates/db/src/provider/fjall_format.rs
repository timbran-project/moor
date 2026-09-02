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

//! Fjall database-format marker handling.
//!
//! Database format 2.0 stores property values as bounded record chains. mooR accepts only an exact
//! format match. An older database must be exported by a compatible server and imported into a
//! fresh database.

use fjall::KeyspaceCreateOptions;
use semver::Version;
use std::path::Path;
use tracing::info;

/// Current database format version. This version is independent of the mooR release version.
const CURRENT_DB_VERSION: &str = "2.0.0";

/// Database version marker key in sequences partition
const VERSION_KEY: &[u8] = b"__db_version__";

/// Check the database-format marker before opening the database for normal use.
pub fn fjall_check_format(db_path: &Path) -> Result<(), String> {
    let database = fjall::Database::builder(db_path)
        .open()
        .map_err(|e| format!("Failed to open database to check version: {e}"))?;
    let has_sequences = database.keyspace_exists("sequences");
    let has_existing_relations = database.keyspace_count() > usize::from(has_sequences);
    if has_existing_relations && !has_sequences {
        return Err(
            "Existing database has no format version; export it with a compatible mooR version and import it into a fresh database"
                .to_string(),
        );
    }

    let sequences_keyspace = database
        .keyspace("sequences", KeyspaceCreateOptions::default)
        .map_err(|e| format!("Failed to open sequences keyspace: {e}"))?;

    let current_version_str = sequences_keyspace
        .get(VERSION_KEY)
        .map_err(|error| format!("Failed to read database format marker: {error}"))?
        .map(|bytes| {
            String::from_utf8(bytes.to_vec())
                .map_err(|error| format!("Database format marker is not UTF-8: {error}"))
        })
        .transpose()?;

    // Only an empty database can acquire the current marker without conversion.
    let Some(current_version_str) = current_version_str else {
        if has_existing_relations {
            return Err(
                "Existing database has no format version; export it with a compatible mooR version and import it into a fresh database"
                    .to_string(),
            );
        }
        info!("Database at {db_path:?} has no version marker; marking as {CURRENT_DB_VERSION}");
        sequences_keyspace
            .insert(VERSION_KEY, CURRENT_DB_VERSION.as_bytes())
            .map_err(|e| format!("Failed to write version marker: {e}"))?;
        return Ok(());
    };

    drop(sequences_keyspace);
    drop(database);

    let current_version = Version::parse(&current_version_str).map_err(|error| {
        format!("Database format marker {current_version_str:?} is not a semantic version: {error}")
    })?;
    let expected_version =
        Version::parse(CURRENT_DB_VERSION).expect("CURRENT_DB_VERSION must be a semantic version");

    info!("Database version marker: {current_version}, current: {expected_version}");
    if current_version == expected_version {
        info!("Database at {db_path:?} already uses format {CURRENT_DB_VERSION}");
        return Ok(());
    }

    Err(format!(
        "Database format {current_version} cannot be opened as {expected_version}; export it with a compatible mooR version and import it into a fresh database"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use fjall::{Database, KeyspaceCreateOptions};
    use tempfile::TempDir;

    fn read_version(path: &Path) -> String {
        let database = Database::builder(path).open().unwrap();
        let sequences = database
            .keyspace("sequences", KeyspaceCreateOptions::default)
            .unwrap();
        String::from_utf8(sequences.get(VERSION_KEY).unwrap().unwrap().to_vec()).unwrap()
    }

    #[test]
    fn fresh_database_gets_current_format_marker() {
        let tmpdir = TempDir::new().unwrap();
        fjall_check_format(tmpdir.path()).unwrap();
        assert_eq!(read_version(tmpdir.path()), "2.0.0");

        fjall_check_format(tmpdir.path()).unwrap();
        assert_eq!(read_version(tmpdir.path()), "2.0.0");
    }

    #[test]
    fn missing_database_path_gets_current_format_marker() {
        let tmpdir = TempDir::new().unwrap();
        let path = tmpdir.path().join("new.db");
        assert!(!path.exists());

        fjall_check_format(&path).unwrap();
        assert_eq!(read_version(&path), "2.0.0");
    }

    #[test]
    fn incompatible_format_requires_export_and_import() {
        let tmpdir = TempDir::new().unwrap();
        fjall_check_format(tmpdir.path()).unwrap();
        let database = Database::builder(tmpdir.path()).open().unwrap();
        let sequences = database
            .keyspace("sequences", KeyspaceCreateOptions::default)
            .unwrap();
        sequences.insert(VERSION_KEY, b"1.0.0").unwrap();
        drop(sequences);
        drop(database);

        let error = fjall_check_format(tmpdir.path()).unwrap_err();
        assert!(error.contains("export it with a compatible mooR version"));
        assert_eq!(read_version(tmpdir.path()), "1.0.0");
    }

    #[test]
    fn malformed_format_marker_is_rejected() {
        let tmpdir = TempDir::new().unwrap();
        fjall_check_format(tmpdir.path()).unwrap();
        let database = Database::builder(tmpdir.path()).open().unwrap();
        let sequences = database
            .keyspace("sequences", KeyspaceCreateOptions::default)
            .unwrap();
        sequences.insert(VERSION_KEY, b"release-2.0.0").unwrap();
        drop(sequences);
        drop(database);

        let error = fjall_check_format(tmpdir.path()).unwrap_err();
        assert!(error.contains("is not a semantic version"));
    }

    #[test]
    fn unversioned_existing_database_is_not_relabeled() {
        let tmpdir = TempDir::new().unwrap();
        let database = Database::builder(tmpdir.path()).open().unwrap();
        database
            .keyspace("object_location", KeyspaceCreateOptions::default)
            .unwrap();
        drop(database);

        let error = fjall_check_format(tmpdir.path()).unwrap_err();
        assert!(error.contains("Existing database has no format version"));
    }
}
