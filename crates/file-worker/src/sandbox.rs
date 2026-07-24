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
//! Every request path is interpreted relative to a fixed sandbox root. Resolution rejects absolute
//! paths, `..` traversal that would climb above the root, and symlinks whose targets escape the
//! sandbox. Error messages only ever mention the caller-supplied relative path so host layout is
//! not leaked back to untrusted callers.

use std::{
    fmt,
    path::{Component, Path, PathBuf},
};

/// A resolved sandbox root. Constructed once at startup; all request paths are resolved against it.
#[derive(Debug, Clone)]
pub struct Sandbox {
    root: PathBuf,
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
    /// Open `dir` as the sandbox root, canonicalizing it and verifying it is a directory.
    pub fn new(dir: &Path) -> Result<Self, SandboxError> {
        let root = dir
            .canonicalize()
            .map_err(|e| SandboxError::Root(format!("{}: {e}", dir.display())))?;
        if !root.is_dir() {
            return Err(SandboxError::Root(format!(
                "{} is not a directory",
                root.display()
            )));
        }
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Resolve a caller-supplied relative path into an absolute path guaranteed to live inside the
    /// sandbox. The target need not exist (so `write`/`mkdir` can create it), but no part of the
    /// path may escape via `..` or symlinks.
    pub fn resolve(&self, rel: &str) -> Result<PathBuf, SandboxError> {
        let reject = |reason: &str| SandboxError::Rejected {
            path: rel.to_string(),
            reason: reason.to_string(),
        };

        // Lexically normalize, forbidding absolute components and traversal above the root.
        let mut parts: Vec<&std::ffi::OsStr> = Vec::new();
        for component in Path::new(rel).components() {
            match component {
                Component::Prefix(_) | Component::RootDir => {
                    return Err(reject("absolute paths are not permitted"));
                }
                Component::CurDir => {}
                Component::ParentDir => {
                    if parts.pop().is_none() {
                        return Err(reject("path escapes the sandbox root"));
                    }
                }
                Component::Normal(name) => parts.push(name),
            }
        }

        let candidate = {
            let mut p = self.root.clone();
            p.extend(&parts);
            p
        };

        // Canonicalize the deepest existing ancestor so any symlinks in the existing prefix are
        // resolved, then confirm the real path is still inside the root.
        let mut existing = candidate.as_path();
        loop {
            if existing.exists() {
                break;
            }
            match existing.parent() {
                Some(parent) => existing = parent,
                None => break,
            }
        }
        let canonical_existing = existing
            .canonicalize()
            .map_err(|e| reject(&format!("could not resolve path: {e}")))?;
        if !canonical_existing.starts_with(&self.root) {
            return Err(reject("path escapes the sandbox root"));
        }

        // Reattach the non-existing tail (new file/dir names) to the real ancestor. When the whole
        // path already exists the tail is empty and the canonicalized ancestor is the full path;
        // joining an empty tail would otherwise append a spurious trailing separator.
        let tail = candidate
            .strip_prefix(existing)
            .expect("existing is an ancestor of candidate");
        let resolved = if tail.as_os_str().is_empty() {
            canonical_existing
        } else {
            canonical_existing.join(tail)
        };

        // If the final target is itself a symlink, its (canonicalized) destination must also stay
        // inside the sandbox; dangling symlinks are refused outright.
        if let Ok(meta) = resolved.symlink_metadata()
            && meta.file_type().is_symlink()
        {
            let target = resolved
                .canonicalize()
                .map_err(|_| reject("refusing to follow a dangling symlink"))?;
            if !target.starts_with(&self.root) {
                return Err(reject("symlink target escapes the sandbox root"));
            }
        }

        Ok(resolved)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn sandbox() -> (tempfile::TempDir, Sandbox) {
        let dir = tempfile::tempdir().unwrap();
        let sandbox = Sandbox::new(dir.path()).unwrap();
        (dir, sandbox)
    }

    #[test]
    fn resolves_nested_path() {
        let (_dir, sandbox) = sandbox();
        let resolved = sandbox.resolve("a/b/c.txt").unwrap();
        assert!(resolved.starts_with(sandbox.root()));
        assert!(resolved.ends_with("a/b/c.txt"));
    }

    #[test]
    fn empty_path_is_root() {
        let (_dir, sandbox) = sandbox();
        assert_eq!(sandbox.resolve("").unwrap(), sandbox.root());
        assert_eq!(sandbox.resolve(".").unwrap(), sandbox.root());
    }

    #[test]
    fn rejects_absolute_paths() {
        let (_dir, sandbox) = sandbox();
        assert!(sandbox.resolve("/etc/passwd").is_err());
    }

    #[test]
    fn rejects_parent_traversal() {
        let (_dir, sandbox) = sandbox();
        assert!(sandbox.resolve("../secret").is_err());
        assert!(sandbox.resolve("a/../../secret").is_err());
    }

    #[test]
    fn allows_interior_parent_traversal() {
        let (_dir, sandbox) = sandbox();
        let resolved = sandbox.resolve("a/b/../c.txt").unwrap();
        assert!(resolved.ends_with("a/c.txt"));
    }

    #[test]
    #[cfg(unix)]
    fn rejects_symlink_escape() {
        let (dir, sandbox) = sandbox();
        let outside = tempfile::tempdir().unwrap();
        fs::write(outside.path().join("secret.txt"), b"top secret").unwrap();
        std::os::unix::fs::symlink(outside.path(), dir.path().join("escape")).unwrap();

        assert!(sandbox.resolve("escape/secret.txt").is_err());
        assert!(sandbox.resolve("escape").is_err());
    }

    #[test]
    #[cfg(unix)]
    fn allows_interior_symlink() {
        let (dir, sandbox) = sandbox();
        fs::create_dir(dir.path().join("real")).unwrap();
        fs::write(dir.path().join("real/file.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink(dir.path().join("real"), dir.path().join("link")).unwrap();

        let resolved = sandbox.resolve("link/file.txt").unwrap();
        assert!(resolved.starts_with(sandbox.root()));
    }
}
