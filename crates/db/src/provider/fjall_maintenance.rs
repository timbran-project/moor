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

//! Isolates Fjall maintenance APIs that are not part of its supported public surface.

use crate::{DatabaseRelation, RelationCompactionResult};

pub(crate) fn major_compact(
    relation: DatabaseRelation,
    keyspace: &fjall::Keyspace,
) -> RelationCompactionResult {
    let bytes_before_flush = keyspace.disk_space();

    // TODO(fjall#313): This adapter is temporary. Replace it with Fjall's supported public API
    // for flushing and major-compacting a live keyspace when that API exists.
    // https://github.com/fjall-rs/fjall/issues/313
    if let Err(error) = keyspace.rotate_memtable_and_wait() {
        return RelationCompactionResult::failed(
            relation,
            bytes_before_flush,
            bytes_before_flush,
            error.to_string(),
        );
    }
    let bytes_before = keyspace.disk_space();
    if let Err(error) = keyspace.major_compact() {
        return RelationCompactionResult::failed(
            relation,
            bytes_before,
            keyspace.disk_space(),
            error.to_string(),
        );
    }

    RelationCompactionResult::completed(relation, bytes_before, keyspace.disk_space())
}
