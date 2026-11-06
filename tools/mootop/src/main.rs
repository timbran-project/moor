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

//! `mootop`: where a running mooR daemon spends its time, by verb, builtin and task.
//!
//! It attaches bpftrace to the daemon's `moor` USDT probes and samples what each thread is
//! running. It needs root, or the capabilities bpftrace needs.

mod dash;
mod live;
mod metrics;
mod record;
mod snapshot;
mod trace;

use std::{
    path::PathBuf,
    process::ExitCode,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use clap::Parser as _;
use clap_derive::{Args, Parser, Subcommand};

use crate::{
    record::Recorder,
    snapshot::Header,
    trace::{Trace, TraceEvent},
};

#[derive(Parser)]
#[command(version, about = "Show where a running mooR daemon spends its time")]
struct Args {
    #[command(subcommand)]
    command: Option<Command>,

    #[command(flatten)]
    capture: CaptureArgs,

    /// Also record the session to this file.
    #[arg(short, long)]
    output: Option<PathBuf>,
}

#[derive(Args, Clone)]
struct CaptureArgs {
    /// The daemon's process ID. By default, the only running moor-daemon or moor process.
    #[arg(short, long, global = true)]
    pid: Option<u32>,

    /// Samples per second, on each CPU.
    #[arg(long, default_value_t = 499, global = true)]
    hz: u32,

    /// The bpftrace to run.
    #[arg(long, default_value = "bpftrace", global = true)]
    bpftrace: String,
}

#[derive(Subcommand)]
enum Command {
    /// Record without the live view, for a later report.
    Record {
        /// The file to write.
        #[arg(short, long)]
        output: PathBuf,
        /// How long to record, in seconds.
        #[arg(short, long, default_value_t = 30)]
        duration: u64,
    },
    /// Print a report of a recording.
    Report {
        /// The recording to read.
        file: PathBuf,
        /// Rows to show in each table.
        #[arg(short, long, default_value_t = 30)]
        top: usize,
    },
}

fn main() -> ExitCode {
    let args = Args::parse();
    let result = match args.command {
        None => live_view(&args.capture, args.output),
        Some(Command::Record { output, duration }) => record(&args.capture, &output, duration),
        Some(Command::Report { file, top }) => record::report(&file, top),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("mootop: {e}");
            ExitCode::FAILURE
        }
    }
}

fn start(
    capture: &CaptureArgs,
    output: Option<&PathBuf>,
) -> Result<(Trace, Option<Recorder>), String> {
    let trace = Trace::start(capture.pid, capture.hz, &capture.bpftrace)?;
    let recorder = match output {
        Some(path) => {
            let header = Header {
                pid: trace.pid,
                binary: trace.binary.clone(),
                hz: capture.hz,
                started: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
            };
            Some(Recorder::create(path, &header)?)
        }
        None => None,
    };
    Ok((trace, recorder))
}

fn live_view(capture: &CaptureArgs, output: Option<PathBuf>) -> Result<(), String> {
    let (trace, recorder) = start(capture, output.as_ref())?;
    live::run(trace, capture.hz, recorder)
}

fn record(capture: &CaptureArgs, output: &PathBuf, duration: u64) -> Result<(), String> {
    let (trace, recorder) = start(capture, Some(output))?;
    let mut recorder = recorder.expect("recorder for an output file");
    let deadline = Instant::now() + Duration::from_secs(duration);
    eprintln!(
        "Recording pid {} for {duration}s to {}",
        trace.pid,
        output.display()
    );
    let mut intervals = 0;
    while let Some(left) = deadline.checked_duration_since(Instant::now()) {
        match trace.events.recv_timeout(left) {
            Ok(TraceEvent::Snapshot(snapshot)) => {
                recorder.write(&snapshot)?;
                intervals += 1;
            }
            Ok(TraceEvent::Warning(warning)) => eprintln!("mootop: {warning}"),
            Ok(TraceEvent::Exited(stderr)) => return Err(format!("bpftrace exited.\n{stderr}")),
            Err(_) => break,
        }
    }
    eprintln!("Recorded {intervals} intervals.");
    Ok(())
}
