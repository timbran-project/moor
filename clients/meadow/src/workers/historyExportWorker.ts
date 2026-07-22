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
import {
    parseEncryptedHistoryEvents,
    parseHistoricalNarrativeEvent,
    parseNarrativeEventEnvelope,
    toPresentationData,
} from "@moor/web-sdk";
import * as flatbuffers from "flatbuffers";
import { decryptEventBlob } from "../lib/age-decrypt.js";
import { buildAuthHeaders } from "../lib/authHeaders";
import { MoorVar } from "../lib/MoorVar.js";

// Message types
export interface StartExportMessage {
    type: "start";
    authToken: string;
    ageIdentity: string;
    systemTitle: string;
    playerOid: string;
}

export interface ProgressMessage {
    type: "progress";
    processed: number;
    total?: number;
}

export interface ErrorMessage {
    type: "error";
    error: string;
}

export interface CompleteMessage {
    type: "complete";
    jsonBlob: Blob;
}

export type WorkerResponse = ProgressMessage | ErrorMessage | CompleteMessage;

// Convert a decrypted NarrativeEvent to a JSON-serializable object
function narrativeEventToJSON(narrativeEvent: NarrativeEvent): any {
    const eventId = narrativeEvent.eventId()?.dataArray();
    const eventIdStr = eventId
        ? Array.from(eventId).map((b: number) => b.toString(16).padStart(2, "0")).join("")
        : "";

    const timestamp = Number(narrativeEvent.timestamp());
    const timestampMs = timestamp / 1000000; // Convert from nanoseconds to milliseconds
    const timestampISO = new Date(timestampMs).toISOString();

    const result: any = {
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
        (value) => new MoorVar(value as any).toJS(),
        (value) => new MoorVar(value as any).asString(),
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
            result.backtrace = parsed.tracebackText ? parsed.tracebackText.split("\n") : [];
            break;
        case "present":
            result.type = "present";
            result.presentation = toPresentationData(parsed.presentation);
            break;
        case "unpresent":
            result.type = "unpresent";
            result.presentation_id = parsed.presentationId;
            break;
    }

    return result;
}

// Fetch all history in batches
async function fetchAllHistoryEncrypted(authToken: string, ageIdentity: string): Promise<Uint8Array[]> {
    const allEncryptedBlobs: Uint8Array[] = [];
    let hasMore = true;
    let oldestEventId: string | undefined = undefined;
    const batchSize = 1000; // Fetch in large batches

    while (hasMore) {
        const params = new URLSearchParams();
        params.set("limit", batchSize.toString());

        // On first request, get all history by using a very large time range
        // Use 10 years (315,360,000 seconds) to ensure we get everything
        if (!oldestEventId) {
            params.set("since_seconds", "315360000"); // ~10 years
        } else {
            // On subsequent requests, use until_event for pagination
            params.set("until_event", oldestEventId);
        }

        const url = `/v1/history?${params}`;

        console.log(`[Worker] Fetching batch: ${url}`);
        const response = await fetch(url, {
            method: "GET",
            headers: buildAuthHeaders(authToken),
        });

        if (!response.ok) {
            throw new Error(`History fetch failed: ${response.status} ${response.statusText}`);
        }

        const arrayBuffer = await response.arrayBuffer();
        const bytes = new Uint8Array(arrayBuffer);

        const historicalEvents = parseEncryptedHistoryEvents(bytes);
        const eventsLength = historicalEvents.length;

        console.log(`[Worker] Received ${eventsLength} events in this batch`);

        if (eventsLength === 0) {
            hasMore = false;
            break;
        }

        // Extract encrypted blobs and track oldest event ID for pagination
        for (let i = 0; i < eventsLength; i++) {
            const encryptedBlob = historicalEvents[i]?.encryptedBlob;
            if (!encryptedBlob) continue;
            allEncryptedBlobs.push(encryptedBlob);

            // Track the event ID for the first event (oldest in this batch)
            if (i === 0) {
                try {
                    // We need to decrypt briefly just to get the event ID for pagination
                    // This is unavoidable since event IDs are inside the encrypted blob
                    const decryptedBytes = await decryptEventBlob(encryptedBlob, ageIdentity);
                    const envelope = parseNarrativeEventEnvelope(decryptedBytes);
                    if (envelope?.eventId) {
                        oldestEventId = envelope.eventId;
                    }
                } catch (err) {
                    console.error("Failed to extract event ID for pagination:", err);
                }
            }
        }

        // If we got fewer events than requested, we've reached the end
        if (eventsLength < batchSize) {
            hasMore = false;
        }
    }

    return allEncryptedBlobs;
}

// Worker state
declare const self: Worker & { ageIdentityCache: string };

// Handle messages from main thread
self.addEventListener("message", async (event: MessageEvent<StartExportMessage>) => {
    const { type, authToken, ageIdentity, systemTitle, playerOid } = event.data;

    if (type !== "start") {
        self.postMessage({ type: "error", error: "Invalid message type" } as ErrorMessage);
        return;
    }

    try {
        // Cache the age identity for the worker's lifetime
        self.ageIdentityCache = ageIdentity;

        // Step 1: Fetch all encrypted history
        self.postMessage({ type: "progress", processed: 0 } as ProgressMessage);

        const exportStartTime = Date.now();
        const encryptedBlobs = await fetchAllHistoryEncrypted(authToken, ageIdentity);
        const total = encryptedBlobs.length;

        // Step 2: Decrypt and convert to JSON
        const events: any[] = [];

        for (let i = 0; i < encryptedBlobs.length; i++) {
            const encryptedBlob = encryptedBlobs[i];

            try {
                const decryptedBytes = await decryptEventBlob(encryptedBlob, ageIdentity);
                const narrativeEvent = NarrativeEvent.getRootAsNarrativeEvent(
                    new flatbuffers.ByteBuffer(decryptedBytes),
                );

                const eventJSON = narrativeEventToJSON(narrativeEvent);
                if (eventJSON) {
                    events.push(eventJSON);
                }
            } catch (err) {
                console.error("Failed to decrypt/convert event:", err);
                // Continue with next event rather than failing the entire export
            }

            // Report progress every 100 events
            if ((i + 1) % 100 === 0 || i === total - 1) {
                self.postMessage({ type: "progress", processed: i + 1, total } as ProgressMessage);
            }
        }

        // Step 3: Create JSON blob with comprehensive metadata
        const exportEndTime = Date.now();
        const oldestEvent = events.length > 0 ? events[events.length - 1] : null;
        const newestEvent = events.length > 0 ? events[0] : null;

        const jsonString = JSON.stringify(
            {
                export_version: "1.0",
                export_date: new Date().toISOString(),
                system_title: systemTitle,
                player_oid: playerOid,
                event_count: events.length,
                time_range: {
                    oldest_event: oldestEvent ? oldestEvent.timestamp : null,
                    newest_event: newestEvent ? newestEvent.timestamp : null,
                    export_duration_ms: exportEndTime - exportStartTime,
                },
                events,
            },
            null,
            2,
        );

        const jsonBlob = new Blob([jsonString], { type: "application/json" });

        // Step 4: Send completion message
        self.postMessage({ type: "complete", jsonBlob } as CompleteMessage);
    } catch (error) {
        self.postMessage({
            type: "error",
            error: error instanceof Error ? error.message : String(error),
        } as ErrorMessage);
    }
});
