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

    it("signs batches by size, boundary ids, and timestamps", () => {
        const batch = [
            message({ id: "a", eventId: "evt-a", timestamp: 10 }),
            message({ id: "b", eventId: "evt-b", timestamp: 20 }),
        ];
        expect(computeHistoryBatchSignature(batch)).toBe("2:evt-a:evt-b:10:20");
    });

    it("falls back to message ids when event ids are missing", () => {
        const batch = [message({ id: "only", timestamp: 5 })];
        expect(computeHistoryBatchSignature(batch)).toBe("1:only:only:5:5");
    });

    it("treats empty batches as never redundant", () => {
        expect(isRedundantHistoryBatch(null, null, Date.now(), Date.now())).toBe(false);
    });

    it("flags an identical repeated batch inside the dedup window", () => {
        const now = 1_000_000;
        expect(isRedundantHistoryBatch("sig", "sig", now - 1000, now)).toBe(true);
    });

    it("allows an identical batch after the dedup window expires", () => {
        const now = 1_000_000;
        expect(
            isRedundantHistoryBatch("sig", "sig", now - HISTORY_BATCH_DEDUP_WINDOW_MS - 1, now),
        ).toBe(false);
    });

    it("does not flag different batches", () => {
        const now = 1_000_000;
        expect(isRedundantHistoryBatch("sig-2", "sig-1", now - 1000, now)).toBe(false);
    });
});
