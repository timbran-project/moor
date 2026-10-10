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

//! Git object retrieval. Repositories are bare, isolated, and disposable.

use crate::protocol::{Error, Operation, Request, Result, Revision, map, success};
use gix::{bstr::ByteSlice, objs::tree::EntryKind};
use moor_var::{Var, v_binary, v_bool, v_int, v_list, v_str};
use std::{path::Path, sync::atomic::AtomicBool};

fn failed() -> Error {
    Error::new("fetch_failed", "Git retrieval failed")
}
fn corrupt() -> Error {
    Error::new("invalid_repository", "Cannot read repository objects")
}
fn limit() -> Error {
    Error::new(
        "limit_exceeded",
        "Repository result exceeds the requested limits",
    )
}
fn oid(id: impl std::fmt::Display) -> Var {
    v_str(&format!("sha1:{id}"))
}
fn options() -> gix::open::Options {
    gix::open::Options::isolated().config_overrides([
        "http.followRedirects=false",
        "credential.helper=",
        "credential.interactive=false",
        "core.logAllRefUpdates=false",
        "pack.threads=1",
    ])
}

/// Retrieve objects from one remote revision without a working checkout.
/// The caller owns the directory and removes it even if this process is killed.
#[allow(clippy::result_large_err)] // The gix credential callback fixes its error type.
pub fn execute(request: &Request, directory: &Path) -> Result<Var> {
    if request.operation == Operation::Refs {
        return refs(request, directory);
    }
    let revision = match request.revision.as_ref().expect("validated revision") {
        Revision::Ref(name) | Revision::Commit(name) => name.clone(),
    };
    let repo = gix::ThreadSafeRepository::init_opts(
        directory,
        gix::create::Kind::Bare,
        gix::create::Options::default(),
        options(),
    )
    .map_err(|_| failed())?
    .to_thread_local();
    let remote = repo
        .remote_at(request.repository.as_str())
        .map_err(|_| failed())?
        .with_refspecs([revision.as_str()], gix::remote::Direction::Fetch)
        .map_err(|_| failed())?
        .with_fetch_tags(gix::remote::fetch::Tags::None);
    let budget = crate::transport::Budget::new(request.limits.max_fetch_bytes);
    let transport = gix::protocol::transport::client::blocking_io::http::connect_http(
        crate::transport::BoundedHttp::new(budget.clone()),
        gix::url::parse(request.repository.as_str()).map_err(|_| failed())?,
        gix::protocol::transport::Protocol::V2,
        false,
    );
    let auth = budget.authentication_required.clone();
    let connection = remote
        .to_connection_with_transport(transport)
        .with_credentials(move |_| {
            auth.store(true, std::sync::atomic::Ordering::Relaxed);
            Ok(None)
        });
    let prepare = connection
        .prepare_fetch(gix::progress::Discard, Default::default())
        .map_err(|_| budget.error())?;
    let id = prepare
        .ref_map()
        .mappings
        .first()
        .and_then(|mapping| mapping.remote.as_id())
        .map(ToOwned::to_owned)
        .ok_or_else(|| Error::new("revision_not_found", "Requested revision is not available"))?;
    prepare
        .with_shallow(gix::remote::fetch::Shallow::DepthAtRemote(
            std::num::NonZeroU32::new(1).unwrap(),
        ))
        .receive(gix::progress::Discard, &AtomicBool::new(false))
        .map_err(|_| budget.error())?;
    let commit = repo
        .find_object(id)
        .map_err(|_| Error::new("revision_not_found", "Requested commit is not available"))?
        .peel_to_kind(gix::objs::Kind::Commit)
        .map_err(|_| Error::new("wrong_object_type", "Revision does not identify a commit"))?
        .into_commit();
    let commit_id = commit.id;
    let tree = commit.tree().map_err(|_| corrupt())?;
    let mut budget = Budget {
        entries: 0,
        bytes: 0,
        request,
    };
    if request.operation == Operation::Read {
        let entry = tree
            .lookup_entry_by_path(&request.path)
            .map_err(|_| corrupt())?
            .ok_or_else(|| Error::new("path_not_found", "Requested path does not exist"))?;
        if !matches!(
            entry.mode().kind(),
            EntryKind::Blob | EntryKind::BlobExecutable | EntryKind::Link
        ) {
            return Err(Error::new(
                "wrong_object_type",
                "Read requires a file or symlink",
            ));
        }
        let value = budget.entry(
            &repo,
            entry.object_id(),
            entry.mode().kind(),
            &request.path,
            true,
        )?;
        return Ok(success(map(&[
            ("commit", oid(commit_id)),
            ("entry", value),
        ])));
    }
    let tree = if request.path.is_empty() {
        tree
    } else {
        let entry = tree
            .lookup_entry_by_path(&request.path)
            .map_err(|_| corrupt())?
            .ok_or_else(|| Error::new("path_not_found", "Requested path does not exist"))?;
        if entry.mode().kind() != EntryKind::Tree {
            return Err(Error::new(
                "wrong_object_type",
                "Requested path must be a directory",
            ));
        }
        entry
            .object()
            .map_err(|_| corrupt())?
            .try_into_tree()
            .map_err(|_| corrupt())?
    };
    let subtree_id = tree.id;
    // Use an explicit stack so repository depth cannot consume the Rust call stack.
    let mut pending = vec![(String::new(), tree.id)];
    let mut entries = Vec::new();
    while let Some((prefix, tree_id)) = pending.pop() {
        let tree = repo
            .find_object(tree_id)
            .map_err(|_| corrupt())?
            .try_into_tree()
            .map_err(|_| corrupt())?;
        for entry in tree.iter() {
            let entry = entry.map_err(|_| corrupt())?;
            let name = entry
                .filename()
                .to_str()
                .map_err(|_| Error::new("unsupported_path", "Repository path is not UTF-8"))?;
            if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', '\0']) {
                return Err(Error::new(
                    "unsupported_path",
                    "Repository contains an invalid path component",
                ));
            }
            let path = if prefix.is_empty() {
                name.to_owned()
            } else {
                format!("{prefix}/{name}")
            };
            if path.len() > 4096 {
                return Err(Error::new(
                    "unsupported_path",
                    "Repository path exceeds 4096 bytes",
                ));
            }
            let kind = entry.mode().kind();
            let value = budget.entry(
                &repo,
                entry.object_id(),
                kind,
                &path,
                request.operation == Operation::Snapshot,
            )?;
            if kind == EntryKind::Tree && request.recursive {
                pending.push((path.clone(), entry.object_id()));
            }
            entries.push((path, value));
        }
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(success(map(&[
        ("commit", oid(commit_id)),
        ("tree", oid(subtree_id)),
        ("path", v_str(&request.path)),
        (
            "entries",
            v_list(&entries.into_iter().map(|(_, v)| v).collect::<Vec<_>>()),
        ),
    ])))
}

struct Budget<'a> {
    entries: usize,
    bytes: usize,
    request: &'a Request,
}
impl Budget<'_> {
    fn entry(
        &mut self,
        repo: &gix::Repository,
        id: gix::ObjectId,
        kind: EntryKind,
        path: &str,
        contents: bool,
    ) -> Result<Var> {
        self.entries += 1;
        if self.entries > self.request.limits.max_entries {
            return Err(limit());
        }
        let mut fields = vec![
            ("path", v_str(path)),
            ("oid", oid(id)),
            (
                "kind",
                v_str(match kind {
                    EntryKind::Tree => "directory",
                    EntryKind::Commit => "submodule",
                    EntryKind::Link => "symlink",
                    _ => "file",
                }),
            ),
        ];
        if matches!(
            kind,
            EntryKind::Blob | EntryKind::BlobExecutable | EntryKind::Link
        ) {
            let header = repo.find_header(id).map_err(|_| corrupt())?;
            if header.kind() != gix::objs::Kind::Blob {
                return Err(corrupt());
            }
            let size = header.size();
            fields.push(("size", v_int(i64::try_from(size).map_err(|_| limit())?)));
            if kind != EntryKind::Link {
                fields.push(("executable", v_bool(kind == EntryKind::BlobExecutable)));
            }
            if contents {
                if size > self.request.limits.max_file_bytes as u64 {
                    return Err(limit());
                }
                self.bytes = self.bytes.checked_add(size as usize).ok_or_else(limit)?;
                if self.bytes > self.request.limits.max_total_bytes {
                    return Err(limit());
                }
                let object = repo.find_object(id).map_err(|_| corrupt())?;
                fields.push(("content", v_binary(object.data.clone())));
            }
        }
        Ok(map(&fields))
    }
}

#[allow(clippy::result_large_err)] // The gix credential callback fixes its error type.
fn refs(request: &Request, directory: &Path) -> Result<Var> {
    let repo = gix::ThreadSafeRepository::init_opts(
        directory,
        gix::create::Kind::Bare,
        gix::create::Options::default(),
        options(),
    )
    .map_err(|_| failed())?
    .to_thread_local();
    let remote = repo
        .remote_at(request.repository.as_str())
        .map_err(|_| failed())?
        .with_refspecs(
            ["refs/heads/*:refs/heads/*", "refs/tags/*:refs/tags/*"],
            gix::remote::Direction::Fetch,
        )
        .map_err(|_| failed())?;
    let budget = crate::transport::Budget::new(request.limits.max_fetch_bytes);
    let transport = gix::protocol::transport::client::blocking_io::http::connect_http(
        crate::transport::BoundedHttp::new(budget.clone()),
        gix::url::parse(request.repository.as_str()).map_err(|_| failed())?,
        gix::protocol::transport::Protocol::V2,
        false,
    );
    let auth = budget.authentication_required.clone();
    let connection = remote
        .to_connection_with_transport(transport)
        .with_credentials(move |_| {
            auth.store(true, std::sync::atomic::Ordering::Relaxed);
            Ok(None)
        });
    let (refs, _) = connection
        .ref_map(gix::progress::Discard, Default::default())
        .map_err(|_| budget.error())?;
    let mut entries = Vec::new();
    for reference in refs.remote_refs {
        let (name, direct, peeled) = reference.unpack();
        let name = name
            .to_str()
            .map_err(|_| Error::new("unsupported_path", "Ref name is not UTF-8"))?;
        if !(name.starts_with("refs/heads/") || name.starts_with("refs/tags/")) {
            continue;
        }
        if name.len() > 4096 || entries.len() >= request.limits.max_entries {
            return Err(limit());
        }
        let Some(direct) = direct else {
            continue;
        };
        let mut fields = vec![("name", v_str(name)), ("oid", oid(direct))];
        if let Some(peeled) = peeled {
            fields.push(("peeled", oid(peeled)));
        }
        entries.push((name.to_owned(), map(&fields)));
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(success(map(&[(
        "refs",
        v_list(&entries.into_iter().map(|(_, v)| v).collect::<Vec<_>>()),
    )])))
}
