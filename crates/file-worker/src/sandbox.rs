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
//

//! Path containment for the file worker.
//!
//! Every request path is interpreted relative to an open directory capability. The capability
//! keeps path lookup confined during the filesystem operation, including when directories or
//! symlinks are changed concurrently. Error messages only mention the caller-supplied relative path
//! so host layout is not leaked back to untrusted callers.

use cap_std::{
    ambient_authority,
    fs::{Dir, Metadata, OpenOptions, ReadDir},
};
use std::{
    fmt,
    fs::File,
    io,
    path::{Component, Path, PathBuf},
};

/// An open sandbox root used as the capability for all worker filesystem access.
#[derive(Debug)]
pub struct Sandbox {
    root: PathBuf,
    dir: Dir,
}

#[derive(Debug)]
pub enum SandboxError {
    /// The sandbox root itself could not be opened.
    Root(String),
    /// The request path was rejected before touching the filesystem.
    Rejected { path: String, reason: String },
}

impl fmt::Display for SandboxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SandboxError::Root(msg) => write!(f, "invalid sandbox root: {msg}"),
            SandboxError::Rejected { path, reason } => {
                write!(f, "path {path:?} rejected: {reason}")
            }
        }
    }
}

impl std::error::Error for SandboxError {}

impl Sandbox {
    /// Open `path` as the sandbox root and retain its directory capability.
    pub fn new(path: &Path) -> Result<Self, SandboxError> {
        let root = path
            .canonicalize()
            .map_err(|e| SandboxError::Root(format!("{}: {e}", path.display())))?;
        if !root.is_dir() {
            return Err(SandboxError::Root(format!(
                "{} is not a directory",
                root.display()
            )));
        }
        let dir = Dir::open_ambient_dir(&root, ambient_authority())
            .map_err(|e| SandboxError::Root(format!("{}: {e}", root.display())))?;
        Ok(Self { root, dir })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn open(&self, rel: &str) -> Result<File, SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .open(path)
            .map(cap_std::fs::File::into_std)
            .map_err(|e| io_error(rel, "open", e))
    }

    pub fn open_with(&self, rel: &str, options: &OpenOptions) -> Result<File, SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .open_with(path, options)
            .map(cap_std::fs::File::into_std)
            .map_err(|e| io_error(rel, "open", e))
    }

    pub fn remove_file(&self, rel: &str) -> Result<(), SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .remove_file(path)
            .map_err(|e| io_error(rel, "delete", e))
    }

    pub fn create_dir_all(&self, rel: &str) -> Result<(), SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .create_dir_all(path)
            .map_err(|e| io_error(rel, "create directory", e))
    }

    pub fn remove_dir(&self, rel: &str) -> Result<(), SandboxError> {
        let path = relative_path(rel)?;
        if path == Path::new(".") {
            return Err(rejected(rel, "the sandbox root may not be removed"));
        }
        self.dir
            .remove_dir(path)
            .map_err(|e| io_error(rel, "remove directory", e))
    }

    pub fn symlink_metadata(&self, rel: &str) -> Result<Metadata, SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .symlink_metadata(path)
            .map_err(|e| io_error(rel, "stat", e))
    }

    pub fn read_dir(&self, rel: &str) -> Result<ReadDir, SandboxError> {
        let path = relative_path(rel)?;
        self.dir
            .read_dir(path)
            .map_err(|e| io_error(rel, "list directory", e))
    }
}

fn relative_path(rel: &str) -> Result<PathBuf, SandboxError> {
    let mut path = PathBuf::new();
    for component in Path::new(rel).components() {
        match component {
            Component::Prefix(_) | Component::RootDir => {
                return Err(rejected(rel, "absolute paths are not permitted"));
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if !path.pop() {
                    return Err(rejected(rel, "path escapes the sandbox root"));
                }
            }
            Component::Normal(name) => path.push(name),
        }
    }
    if path.as_os_str().is_empty() {
        path.push(".");
    }
    Ok(path)
}

fn io_error(rel: &str, operation: &str, error: io::Error) -> SandboxError {
    rejected(rel, &format!("could not {operation}: {error}"))
}

fn rejected(rel: &str, reason: &str) -> SandboxError {
    SandboxError::Rejected {
        path: rel.to_string(),
        reason: reason.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, io::Read};

    fn sandbox() -> (tempfile::TempDir, Sandbox) {
        let dir = tempfile::tempdir().unwrap();
        let sandbox = Sandbox::new(dir.path()).unwrap();
        (dir, sandbox)
    }

    #[test]
    fn normalizes_nested_path() {
        assert_eq!(relative_path("a/b/../c.txt").unwrap(), Path::new("a/c.txt"));
    }

    #[test]
    fn empty_path_is_root() {
        assert_eq!(relative_path("").unwrap(), Path::new("."));
        assert_eq!(relative_path(".").unwrap(), Path::new("."));
    }

    #[test]
    fn rejects_absolute_paths() {
        assert!(relative_path("/etc/passwd").is_err());
    }

    #[test]
    fn rejects_parent_traversal() {
        assert!(relative_path("../secret").is_err());
        assert!(relative_path("a/../../secret").is_err());
    }

    #[test]
    #[cfg(unix)]
    fn rejects_symlink_escape() {
        let (dir, sandbox) = sandbox();
        let outside = tempfile::tempdir().unwrap();
        fs::write(outside.path().join("secret.txt"), b"top secret").unwrap();
        std::os::unix::fs::symlink(outside.path(), dir.path().join("escape")).unwrap();

        assert!(sandbox.open("escape/secret.txt").is_err());
        assert!(sandbox.open("escape").is_err());
    }

    #[test]
    #[cfg(unix)]
    fn allows_interior_symlink() {
        let (dir, sandbox) = sandbox();
        fs::create_dir(dir.path().join("real")).unwrap();
        fs::write(dir.path().join("real/file.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink("real", dir.path().join("link")).unwrap();

        let mut file = sandbox.open("link/file.txt").unwrap();
        let mut content = String::new();
        file.read_to_string(&mut content).unwrap();
        assert_eq!(content, "hello");
    }

    #[test]
    #[cfg(unix)]
    fn deleting_symlink_preserves_target() {
        let (dir, sandbox) = sandbox();
        fs::write(dir.path().join("target.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink("target.txt", dir.path().join("link.txt")).unwrap();

        sandbox.remove_file("link.txt").unwrap();
        assert!(!dir.path().join("link.txt").exists());
        assert_eq!(fs::read(dir.path().join("target.txt")).unwrap(), b"hello");
    }

    #[test]
    #[cfg(unix)]
    fn stat_reports_symlink() {
        let (dir, sandbox) = sandbox();
        fs::write(dir.path().join("target.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink("target.txt", dir.path().join("link.txt")).unwrap();

        let metadata = sandbox.symlink_metadata("link.txt").unwrap();
        assert!(metadata.file_type().is_symlink());
    }

    #[test]
    fn rejects_removing_root() {
        let (dir, sandbox) = sandbox();
        assert!(sandbox.remove_dir("").is_err());
        assert!(sandbox.remove_dir(".").is_err());
        assert!(sandbox.remove_dir("child/..").is_err());
        assert!(dir.path().is_dir());
    }
}
