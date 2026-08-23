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

//! Cold-path metadata for external performance probes.

use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread::JoinHandle,
    time::Duration,
};

use moor_common::{
    model::{HasUuid, Named, ValSet, WorldStateError},
    threading::spawn_efficient,
};
use moor_db::{Database, TxDB};
use tracing::{error, info, warn};

fn emit_verb_metadata(database: &TxDB) -> Result<(usize, usize), WorldStateError> {
    let snapshot = database.create_snapshot()?;
    let export = snapshot.begin_export(&[])?;
    let mut emitted = 0;
    let mut errors = 0;

    for metadata in export.metadata() {
        let object = metadata.oid;
        let verbs = match snapshot.get_object_verbs(&object) {
            Ok(verbs) => verbs,
            Err(error) => {
                warn!(%object, %error, "Unable to read verbs for performance metadata");
                errors += 1;
                continue;
            }
        };

        for verb in verbs.iter() {
            let Some(name) = verb.names().first() else {
                continue;
            };
            let name = name.as_str();
            let (uuid_high, uuid_low) = verb.uuid().as_u64_pair();
            probe::probe!(
                moor_v1,
                verb_metadata,
                uuid_high,
                uuid_low,
                verb.location().as_u64(),
                name.as_ptr(),
                name.len()
            );
            emitted += 1;
        }
    }

    Ok((emitted, errors))
}

/// Start the thread that emits verb metadata after a diagnostics probe attaches.
pub(crate) fn start(
    database: TxDB,
    kill_switch: Arc<AtomicBool>,
) -> std::io::Result<JoinHandle<()>> {
    spawn_efficient("moor-perf-diagnostics", move || {
        let mut was_attached = false;

        while !kill_switch.load(Ordering::Relaxed) {
            let attached = probe::probe_lazy!(moor_v1, diagnostics_attached);
            if attached && !was_attached {
                info!("Performance diagnostics attached; emitting verb metadata");
                match emit_verb_metadata(&database) {
                    Ok((emitted, errors)) => {
                        probe::probe!(moor_v1, verb_metadata_done, emitted, errors);
                        info!(emitted, errors, "Verb performance metadata emitted");
                    }
                    Err(error) => {
                        probe::probe!(moor_v1, verb_metadata_done, 0_usize, 1_usize);
                        error!(%error, "Unable to emit verb performance metadata");
                    }
                }
            }
            was_attached = attached;
            std::thread::sleep(Duration::from_secs(1));
        }
    })
}
