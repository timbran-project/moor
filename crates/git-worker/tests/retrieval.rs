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

//! Exercise the public protocol against a real local Git smart-HTTP server.
use moor_git_worker::{
    job::Executor,
    protocol::{Limits, map},
};
use moor_var::{Associative, Var, v_bool, v_int, v_str};
use std::{
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};
use tiny_http::{Header, Response, Server, StatusCode};

fn git(directory: &Path, arguments: &[&str]) -> String {
    let output = Command::new("git")
        .current_dir(directory)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .args([
            "-c",
            "user.name=Worker Test",
            "-c",
            "user.email=worker@example.invalid",
        ])
        .args(arguments)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {arguments:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap().trim().to_owned()
}
struct Fixture {
    root: tempfile::TempDir,
    url: String,
    first: String,
    second: String,
    stop: Arc<AtomicBool>,
    server: Option<thread::JoinHandle<()>>,
}
impl Fixture {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let repo = root.path().join("repo.git");
        std::fs::create_dir(&repo).unwrap();
        git(&repo, &["init", "-b", "main"]);
        std::fs::create_dir(repo.join("sub")).unwrap();
        std::fs::write(repo.join("sub/file.txt"), b"first\r\n").unwrap();
        std::fs::write(repo.join("sub/binary"), [0, 255, 13, 10]).unwrap();
        std::os::unix::fs::symlink("../../outside", repo.join("sub/link")).unwrap();
        std::fs::write(repo.join("run"), "#!/bin/sh\n").unwrap();
        git(&repo, &["add", "."]);
        git(&repo, &["update-index", "--chmod=+x", "run"]);
        git(&repo, &["commit", "-m", "first"]);
        let first = git(&repo, &["rev-parse", "HEAD"]);
        git(&repo, &["tag", "-a", "v1", "-m", "first tag"]);
        // A gitlink need not have a corresponding checkout or .gitmodules file.
        git(
            &repo,
            &[
                "update-index",
                "--add",
                "--cacheinfo",
                &format!("160000,{first},sub/module"),
            ],
        );
        std::fs::write(repo.join("sub/file.txt"), "second\n").unwrap();
        git(&repo, &["add", "sub/file.txt"]);
        git(&repo, &["commit", "-m", "second"]);
        let second = git(&repo, &["rev-parse", "HEAD"]);
        let server = Server::http("127.0.0.1:0").unwrap();
        let url = format!("http://{}/repo.git", server.server_addr());
        let stop = Arc::new(AtomicBool::new(false));
        let stopped = stop.clone();
        let project_root = root.path().to_owned();
        let server = thread::spawn(move || {
            while !stopped.load(Ordering::Relaxed) {
                let Some(mut request) = server.recv_timeout(Duration::from_millis(20)).unwrap()
                else {
                    continue;
                };
                let (path, query) = request.url().split_once('?').unwrap_or((request.url(), ""));
                let mut child = Command::new("git");
                child
                    .arg("http-backend")
                    .env("GIT_CONFIG_NOSYSTEM", "1")
                    .env("GIT_CONFIG_GLOBAL", "/dev/null")
                    .env("GIT_PROJECT_ROOT", &project_root)
                    .env("GIT_HTTP_EXPORT_ALL", "1")
                    .env("PATH_INFO", path)
                    .env("QUERY_STRING", query)
                    .env("REQUEST_METHOD", request.method().as_str());
                for header in request.headers() {
                    if header.field.equiv("Content-Type") {
                        child.env("CONTENT_TYPE", header.value.as_str());
                    }
                    if header.field.equiv("Git-Protocol") {
                        child.env("HTTP_GIT_PROTOCOL", header.value.as_str());
                    }
                }
                let mut body = Vec::new();
                request.as_reader().read_to_end(&mut body).unwrap();
                child.env("CONTENT_LENGTH", body.len().to_string());
                let mut child = child
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
                    .unwrap();
                child.stdin.take().unwrap().write_all(&body).unwrap();
                let output = child.wait_with_output().unwrap();
                let split = output
                    .stdout
                    .windows(4)
                    .position(|w| w == b"\r\n\r\n")
                    .unwrap();
                let mut response = Response::from_data(output.stdout[split + 4..].to_vec());
                for line in String::from_utf8_lossy(&output.stdout[..split]).lines() {
                    let (key, value) = line.split_once(':').unwrap();
                    if key == "Status" {
                        response = response.with_status_code(StatusCode(
                            value.trim().split(' ').next().unwrap().parse().unwrap(),
                        ));
                    } else {
                        response.add_header(Header::from_bytes(key, value.trim()).unwrap());
                    }
                }
                let _ = request.respond(response);
            }
        });
        Self {
            root,
            url,
            first,
            second,
            stop,
            server: Some(server),
        }
    }
    fn executor(&self, limits: Limits) -> Executor {
        Executor::new(
            PathBuf::from(env!("CARGO_BIN_EXE_moor-git-worker")),
            self.root.path().join("jobs"),
            limits,
            2,
        )
        .unwrap()
    }
    fn request(&self, op: &str, revision: Var, path: &str) -> Vec<Var> {
        vec![
            v_str(op),
            map(&[
                ("schema", v_int(1)),
                ("repository", v_str(&self.url)),
                ("revision", revision),
                ("path", v_str(path)),
            ]),
        ]
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        self.server.take().unwrap().join().unwrap();
    }
}
fn field(value: &Var, name: &str) -> Var {
    value.as_map().unwrap().get(&v_str(name)).unwrap()
}
fn result(value: Var) -> Var {
    assert_eq!(field(&value, "ok"), v_bool(true), "{value:?}");
    field(&value, "result")
}
fn ref_revision(name: &str) -> Var {
    map(&[("ref", v_str(name))])
}
fn commit_revision(id: &str) -> Var {
    map(&[("commit", v_str(&format!("sha1:{id}")))])
}
fn entry(entries: &Var, name: &str) -> Var {
    entries
        .as_list()
        .unwrap()
        .iter()
        .find(|e| field(e, "path") == v_str(name))
        .unwrap()
}
#[tokio::test]
async fn snapshot_is_pinned_and_preserves_git_entry_types() {
    let fixture = Fixture::new();
    let executor = fixture.executor(Limits::default());
    let snapshot = result(
        executor
            .perform(
                fixture.request("snapshot", ref_revision("refs/heads/main"), ""),
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        field(&snapshot, "commit"),
        v_str(&format!("sha1:{}", fixture.second))
    );
    let entries = field(&snapshot, "entries");
    assert_eq!(
        field(&entry(&entries, "sub/binary"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        &[0, 255, 13, 10]
    );
    assert_eq!(
        field(&entry(&entries, "sub/link"), "kind"),
        v_str("symlink")
    );
    assert_eq!(
        field(&entry(&entries, "sub/link"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        b"../../outside"
    );
    assert_eq!(
        field(&entry(&entries, "sub/module"), "kind"),
        v_str("submodule")
    );
    assert_eq!(field(&entry(&entries, "run"), "executable"), v_bool(true));
    let read = result(
        executor
            .perform(
                fixture.request("read", commit_revision(&fixture.first), "sub/file.txt"),
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        field(&field(&read, "entry"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        b"first\r\n"
    );
    let tag = result(
        executor
            .perform(
                fixture.request("snapshot", ref_revision("refs/tags/v1"), "sub"),
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        field(&tag, "commit"),
        v_str(&format!("sha1:{}", fixture.first))
    );
    assert_eq!(
        field(&entry(&field(&tag, "entries"), "file.txt"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        b"first\r\n"
    );
    assert_eq!(
        std::fs::read_dir(fixture.root.path().join("jobs"))
            .unwrap()
            .count(),
        0
    );
}
#[tokio::test]
async fn refs_tree_and_application_failures() {
    let fixture = Fixture::new();
    let executor = fixture.executor(Limits::default());
    let refs = result(
        executor
            .perform(
                vec![
                    v_str("refs"),
                    map(&[("schema", v_int(1)), ("repository", v_str(&fixture.url))]),
                ],
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(field(&refs, "refs").as_list().unwrap().len(), 2);
    let advertised = field(&refs, "refs");
    let advertised = advertised.as_list().unwrap();
    assert_eq!(field(&advertised[0], "name"), v_str("refs/heads/main"));
    assert_eq!(
        field(&advertised[0], "oid"),
        v_str(&format!("sha1:{}", fixture.second))
    );
    assert_eq!(field(&advertised[1], "name"), v_str("refs/tags/v1"));
    assert_eq!(
        field(&advertised[1], "peeled"),
        v_str(&format!("sha1:{}", fixture.first))
    );

    let tree = result(
        executor
            .perform(
                fixture.request("tree", ref_revision("refs/heads/main"), ""),
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(field(&tree, "entries").as_list().unwrap().len(), 2);
    for (op, rev, path, code) in [
        ("read", "refs/heads/main", "absent", "path_not_found"),
        ("read", "refs/heads/main", "sub", "wrong_object_type"),
        ("snapshot", "refs/heads/absent", "", "revision_not_found"),
        ("snapshot", "refs/heads/main", "run", "wrong_object_type"),
    ] {
        let error = executor
            .perform(fixture.request(op, ref_revision(rev), path), None)
            .await
            .unwrap();
        assert_eq!(
            field(&field(&error, "error"), "code"),
            v_str(code),
            "{error:?}"
        );
    }
}
#[tokio::test]
async fn result_limits_fail_without_partial_success() {
    let fixture = Fixture::new();
    for limits in [
        Limits {
            max_entries: 1,
            ..Limits::default()
        },
        Limits {
            max_file_bytes: 2,
            ..Limits::default()
        },
        Limits {
            max_file_bytes: 8,
            max_total_bytes: 8,
            ..Limits::default()
        },
    ] {
        let executor = fixture.executor(limits);
        let value = executor
            .perform(
                fixture.request("snapshot", ref_revision("refs/heads/main"), "sub"),
                None,
            )
            .await
            .unwrap();
        assert_eq!(
            field(&field(&value, "error"), "code"),
            v_str("limit_exceeded"),
            "{value:?}"
        );
    }
}
#[tokio::test]
async fn timeout_kills_job_and_releases_slot_and_directory() {
    let root = tempfile::tempdir().unwrap();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/repo", listener.local_addr().unwrap());
    let executor = Executor::new(
        PathBuf::from(env!("CARGO_BIN_EXE_moor-git-worker")),
        root.path().join("jobs"),
        Limits::default(),
        1,
    )
    .unwrap();
    for _ in 0..2 {
        let value = executor
            .perform(
                vec![
                    v_str("refs"),
                    map(&[("schema", v_int(1)), ("repository", v_str(&url))]),
                ],
                Some(Duration::from_millis(100)),
            )
            .await;
        assert!(
            matches!(
                value,
                Err(moor_common::tasks::WorkerError::RequestTimedOut(_))
            ),
            "{value:?}"
        );
        assert_eq!(
            std::fs::read_dir(root.path().join("jobs")).unwrap().count(),
            0
        );
    }
}

#[tokio::test]
async fn download_limits_cover_ref_advertisements_and_pack_data() {
    let fixture = Fixture::new();
    let repo = fixture.root.path().join("repo.git");
    // Enough incompressible data to exceed the network limit while the requested subtree stays small.
    let mut state = 1u64;
    let bytes = (0..100_000)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state as u8
        })
        .collect::<Vec<_>>();
    std::fs::write(repo.join("large"), bytes).unwrap();
    git(&repo, &["add", "large"]);
    git(&repo, &["commit", "-m", "large file"]);
    let executor = fixture.executor(Limits {
        max_fetch_bytes: 4096,
        ..Limits::default()
    });
    let value = executor
        .perform(
            fixture.request("snapshot", ref_revision("refs/heads/main"), "sub"),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        field(&field(&value, "error"), "code"),
        v_str("limit_exceeded"),
        "{value:?}"
    );
    for i in 0..80 {
        git(&repo, &["tag", &format!("many-tags-{i:03}")]);
    }
    let value = executor
        .perform(
            vec![
                v_str("refs"),
                map(&[("schema", v_int(1)), ("repository", v_str(&fixture.url))]),
            ],
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        field(&field(&value, "error"), "code"),
        v_str("limit_exceeded"),
        "{value:?}"
    );
}

#[tokio::test]
async fn busy_and_shutdown_do_not_leave_jobs_running() {
    let root = tempfile::tempdir().unwrap();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/repo", listener.local_addr().unwrap());
    let executor = Arc::new(
        Executor::new(
            PathBuf::from(env!("CARGO_BIN_EXE_moor-git-worker")),
            root.path().join("jobs"),
            Limits::default(),
            1,
        )
        .unwrap(),
    );
    let request = vec![
        v_str("refs"),
        map(&[("schema", v_int(1)), ("repository", v_str(&url))]),
    ];
    let running = {
        let executor = executor.clone();
        let request = request.clone();
        tokio::spawn(async move { executor.perform(request, None).await })
    };
    // Wait for the child to connect, proving the slot is occupied.
    listener.set_nonblocking(true).unwrap();
    let _connection = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match listener.accept() {
                Ok(socket) => break socket,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    tokio::time::sleep(Duration::from_millis(5)).await
                }
                Err(e) => panic!("{e}"),
            }
        }
    })
    .await
    .unwrap();
    let busy = executor.perform(request.clone(), None).await.unwrap();
    assert_eq!(field(&field(&busy, "error"), "code"), v_str("busy"));
    executor.shutdown().await;
    assert!(matches!(
        running.await.unwrap(),
        Err(moor_common::tasks::WorkerError::WorkerDetached(_))
    ));
    assert!(matches!(
        executor.perform(request, None).await,
        Err(moor_common::tasks::WorkerError::WorkerDetached(_))
    ));
    assert_eq!(
        std::fs::read_dir(root.path().join("jobs")).unwrap().count(),
        0
    );
}

#[tokio::test]
async fn hostile_names_and_missing_objects_are_explicit_errors() {
    use std::os::unix::ffi::OsStringExt;
    let fixture = Fixture::new();
    let repo = fixture.root.path().join("repo.git");
    std::fs::write(
        repo.join(std::ffi::OsString::from_vec(vec![b'x', 255])),
        "bad name",
    )
    .unwrap();
    git(&repo, &["add", "."]);
    git(&repo, &["commit", "-m", "non UTF-8 path"]);
    let executor = fixture.executor(Limits::default());
    let value = executor
        .perform(
            fixture.request("tree", ref_revision("refs/heads/main"), ""),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        field(&field(&value, "error"), "code"),
        v_str("unsupported_path")
    );
    // Unrelated unsupported names do not prevent an explicit file read.
    let read = result(
        executor
            .perform(
                fixture.request("read", ref_revision("refs/heads/main"), "sub/file.txt"),
                None,
            )
            .await
            .unwrap(),
    );
    assert_eq!(
        field(&field(&read, "entry"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        b"second\n"
    );
    let value = executor
        .perform(
            fixture.request(
                "snapshot",
                commit_revision("1111111111111111111111111111111111111111"),
                "sub",
            ),
            None,
        )
        .await
        .unwrap();
    assert_eq!(field(&value, "ok"), v_bool(false));
}

#[tokio::test]
async fn authentication_and_redirects_do_not_fetch_unexpected_content() {
    for (status, code) in [(401, "authentication_required"), (302, "fetch_failed")] {
        let root = tempfile::tempdir().unwrap();
        let server = Server::http("127.0.0.1:0").unwrap();
        let url = format!("http://{}/repo", server.server_addr());
        let redirect_target = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        redirect_target.set_nonblocking(true).unwrap();
        let location = format!("http://{}/different", redirect_target.local_addr().unwrap());
        let responder = thread::spawn(move || {
            let request = server
                .recv_timeout(Duration::from_secs(5))
                .unwrap()
                .expect("HTTP request");
            let response = Response::empty(StatusCode(status))
                .with_header(Header::from_bytes("Location", location).unwrap())
                .with_header(Header::from_bytes("WWW-Authenticate", "Basic realm=git").unwrap());
            request.respond(response).unwrap();
        });
        let executor = Executor::new(
            PathBuf::from(env!("CARGO_BIN_EXE_moor-git-worker")),
            root.path().join("jobs"),
            Limits::default(),
            1,
        )
        .unwrap();
        let value = executor
            .perform(
                vec![
                    v_str("refs"),
                    map(&[("schema", v_int(1)), ("repository", v_str(&url))]),
                ],
                None,
            )
            .await
            .unwrap();
        responder.join().unwrap();
        assert_eq!(
            field(&field(&value, "error"), "code"),
            v_str(code),
            "{value:?}"
        );
        assert!(
            matches!(redirect_target.accept(), Err(e) if e.kind() == std::io::ErrorKind::WouldBlock)
        );
    }
}

/// Verify registration, dispatch, and binary results through the existing worker wire protocol.
#[test]
fn standalone_worker_round_trips_a_git_read_over_ipc() {
    use moor_runtime_api::{WORKER_BROADCAST_TOPIC, mk_worker_ack_reply, mk_worker_request_msg};
    use moor_schema::{
        convert::{var_from_flatbuffer_ref, var_to_flatbuffer},
        rpc,
    };
    use planus::ReadAsRoot;
    let fixture = Fixture::new();
    let context = r0z::Context::new();
    let responses = context.socket(r0z::REP).unwrap();
    responses.set_rcvtimeo(10000).unwrap();
    responses.set_sndtimeo(10000).unwrap();
    responses.set_linger(0).unwrap();
    let events = context.socket(r0z::XPUB).unwrap();
    events.set_rcvtimeo(10000).unwrap();
    events.set_linger(0).unwrap();
    let rpc_url = format!("ipc://{}/responses", fixture.root.path().display());
    let event_url = format!("ipc://{}/events", fixture.root.path().display());
    responses.bind(&rpc_url).unwrap();
    events.bind(&event_url).unwrap();
    struct Process(std::process::Child);
    impl Drop for Process {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    let mut worker = Process(
        Command::new(env!("CARGO_BIN_EXE_moor-git-worker"))
            .args([
                "--rpc-address",
                &rpc_url,
                "--workers-response-address",
                &rpc_url,
                "--workers-request-address",
                &event_url,
            ])
            .arg("--work-dir")
            .arg(fixture.root.path().join("wire-jobs"))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap(),
    );
    let attach = responses.recv_multipart(0).unwrap();
    let id = uuid::Uuid::from_slice(&attach[0]).unwrap();
    let message = rpc::WorkerToDaemonMessageRef::read_as_root(&attach[1]).unwrap();
    let rpc::WorkerToDaemonMessageUnionRef::AttachWorker(attach) = message.message().unwrap()
    else {
        panic!("Expected attachment");
    };
    assert_eq!(attach.worker_type().unwrap().value().unwrap(), "git");
    let mut builder = planus::Builder::new();
    responses
        .send(builder.finish(mk_worker_ack_reply(), None), 0)
        .unwrap();
    // XPUB confirms subscription before dispatch; there is no timing-dependent sleep.
    let subscription = events.recv_bytes(0).unwrap();
    assert_eq!(subscription[0], 1);
    assert_eq!(&subscription[1..], WORKER_BROADCAST_TOPIC);
    let request_id = uuid::Uuid::new_v4();
    let request = fixture
        .request("read", commit_revision(&fixture.first), "sub/binary")
        .iter()
        .map(|value| var_to_flatbuffer(value).unwrap())
        .collect();
    let request = mk_worker_request_msg(id, request_id, &moor_var::SYSTEM_OBJECT, request, 5000);
    let mut builder = planus::Builder::new();
    events
        .send_multipart([WORKER_BROADCAST_TOPIC, builder.finish(&request, None)], 0)
        .unwrap();
    let reply = responses.recv_multipart(0).unwrap();
    let message = rpc::WorkerToDaemonMessageRef::read_as_root(&reply[1]).unwrap();
    let rpc::WorkerToDaemonMessageUnionRef::RequestResult(reply) = message.message().unwrap()
    else {
        panic!("Expected result");
    };
    let value = result(var_from_flatbuffer_ref(reply.result().unwrap()).unwrap());
    assert_eq!(
        field(&field(&value, "entry"), "content")
            .as_binary()
            .unwrap()
            .as_bytes(),
        &[0, 255, 13, 10]
    );
    let mut builder = planus::Builder::new();
    responses
        .send(builder.finish(mk_worker_ack_reply(), None), 0)
        .unwrap();
    // SAFETY: this is the owned, still-running worker child, not an arbitrary host process.
    assert_eq!(
        unsafe { libc::kill(worker.0.id() as i32, libc::SIGTERM) },
        0
    );
    let start = std::time::Instant::now();
    loop {
        if let Some(status) = worker.0.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "Worker did not stop"
        );
        thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(
        std::fs::read_dir(fixture.root.path().join("wire-jobs"))
            .unwrap()
            .count(),
        0
    );
}

#[tokio::test]
#[ignore = "requires access to GitHub; local smart-HTTP tests run by default"]
async fn public_https_smoke() {
    let root = tempfile::tempdir().unwrap();
    let executor = Executor::new(
        PathBuf::from(env!("CARGO_BIN_EXE_moor-git-worker")),
        root.path().join("jobs"),
        Limits::default(),
        1,
    )
    .unwrap();
    let value = result(
        executor
            .perform(
                vec![
                    v_str("read"),
                    map(&[
                        ("schema", v_int(1)),
                        (
                            "repository",
                            v_str("https://github.com/octocat/Hello-World.git"),
                        ),
                        ("revision", ref_revision("refs/heads/master")),
                        ("path", v_str("README")),
                    ]),
                ],
                None,
            )
            .await
            .unwrap(),
    );
    assert!(
        !field(&field(&value, "entry"), "content")
            .as_binary()
            .unwrap()
            .is_empty()
    );
}
