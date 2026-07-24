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

//! Filesystem operations exposed by the worker.
//!
//! Requests take the shape `{operation, path, ...}` where `operation` is a symbol and `path` is a
//! sandbox-relative string. All paths are resolved through [`Sandbox`] before any I/O happens.

use std::{
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use cap_std::fs::{FileType, OpenOptions};
use moor_common::tasks::WorkerError;
use moor_var::{Obj, Symbol, Var, Variant, v_int, v_list_iter, v_map, v_str, v_string};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    task,
};
use tracing::info;
use uuid::Uuid;

use crate::sandbox::Sandbox;

fn err(msg: impl Into<String>) -> WorkerError {
    WorkerError::RequestError(msg.into())
}

async fn blocking<T, F>(operation: F) -> Result<T, WorkerError>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, WorkerError> + Send + 'static,
{
    task::spawn_blocking(operation)
        .await
        .map_err(|e| WorkerError::InternalError(format!("filesystem operation task failed: {e}")))?
}

/// Entry point wired into the worker loop. Dispatches on the operation symbol and enforces the
/// per-request timeout supplied via `worker_request` options.
pub async fn perform_file_request(
    sandbox: Arc<Sandbox>,
    _request_id: Uuid,
    _worker_type: Symbol,
    _perms: Obj,
    arguments: Vec<Var>,
    timeout: Option<Duration>,
) -> Result<Var, WorkerError> {
    let fut = dispatch(sandbox, arguments);
    match timeout {
        Some(timeout) => tokio::time::timeout(timeout, fut)
            .await
            .map_err(|_| err("file operation timed out"))?,
        None => fut.await,
    }
}

async fn dispatch(sandbox: Arc<Sandbox>, arguments: Vec<Var>) -> Result<Var, WorkerError> {
    let op = arguments
        .first()
        .ok_or_else(|| err("first argument must be an operation symbol"))?
        .as_symbol()
        .map_err(|_| err("first argument must be a symbol or string"))?;

    let op_name = op.as_string();
    match op_name.as_str() {
        "read" => read(&sandbox, &arguments).await,
        "write" => write(&sandbox, &arguments, false).await,
        "append" => write(&sandbox, &arguments, true).await,
        "delete" => delete(&sandbox, &arguments).await,
        "stat" => stat(&sandbox, &arguments).await,
        "line_count" => line_count(&sandbox, &arguments).await,
        "mkdir" => mkdir(&sandbox, &arguments).await,
        "rmdir" => rmdir(&sandbox, &arguments).await,
        "list" => list(&sandbox, &arguments).await,
        other => Err(err(format!("unknown operation {other:?}"))),
    }
}

fn path_arg(arguments: &[Var], idx: usize) -> Result<&str, WorkerError> {
    arguments
        .get(idx)
        .ok_or_else(|| err("a path argument is required"))?
        .as_string()
        .ok_or_else(|| err("path argument must be a string"))
}

/// Accept content as either a single string or a list of strings (joined with newlines).
fn content_arg(arguments: &[Var], idx: usize) -> Result<String, WorkerError> {
    let value = arguments
        .get(idx)
        .ok_or_else(|| err("a content argument is required"))?;
    match value.variant() {
        Variant::Str(s) => Ok(s.as_str().to_string()),
        Variant::List(list) => {
            let mut lines = Vec::with_capacity(list.len());
            for item in list.iter() {
                match item.variant() {
                    Variant::Str(s) => lines.push(s.as_str().to_string()),
                    _ => return Err(err("content list items must be strings")),
                }
            }
            Ok(lines.join("\n"))
        }
        _ => Err(err("content must be a string or a list of strings")),
    }
}

async fn read(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let rel_for_open = rel.clone();
    let sandbox = sandbox.clone();
    let file =
        blocking(move || sandbox.open(&rel_for_open).map_err(|e| err(e.to_string()))).await?;
    let file = tokio::fs::File::from_std(file);

    // Optional 1-based inclusive line range: {read, path, start_line, end_line}.
    if arguments.len() > 2 {
        let start = arguments[2]
            .as_integer()
            .ok_or_else(|| err("start_line must be an integer"))?;
        let end = arguments
            .get(3)
            .and_then(|v| v.as_integer())
            .unwrap_or(i64::MAX);
        if start < 1 {
            return Err(err("start_line must be >= 1"));
        }
        if end < start {
            return Err(err("end_line must be >= start_line"));
        }

        let mut lines = BufReader::new(file).lines();
        let mut out = Vec::new();
        let mut n: i64 = 0;
        while let Some(line) = lines
            .next_line()
            .await
            .map_err(|e| err(format!("could not read {rel:?}: {e}")))?
        {
            n += 1;
            if n > end {
                break;
            }
            if n >= start {
                out.push(v_string(line));
            }
        }
        return Ok(v_list_iter(out));
    }

    let mut content = String::new();
    BufReader::new(file)
        .read_to_string(&mut content)
        .await
        .map_err(|e| err(format!("could not read {rel:?}: {e}")))?;
    info!(path = rel.as_str(), "read");
    Ok(v_string(content))
}

async fn write(
    sandbox: &Arc<Sandbox>,
    arguments: &[Var],
    append: bool,
) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let content = content_arg(arguments, 2)?;

    let rel_for_open = rel.clone();
    let sandbox = sandbox.clone();
    let file = blocking(move || {
        let mut options = OpenOptions::new();
        options
            .write(true)
            .create(true)
            .append(append)
            .truncate(!append);
        sandbox
            .open_with(&rel_for_open, &options)
            .map_err(|e| err(e.to_string()))
    })
    .await?;
    let mut file = tokio::fs::File::from_std(file);
    file.write_all(content.as_bytes())
        .await
        .map_err(|e| err(format!("could not write {rel:?}: {e}")))?;
    file.flush()
        .await
        .map_err(|e| err(format!("could not flush {rel:?}: {e}")))?;

    info!(path = rel.as_str(), append, bytes = content.len(), "write");
    Ok(v_int(content.len() as i64))
}

async fn delete(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let rel_for_delete = rel.clone();
    let sandbox = sandbox.clone();
    blocking(move || {
        sandbox
            .remove_file(&rel_for_delete)
            .map_err(|e| err(e.to_string()))
    })
    .await?;
    info!(path = rel.as_str(), "delete");
    Ok(v_int(1))
}

async fn mkdir(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let rel_for_create = rel.clone();
    let sandbox = sandbox.clone();
    blocking(move || {
        sandbox
            .create_dir_all(&rel_for_create)
            .map_err(|e| err(e.to_string()))
    })
    .await?;
    info!(path = rel.as_str(), "mkdir");
    Ok(v_int(1))
}

async fn rmdir(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let rel_for_remove = rel.clone();
    let sandbox = sandbox.clone();
    // Only empty directories may be removed; recursive deletion is intentionally not supported.
    blocking(move || {
        sandbox
            .remove_dir(&rel_for_remove)
            .map_err(|e| err(e.to_string()))
    })
    .await?;
    info!(path = rel.as_str(), "rmdir");
    Ok(v_int(1))
}

async fn line_count(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let rel_for_open = rel.clone();
    let sandbox = sandbox.clone();
    let file =
        blocking(move || sandbox.open(&rel_for_open).map_err(|e| err(e.to_string()))).await?;
    let file = tokio::fs::File::from_std(file);
    let mut lines = BufReader::new(file).lines();
    let mut count: i64 = 0;
    while lines
        .next_line()
        .await
        .map_err(|e| err(format!("could not read {rel:?}: {e}")))?
        .is_some()
    {
        count += 1;
    }
    Ok(v_int(count))
}

async fn stat(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let sandbox = sandbox.clone();
    let meta = blocking(move || {
        sandbox
            .symlink_metadata(&rel)
            .map_err(|e| err(e.to_string()))
    })
    .await?;

    let mut pairs = vec![
        (v_str("type"), v_str(file_type_name(&meta.file_type()))),
        (v_str("size"), v_int(meta.len() as i64)),
        (
            v_str("readonly"),
            v_int(meta.permissions().readonly() as i64),
        ),
    ];

    #[cfg(unix)]
    {
        use cap_std::fs::PermissionsExt;
        let mode = meta.permissions().mode() & 0o7777;
        pairs.push((v_str("mode"), v_string(format!("{mode:o}"))));
    }

    push_time(
        &mut pairs,
        "modified",
        meta.modified().map(|time| time.into_std()).ok(),
    );
    push_time(
        &mut pairs,
        "created",
        meta.created().map(|time| time.into_std()).ok(),
    );
    push_time(
        &mut pairs,
        "accessed",
        meta.accessed().map(|time| time.into_std()).ok(),
    );

    Ok(v_map(&pairs))
}

async fn list(sandbox: &Arc<Sandbox>, arguments: &[Var]) -> Result<Var, WorkerError> {
    let rel = path_arg(arguments, 1)?.to_string();
    let sandbox = sandbox.clone();
    let entries = blocking(move || {
        let entries = sandbox.read_dir(&rel).map_err(|e| err(e.to_string()))?;
        let mut out = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|e| err(format!("could not read directory {rel:?}: {e}")))?;
            let name = entry.file_name().to_string_lossy().into_owned();
            let file_type = entry
                .file_type()
                .map_err(|e| err(format!("could not stat entry in {rel:?}: {e}")))?;
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            out.push((name, file_type, size));
        }
        Ok(out)
    })
    .await?;
    let out = entries.into_iter().map(|(name, file_type, size)| {
        v_map(&[
            (v_str("name"), v_string(name)),
            (v_str("type"), v_str(file_type_name(&file_type))),
            (v_str("size"), v_int(size as i64)),
        ])
    });
    Ok(v_list_iter(out))
}

fn file_type_name(file_type: &FileType) -> &'static str {
    if file_type.is_dir() {
        "directory"
    } else if file_type.is_symlink() {
        "symlink"
    } else {
        "file"
    }
}

fn push_time(pairs: &mut Vec<(Var, Var)>, key: &str, time: Option<SystemTime>) {
    if let Some(secs) = time
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
    {
        pairs.push((v_str(key), v_int(secs)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{v_list, v_str};

    fn setup() -> (tempfile::TempDir, Arc<Sandbox>) {
        let dir = tempfile::tempdir().unwrap();
        let sandbox = Arc::new(Sandbox::new(dir.path()).unwrap());
        (dir, sandbox)
    }

    async fn run(sandbox: &Arc<Sandbox>, args: Vec<Var>) -> Result<Var, WorkerError> {
        dispatch(sandbox.clone(), args).await
    }

    #[tokio::test]
    async fn write_then_read_roundtrip() {
        let (_dir, sandbox) = setup();
        run(
            &sandbox,
            vec![v_str("write"), v_str("notes.txt"), v_str("hello world")],
        )
        .await
        .unwrap();

        let read = run(&sandbox, vec![v_str("read"), v_str("notes.txt")])
            .await
            .unwrap();
        assert_eq!(read.as_string(), Some("hello world"));
    }

    #[tokio::test]
    async fn write_list_joins_with_newlines() {
        let (_dir, sandbox) = setup();
        run(
            &sandbox,
            vec![
                v_str("write"),
                v_str("multi.txt"),
                v_list(&[v_str("a"), v_str("b"), v_str("c")]),
            ],
        )
        .await
        .unwrap();
        let read = run(&sandbox, vec![v_str("read"), v_str("multi.txt")])
            .await
            .unwrap();
        assert_eq!(read.as_string(), Some("a\nb\nc"));
    }

    #[tokio::test]
    async fn read_line_range() {
        let (_dir, sandbox) = setup();
        run(
            &sandbox,
            vec![
                v_str("write"),
                v_str("lines.txt"),
                v_str("one\ntwo\nthree\nfour"),
            ],
        )
        .await
        .unwrap();

        let range = run(
            &sandbox,
            vec![v_str("read"), v_str("lines.txt"), v_int(2), v_int(3)],
        )
        .await
        .unwrap();
        let list = range.as_list().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].as_string(), Some("two"));
        assert_eq!(list[1].as_string(), Some("three"));
    }

    #[tokio::test]
    async fn append_adds_content() {
        let (_dir, sandbox) = setup();
        run(&sandbox, vec![v_str("write"), v_str("a.txt"), v_str("x")])
            .await
            .unwrap();
        run(&sandbox, vec![v_str("append"), v_str("a.txt"), v_str("y")])
            .await
            .unwrap();
        let read = run(&sandbox, vec![v_str("read"), v_str("a.txt")])
            .await
            .unwrap();
        assert_eq!(read.as_string(), Some("xy"));
    }

    #[tokio::test]
    async fn line_count_counts_lines() {
        let (_dir, sandbox) = setup();
        run(
            &sandbox,
            vec![v_str("write"), v_str("c.txt"), v_str("a\nb\nc")],
        )
        .await
        .unwrap();
        let count = run(&sandbox, vec![v_str("line_count"), v_str("c.txt")])
            .await
            .unwrap();
        assert_eq!(count.as_integer(), Some(3));
    }

    #[tokio::test]
    async fn stat_reports_fields() {
        let (_dir, sandbox) = setup();
        run(
            &sandbox,
            vec![v_str("write"), v_str("s.txt"), v_str("hello")],
        )
        .await
        .unwrap();
        let stat = run(&sandbox, vec![v_str("stat"), v_str("s.txt")])
            .await
            .unwrap();
        let map = stat.as_map().unwrap();
        let lookup = |key: &str| {
            map.iter()
                .find(|(k, _)| k.as_string() == Some(key))
                .map(|(_, v)| v)
        };
        assert_eq!(
            lookup("type").and_then(|v| v.as_string().map(str::to_string)),
            Some("file".to_string())
        );
        assert_eq!(lookup("size").and_then(|v| v.as_integer()), Some(5));
    }

    #[tokio::test]
    async fn mkdir_list_rmdir() {
        let (_dir, sandbox) = setup();
        run(&sandbox, vec![v_str("mkdir"), v_str("sub/inner")])
            .await
            .unwrap();
        run(
            &sandbox,
            vec![v_str("write"), v_str("sub/inner/f.txt"), v_str("z")],
        )
        .await
        .unwrap();

        let listing = run(&sandbox, vec![v_str("list"), v_str("sub/inner")])
            .await
            .unwrap();
        let list = listing.as_list().unwrap();
        assert_eq!(list.len(), 1);

        // Non-empty directory removal fails.
        assert!(
            run(&sandbox, vec![v_str("rmdir"), v_str("sub/inner")])
                .await
                .is_err()
        );

        run(&sandbox, vec![v_str("delete"), v_str("sub/inner/f.txt")])
            .await
            .unwrap();
        run(&sandbox, vec![v_str("rmdir"), v_str("sub/inner")])
            .await
            .unwrap();
    }

    #[tokio::test]
    #[cfg(unix)]
    async fn delete_removes_symlink_not_target() {
        let (dir, sandbox) = setup();
        std::fs::write(dir.path().join("target.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink("target.txt", dir.path().join("link.txt")).unwrap();

        run(&sandbox, vec![v_str("delete"), v_str("link.txt")])
            .await
            .unwrap();

        assert!(std::fs::symlink_metadata(dir.path().join("link.txt")).is_err());
        assert_eq!(
            std::fs::read(dir.path().join("target.txt")).unwrap(),
            b"hello"
        );
    }

    #[tokio::test]
    #[cfg(unix)]
    async fn stat_reports_symlink_type() {
        let (dir, sandbox) = setup();
        std::fs::write(dir.path().join("target.txt"), b"hello").unwrap();
        std::os::unix::fs::symlink("target.txt", dir.path().join("link.txt")).unwrap();

        let stat = run(&sandbox, vec![v_str("stat"), v_str("link.txt")])
            .await
            .unwrap();
        let has_symlink_type = stat.as_map().unwrap().iter().any(|(key, value)| {
            key.as_string() == Some("type") && value.as_string() == Some("symlink")
        });
        assert!(has_symlink_type);
    }

    #[tokio::test]
    async fn rmdir_rejects_sandbox_root() {
        let (dir, sandbox) = setup();

        assert!(
            run(&sandbox, vec![v_str("rmdir"), v_str(".")])
                .await
                .is_err()
        );
        assert!(
            run(&sandbox, vec![v_str("rmdir"), v_str("")])
                .await
                .is_err()
        );
        assert!(dir.path().is_dir());
    }

    #[tokio::test]
    async fn escape_is_rejected() {
        let (_dir, sandbox) = setup();
        assert!(
            run(&sandbox, vec![v_str("read"), v_str("../etc/passwd")])
                .await
                .is_err()
        );
    }
}
