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

//! Recordings: a header line, then one snapshot per line, as JSON.

use std::{
    fs::File,
    io::{BufRead, BufReader, BufWriter, Write},
    path::Path,
};

use crate::snapshot::{Header, Names, Snapshot, View, rows, summary};

pub struct Recorder {
    out: BufWriter<File>,
}

impl Recorder {
    pub fn create(path: &Path, header: &Header) -> Result<Self, String> {
        let file = File::create(path).map_err(|e| format!("Couldn't create {path:?}: {e}"))?;
        let mut recorder = Self {
            out: BufWriter::new(file),
        };
        recorder.line(header)?;
        Ok(recorder)
    }

    pub fn write(&mut self, snapshot: &Snapshot) -> Result<(), String> {
        self.line(snapshot)
    }

    fn line(&mut self, value: &impl serde::Serialize) -> Result<(), String> {
        serde_json::to_writer(&mut self.out, value).map_err(|e| e.to_string())?;
        // Flush each line, so an interrupted recording is still readable.
        writeln!(self.out)
            .and_then(|_| self.out.flush())
            .map_err(|e| format!("Couldn't write the recording: {e}"))
    }
}

/// Print a report of a recording.
pub fn report(path: &Path, top: usize) -> Result<(), String> {
    let file = File::open(path).map_err(|e| format!("Couldn't open {path:?}: {e}"))?;
    let mut lines = BufReader::new(file).lines();
    let header: Header = lines
        .next()
        .ok_or("The recording is empty.")?
        .map_err(|e| e.to_string())
        .and_then(|l| serde_json::from_str(&l).map_err(|e| format!("Bad header: {e}")))?;

    let mut total = Snapshot::default();
    let mut names = Names::default();
    let mut intervals = 0;
    for line in lines {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let snapshot: Snapshot =
            serde_json::from_str(&line).map_err(|e| format!("Bad snapshot: {e}"))?;
        names.learn(&snapshot);
        total.merge(&snapshot);
        intervals += 1;
    }

    let s = summary(&total, header.hz);
    let commits: f64 = s.commits.iter().sum();
    println!(
        "mootop recording of pid {} ({}), {intervals} intervals over {:.0}s, sampled at {} Hz",
        header.pid, header.binary, total.seconds, header.hz
    );
    println!();
    println!(
        "CPU      daemon {:.1}%   tasks {:.1}%   commits {:.1}%   other threads {:.1}%",
        s.daemon_cpu, s.task_cpu, s.commit_cpu, s.other_cpu
    );
    println!(
        "Commits  {commits:.1}/s: read-only {:.1}, write {:.1} (mean {:.0}µs), conflict {:.1}, \
         error {:.1}",
        s.commits[0], s.commits[1], s.commit_us[1], s.commits[2], s.commits[3]
    );

    for view in View::ALL {
        let rows = rows(&total, header.hz, &names, view);
        println!();
        println!("{} (top {top} of {})", view.title(), rows.len());
        match view {
            View::Tasks => println!("{:>7}  {:<14}  Busiest frame", "%CPU", "Task"),
            _ => println!("{:>7}  {:>9}  Name", "%CPU", "Calls/s"),
        }
        for r in rows.iter().take(top) {
            match view {
                View::Tasks => println!("{:7.2}  {:<14}  {}", r.cpu, r.label, r.detail),
                _ => println!(
                    "{:7.2}  {:>9}  {}",
                    r.cpu,
                    r.calls.map(|c| format!("{c:.1}")).unwrap_or_default(),
                    r.label
                ),
            }
        }
    }
    Ok(())
}
