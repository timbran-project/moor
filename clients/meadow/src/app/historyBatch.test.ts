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

import { describe, expect, it } from "vitest";
import type { NarrativeMessage } from "../components/Narrative";
import { computeHistoryBatchSignature, HISTORY_BATCH_DEDUP_WINDOW_MS, isRedundantHistoryBatch } from "./historyBatch";

const message = (overrides: Partial<NarrativeMessage> = {}): NarrativeMessage => ({
    id: "m1",
    content: "hello",
    type: "narrative",
    timestamp: 1000,
    ...overrides,
} as NarrativeMessage);

describe("history batch deduplication", () => {
    it("returns a null signature for empty batches", () => {
        expect(computeHistoryBatchSignature([])).toBeNull();
    });

    it("recognizes a repeated batch and accepts different boundaries", () => {
        const batch = [
            message({ id: "a", eventId: "evt-a", timestamp: 10 }),
            message({ id: "b", eventId: "evt-b", timestamp: 20 }),
        ];
        const signature = computeHistoryBatchSignature(batch);
        const now = 1_000_000;
        expect(isRedundantHistoryBatch(computeHistoryBatchSignature([...batch]), signature, now - 1000, now)).toBe(true);
        expect(isRedundantHistoryBatch(computeHistoryBatchSignature([
            batch[0], message({ id: "c", eventId: "evt-c", timestamp: 20 }),
        ]), signature, now - 1000, now)).toBe(false);
        expect(isRedundantHistoryBatch(computeHistoryBatchSignature([
            batch[0], message({ id: "b", eventId: "evt-b", timestamp: 21 }),
        ]), signature, now - 1000, now)).toBe(false);
    });

    it("recognizes equal batches without event ids using message ids", () => {
        const batch = [message({ id: "only", timestamp: 5 })];
        const now = 1_000_000;
        expect(isRedundantHistoryBatch(
            computeHistoryBatchSignature([message({ id: "only", timestamp: 5 })]),
            computeHistoryBatchSignature(batch), now - 1000, now,
        )).toBe(true);
        expect(isRedundantHistoryBatch(
            computeHistoryBatchSignature([message({ id: "other", timestamp: 5 })]),
            computeHistoryBatchSignature(batch), now - 1000, now,
        )).toBe(false);
    });

    it("treats empty batches as never redundant", () => {
        expect(isRedundantHistoryBatch(null, null, Date.now(), Date.now())).toBe(false);
    });

    it("flags an identical repeated batch inside the dedup window", () => {
        const now = 1_000_000;
        const signature = computeHistoryBatchSignature([message()]);
        expect(isRedundantHistoryBatch(signature, signature, now - 1000, now)).toBe(true);
    });

    it("allows an identical batch after the dedup window expires", () => {
        const now = 1_000_000;
        const signature = computeHistoryBatchSignature([message()]);
        expect(
            isRedundantHistoryBatch(signature, signature, now - HISTORY_BATCH_DEDUP_WINDOW_MS - 1, now),
        ).toBe(false);
    });

    it("does not flag different batches", () => {
        const now = 1_000_000;
        const previous = computeHistoryBatchSignature([message({ id: "before" })]);
        const current = computeHistoryBatchSignature([message({ id: "after" })]);
        expect(isRedundantHistoryBatch(current, previous, now - 1000, now)).toBe(false);
    });
});
