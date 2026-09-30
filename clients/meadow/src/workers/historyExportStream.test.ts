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

import { EncryptedHistoryPage } from "@moor/web-sdk";
import { describe, expect, it, vi } from "vitest";
import { HISTORY_EXPORT_CHUNK_BYTES, HISTORY_EXPORT_PAGE_LIMIT } from "./historyExportProtocol";
import { readExportPage, streamHistoryExport } from "./historyExportStream";

function page(ids: number[], cursor: string | null = "cursor", hasMoreBefore = false): EncryptedHistoryPage {
    return {
        events: ids.map(id => ({ encryptedBlob: new Uint8Array([id]), isHistorical: true })),
        eventCount: ids.length,
        earliestEventId: cursor,
        hasMoreBefore,
    };
}
const metadata = { systemTitle: "A \"world\"", playerOid: "oid:1" };
const convertEvent = async (blob: Uint8Array) => ({
    event_id: String(blob[0]),
    timestamp: new Date(blob[0]).toISOString(),
    timestamp_ms: blob[0],
    content: "Hello 🌿",
});

function collector() {
    const chunks: Uint8Array[] = [];
    return {
        write: async (chunk: Uint8Array) => {
            chunks.push(chunk);
        },
        text: () => chunks.map(chunk => new TextDecoder().decode(chunk)).join(""),
    };
}

describe("streaming history serialization", () => {
    it("keeps the JSON schema, page order, Unicode, counts, and actual timestamp range", async () => {
        const output = collector();
        const fetchPage = vi.fn().mockResolvedValueOnce(page([3, 4], "first"))
            .mockResolvedValueOnce(page([1, 2], "last"));
        const onProgress = vi.fn();
        await streamHistoryExport({ ...metadata, fetchPage, convertEvent, write: output.write, onProgress });
        const json = JSON.parse(output.text());
        expect(json.events.map((event: { event_id: string }) => event.event_id)).toEqual(["3", "4", "1", "2"]);
        expect(json.events[0].content).toBe("Hello 🌿");
        expect(json.event_count).toBe(4);
        expect(json.skipped_event_count).toBe(0);
        expect(json.system_title).toBe(metadata.systemTitle);
        expect(json.export_version).toBe("1.0");
        expect(json.time_range.oldest_event).toBe(new Date(1).toISOString());
        expect(json.time_range.newest_event).toBe(new Date(4).toISOString());
        expect(output.text()).not.toContain("\n");
        expect(fetchPage.mock.calls).toEqual([[undefined], ["first"]]);
        expect(onProgress).toHaveBeenLastCalledWith(4);
    });

    it("emits valid empty exports", async () => {
        const output = collector();
        await streamHistoryExport({
            ...metadata,
            fetchPage: async () => page([]),
            convertEvent,
            write: output.write,
            onProgress: vi.fn(),
        });
        expect(JSON.parse(output.text())).toMatchObject({
            events: [],
            event_count: 0,
            time_range: { oldest_event: null, newest_event: null },
        });
    });

    it("skips corrupt events and paginates using metadata without decrypting the cursor again", async () => {
        const output = collector();
        const fetchPage = vi.fn().mockResolvedValueOnce(page([3, 4], "first"))
            .mockResolvedValueOnce(page([1, 2], "last"));
        const convert = vi.fn(async (blob: Uint8Array) => {
            if (blob[0] === 3) throw new Error("private data");
            return convertEvent(blob);
        });
        await streamHistoryExport({
            ...metadata,
            fetchPage,
            convertEvent: convert,
            write: output.write,
            onProgress: vi.fn(),
        });
        expect(convert).toHaveBeenCalledTimes(4);
        expect(JSON.parse(output.text())).toMatchObject({ event_count: 3, skipped_event_count: 1 });
        expect(output.text()).not.toContain("private data");
    });

    it.each([null, "same"])("rejects missing or repeated continuation cursors: %s", async (cursor) => {
        const fetchPage = vi.fn().mockResolvedValueOnce(page([2], "same", true))
            .mockResolvedValueOnce(page([1], cursor, true));
        await expect(
            streamHistoryExport({ ...metadata, fetchPage, convertEvent, write: async () => {}, onProgress: vi.fn() }),
        )
            .rejects.toThrow(/cursor/);
        expect(fetchPage).toHaveBeenCalledTimes(2);
    });

    it("stops fetching when the output fails instead of skipping the failed write", async () => {
        const fetchPage = vi.fn(async () => page([1]));
        await expect(streamHistoryExport({
            ...metadata,
            fetchPage,
            convertEvent,
            write: async () => {
                throw new Error("disk full");
            },
            onProgress: vi.fn(),
        })).rejects.toThrow("disk full");
        expect(fetchPage).toHaveBeenCalledTimes(1);
    });

    it("holds at most one 64 KiB output chunk across more than 64 MiB and 128 pages", async () => {
        let pages = 0;
        let pendingBytes = 0;
        let peakBytes = 0;
        let totalBytes = 0;
        const fetchPage = async () => {
            expect(pendingBytes).toBe(0);
            pages++;
            return page([1], `page-${pages}`, pages < 128);
        };
        await streamHistoryExport({
            ...metadata,
            fetchPage,
            convertEvent: async blob => ({ ...await convertEvent(blob), content: "🌿".repeat(128 * 1024) }),
            write: async bytes => {
                pendingBytes += bytes.byteLength;
                peakBytes = Math.max(peakBytes, pendingBytes);
                await Promise.resolve();
                totalBytes += bytes.byteLength;
                pendingBytes -= bytes.byteLength;
            },
            onProgress: () => {},
        });
        expect(totalBytes).toBeGreaterThan(64 * 1024 * 1024);
        expect(peakBytes).toBe(HISTORY_EXPORT_CHUNK_BYTES);
        expect(pages).toBe(128);
    });

    it("does not fetch another page while the sink is stalled", async () => {
        let release!: () => void;
        let started!: () => void;
        const entered = new Promise<void>(resolve => {
            started = resolve;
        });
        const gate = new Promise<void>(resolve => {
            release = resolve;
        });
        const fetchPage = vi.fn().mockResolvedValueOnce(page([1])).mockResolvedValueOnce(page([]));
        const pending = streamHistoryExport({
            ...metadata,
            fetchPage,
            convertEvent,
            write: async () => {
                started();
                await gate;
            },
            onProgress: vi.fn(),
        });
        await entered;
        expect(fetchPage).toHaveBeenCalledTimes(1);
        release();
        await pending;
        expect(fetchPage).toHaveBeenCalledTimes(2);
    });
});

describe("history page byte limit", () => {
    it("reads a small page across response chunks", async () => {
        const response = new Response(
            new ReadableStream({
                start(controller) {
                    controller.enqueue(new Uint8Array([1, 2]));
                    controller.enqueue(new Uint8Array([3]));
                    controller.close();
                },
            }),
        );
        expect(await readExportPage(response)).toEqual(new Uint8Array([1, 2, 3]));
    });
    it("cancels an oversized response before buffering the excess", async () => {
        const cancel = vi.fn();
        const response = new Response(
            new ReadableStream({
                start(controller) {
                    controller.enqueue(new Uint8Array(HISTORY_EXPORT_PAGE_LIMIT));
                    controller.enqueue(new Uint8Array(1));
                },
                cancel,
            }),
        );
        await expect(readExportPage(response)).rejects.toThrow("16 MiB");
        expect(cancel).toHaveBeenCalledOnce();
    });
});
