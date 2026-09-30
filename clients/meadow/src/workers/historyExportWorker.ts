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

// Web Worker for exporting event history
// Handles decryption and JSON conversion off the main thread

import { NarrativeEvent } from "@moor/schema/generated/moor-common/narrative-event";
import { buildAuthHeaders, parseEncryptedHistoryPage, parseHistoricalNarrativeEvent } from "@moor/web-sdk";
import * as flatbuffers from "flatbuffers";
import { decryptEventBlob } from "../lib/age-decrypt.js";
import { MoorVar } from "../lib/MoorVar.js";

import { HISTORY_EXPORT_BATCH_SIZE, WorkerRequest, WorkerResponse } from "./historyExportProtocol";
import { ExportEvent, readExportPage, streamHistoryExport } from "./historyExportStream";

// Convert a decrypted NarrativeEvent to a JSON-serializable object
function narrativeEventToJSON(narrativeEvent: NarrativeEvent): ExportEvent {
    const eventId = narrativeEvent.eventId()?.dataArray();
    const eventIdStr = eventId
        ? Array.from(eventId).map((b: number) => b.toString(16).padStart(2, "0")).join("")
        : "";

    const timestamp = Number(narrativeEvent.timestamp());
    const timestampMs = timestamp / 1000000; // Convert from nanoseconds to milliseconds
    const timestampISO = new Date(timestampMs).toISOString();

    const result: ExportEvent = {
        event_id: eventIdStr,
        timestamp: timestampISO,
        timestamp_ms: timestampMs,
    };

    // Extract author (player OID) if present
    const author = narrativeEvent.author();
    if (author) {
        const authorValue = new MoorVar(author).toJS();
        if (authorValue && typeof authorValue === "object" && "Obj" in authorValue) {
            result.author_oid = authorValue.Obj;
        }
    }

    const parsed = parseHistoricalNarrativeEvent(
        narrativeEvent,
        (value) => new MoorVar(value).toJS(),
        (value) => new MoorVar(value).asString(),
    );
    if (!parsed) {
        result.type = "unknown";
        return result;
    }

    switch (parsed.kind) {
        case "notify":
            result.type = "notify";
            result.content = parsed.content;
            result.content_type = parsed.contentType;
            break;
        case "traceback":
            result.type = "traceback";
            result.backtrace = parsed.backtrace;
            break;
        case "present":
            result.type = "present";
            result.presentation = parsed.presentData;
            break;
        case "unpresent":
            result.type = "unpresent";
            result.presentation_id = parsed.presentationId;
            break;
    }

    return result;
}

declare const self: DedicatedWorkerGlobalScope;

// Only one chunk may be in flight; the main thread acknowledges it after writing.
let acknowledge: (() => void) | null = null;
let running = false;
const send = (message: WorkerResponse, transfer: Transferable[] = []) => self.postMessage(message, transfer);

self.addEventListener("message", async (event: MessageEvent<WorkerRequest>) => {
    const message = event.data;
    if (message.type === "ack") {
        const resolve = acknowledge;
        acknowledge = null;
        resolve?.();
        return;
    }
    if (message.type !== "start" || running) return;
    running = true;

    try {
        const result = await streamHistoryExport({
            systemTitle: message.systemTitle,
            playerOid: message.playerOid,
            fetchPage: async (cursor) => {
                const params = new URLSearchParams({ limit: String(HISTORY_EXPORT_BATCH_SIZE) });
                if (cursor) params.set("until_event", cursor);
                else params.set("since_seconds", "315360000");
                const response = await fetch(`/v1/history?${params}`, {
                    headers: buildAuthHeaders(message.authToken),
                });
                if (!response.ok) throw new Error(`History fetch failed: ${response.status}`);
                return parseEncryptedHistoryPage(await readExportPage(response));
            },
            convertEvent: async (blob) => {
                const bytes = await decryptEventBlob(blob, message.ageIdentity);
                return narrativeEventToJSON(NarrativeEvent.getRootAsNarrativeEvent(new flatbuffers.ByteBuffer(bytes)));
            },
            write: (bytes) =>
                new Promise<void>((resolve) => {
                    acknowledge = resolve;
                    send({ type: "chunk", bytes }, [bytes.buffer]);
                }),
            onProgress: (processed) => send({ type: "progress", processed }),
        });
        send({ type: "complete", skipped: result.skipped });
    } catch (error) {
        send({ type: "error", error: error instanceof Error ? error.message : "History export failed" });
    }
});
