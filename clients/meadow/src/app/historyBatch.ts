// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// General Public License as published by the Free Software Foundation, version
// 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.
//

import { NarrativeMessage } from "../components/Narrative";

export const HISTORY_BATCH_DEDUP_WINDOW_MS = 2 * 60 * 1000;

/**
 * Identifies a history batch by size, boundary event ids, and timestamps so a
 * repeated fetch of the same page can be recognized and skipped.
 * Returns null for empty batches (which are never treated as redundant).
 */
export const computeHistoryBatchSignature = (messages: NarrativeMessage[]): string | null => {
    if (messages.length === 0) {
        return null;
    }
    const first = messages[0];
    const last = messages[messages.length - 1];
    const firstKey = first.eventId || first.id;
    const lastKey = last.eventId || last.id;
    return `${messages.length}:${firstKey}:${lastKey}:${first.timestamp || 0}:${last.timestamp || 0}`;
};

/**
 * True when this batch repeats the immediately-previous batch within the dedup
 * window. Empty batches are never redundant.
 */
export const isRedundantHistoryBatch = (
    signature: string | null,
    lastSignature: string | null,
    lastAppliedAt: number,
    now: number,
): boolean => {
    if (signature === null || signature !== lastSignature) {
        return false;
    }
    return (now - lastAppliedAt) < HISTORY_BATCH_DEDUP_WINDOW_MS;
};
