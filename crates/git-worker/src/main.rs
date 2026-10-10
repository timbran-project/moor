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

//! Standalone Git worker. Git requests run in bounded child processes.

use clap::Parser;
use clap_derive::Parser;
use moor_git_worker::{
    job::{Executor, child_main},
    protocol::Limits,
};
use moor_runtime_api::client_args::RpcClientArgs;
use moor_var::Symbol;
use std::{
    path::PathBuf,
    sync::{
        Arc, LazyLock,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};
use tokio::signal::unix::{SignalKind, signal};

static VERSION: LazyLock<String> = LazyLock::new(|| {
    format!(
        "{} (commit: {})",
        env!("CARGO_PKG_VERSION"),
        moor_common::build::short_commit()
    )
});
#[derive(Parser, Debug)]
#[command(version = VERSION.as_str(), about = "Read-only Git repository access for mooR")]
struct Args {
    #[command(flatten)]
    connection: RpcClientArgs,
    /// Parent directory for disposable job repositories.
    #[arg(long, default_value = ".moor-git-worker")]
    work_dir: PathBuf,
    #[arg(long, default_value_t = 4)]
    max_concurrent_requests: usize,
    #[arg(long, default_value_t = 4096)]
    max_entries: usize,
    #[arg(long, default_value_t = 4194304)]
    max_file_bytes: usize,
    #[arg(long, default_value_t = 16777216)]
    max_total_bytes: usize,
    /// Maximum Git HTTP response bytes and maximum size of each job file.
    #[arg(long, default_value_t = 268435456)]
    max_fetch_bytes: usize,
    /// Virtual address-space ceiling for each Git job.
    #[arg(long, default_value_t = 1073741824)]
    max_memory_bytes: usize,
    #[arg(long, default_value_t = 30)]
    max_seconds: u64,
    #[arg(long)]
    debug: bool,
}
fn main() -> eyre::Result<()> {
    let mut arguments = std::env::args_os().skip(1);
    if arguments.next().as_deref() == Some(std::ffi::OsStr::new("--git-job")) {
        let directory = arguments
            .next()
            .ok_or_else(|| eyre::eyre!("Missing job directory"))?;
        return child_main(std::path::Path::new(&directory));
    }
    color_eyre::install()?;
    let args = Args::parse();
    moor_common::tracing::init_tracing(args.debug)?;
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(run(args))
}
async fn run(args: Args) -> eyre::Result<()> {
    let limits = Limits {
        max_entries: args.max_entries,
        max_file_bytes: args.max_file_bytes,
        max_total_bytes: args.max_total_bytes,
        max_fetch_bytes: args.max_fetch_bytes,
        max_memory_bytes: args.max_memory_bytes,
        max_seconds: args.max_seconds,
    };
    let executor = Arc::new(Executor::new(
        std::env::current_exe()?,
        args.work_dir,
        limits,
        args.max_concurrent_requests,
    )?);
    let keys = moor_zmq_client::enrollment_client::setup_curve_auth(
        &args.connection.rpc_address,
        &args.connection.enrollment_address,
        args.connection.enrollment_token_file.as_deref(),
        "git-worker",
        &args.connection.data_dir,
    )
    .map_err(|e| eyre::eyre!("Worker enrollment failed: {e}"))?;
    let kill = Arc::new(AtomicBool::new(false));
    let ping = Arc::new(AtomicU64::new(0));
    let jobs = executor.clone();
    let perform = Arc::new(move |_id, _kind, _principal, request, timeout| {
        let executor = jobs.clone();
        async move { executor.perform(request, timeout).await }
    });
    let mut terminate = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let work = moor_zmq_client::worker_loop(
        &kill,
        uuid::Uuid::new_v4(),
        &args.connection.workers_response_address,
        &args.connection.workers_request_address,
        Symbol::mk("git"),
        perform,
        keys,
        Some(ping),
    );
    let result = tokio::select! {
        result = work => result.map_err(eyre::Report::from),
        _ = terminate.recv() => Ok(()),
        _ = interrupt.recv() => Ok(()),
    };
    kill.store(true, Ordering::Relaxed);
    executor.shutdown().await;
    result
}
