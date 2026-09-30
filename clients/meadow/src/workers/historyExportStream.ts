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
import { advanceHistoryExportCursor } from "./historyExportPagination";
import { HISTORY_EXPORT_CHUNK_BYTES, HISTORY_EXPORT_PAGE_LIMIT } from "./historyExportProtocol";

/** Cap response buffering even when a page contains unusually large events. */
export async function readExportPage(response: Response): Promise<Uint8Array> {
    if (!response.body) throw new Error("History response has no body");
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
        while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > HISTORY_EXPORT_PAGE_LIMIT) {
                await reader.cancel();
                throw new Error("History export stopped: a history page exceeds the 16 MiB processing limit.");
            }
            chunks.push(value);
        }
    } finally {
        reader.releaseLock();
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
    }
    return bytes;
}

export interface ExportEvent {
    timestamp: string;
    timestamp_ms: number;
    [key: string]: unknown;
}

interface ExportOptions {
    systemTitle: string;
    playerOid: string;
    fetchPage: (cursor?: string) => Promise<EncryptedHistoryPage>;
    convertEvent: (blob: Uint8Array) => Promise<ExportEvent>;
    write: (chunk: Uint8Array<ArrayBuffer>) => Promise<void>;
    onProgress: (processed: number) => void;
}

/** Serialize one event at a time; writes apply backpressure before fetching another page. */
export async function streamHistoryExport(options: ExportOptions): Promise<{ skipped: number }> {
    const started = Date.now();
    const encoder = new TextEncoder();
    let buffer = new Uint8Array(HISTORY_EXPORT_CHUNK_BYTES);
    let used = 0;
    const flush = async () => {
        if (!used) return;
        await options.write(used === buffer.length ? buffer : buffer.slice(0, used));
        buffer = new Uint8Array(HISTORY_EXPORT_CHUNK_BYTES);
        used = 0;
    };
    const append = async (text: string) => {
        const bytes = encoder.encode(text);
        let offset = 0;
        while (offset < bytes.length) {
            const count = Math.min(buffer.length - used, bytes.length - offset);
            buffer.set(bytes.subarray(offset, offset + count), used);
            used += count;
            offset += count;
            if (used === buffer.length) await flush();
        }
    };

    let processed = 0;
    let eventCount = 0;
    let skipped = 0;
    let oldest: { timestamp: string; ms: number } | null = null;
    let newest: { timestamp: string; ms: number } | null = null;
    let cursor: string | undefined;
    await append("{\"events\":[");
    options.onProgress(0);

    while (true) {
        const page = await options.fetchPage(cursor);
        if (!page.eventCount) break;
        skipped += page.eventCount - page.events.length;
        processed += page.eventCount - page.events.length;
        for (const { encryptedBlob } of page.events) {
            let converted: ExportEvent;
            let json: string;
            try {
                converted = await options.convertEvent(encryptedBlob);
                json = JSON.stringify(converted);
            } catch {
                // Crypto and conversion exceptions may contain private event data.
                skipped++;
                processed++;
                continue;
            }
            await append((eventCount ? "," : "") + json);
            eventCount++;
            if (!oldest || converted.timestamp_ms < oldest.ms) {
                oldest = { timestamp: converted.timestamp, ms: converted.timestamp_ms };
            }
            if (!newest || converted.timestamp_ms > newest.ms) {
                newest = { timestamp: converted.timestamp, ms: converted.timestamp_ms };
            }
            processed++;
            if (processed % 100 === 0) options.onProgress(processed);
        }
        // Drain this page before requesting another; the sink owns only one pending chunk.
        await flush();
        options.onProgress(processed);
        // The initial time window's terminal flag does not cover history before that window.
        if (cursor && !page.hasMoreBefore) break;
        cursor = advanceHistoryExportCursor(cursor, page.earliestEventId ?? undefined);
    }

    const metadata = {
        export_version: "1.0",
        export_date: new Date().toISOString(),
        system_title: options.systemTitle,
        player_oid: options.playerOid,
        event_count: eventCount,
        skipped_event_count: skipped,
        time_range: {
            oldest_event: oldest?.timestamp ?? null,
            newest_event: newest?.timestamp ?? null,
            export_duration_ms: Date.now() - started,
        },
    };
    await append("]," + JSON.stringify(metadata).slice(1));
    await flush();
    return { skipped };
}
