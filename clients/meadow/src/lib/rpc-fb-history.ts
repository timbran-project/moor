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

import {
    ParsedHistoricalNarrativeEvent,
    parseEncryptedHistoryPage,
    parseHistoricalNarrativeEvent,
    parseNarrativeEventEnvelope,
} from "@moor/web-sdk";

import { decryptEventBlob } from "./age-decrypt.js";
import { MoorVar } from "./MoorVar.js";
import { authHeaders, moorApi } from "./rpc-fb-shared";

export interface HistoryEvent {
    event_id: string;
    timestamp: number;
    is_historical: boolean;
    event: ParsedHistoricalNarrativeEvent;
}

export interface HistoryPage {
    events: HistoryEvent[];
    eventCount: number;
    hasMoreBefore: boolean;
    earliestEventId: string | null;
}

export async function fetchHistoryFlatBuffer(
    authToken: string,
    ageIdentity: string | null,
    limit?: number,
    sinceSeconds?: number,
    untilEvent?: string,
): Promise<HistoryPage> {
    try {
        const params = new URLSearchParams();
        if (limit !== undefined) {
            params.set("limit", limit.toString());
        }
        if (sinceSeconds !== undefined) {
            params.set("since_seconds", sinceSeconds.toString());
        }
        if (untilEvent !== undefined) {
            params.set("until_event", untilEvent);
        }

        const url = `/v1/history?${params}`;
        const headers = authHeaders(authToken);
        const bytes = await moorApi.getFlatBuffer(url, {
            method: "GET",
            headers,
        });
        const page = parseEncryptedHistoryPage(bytes);
        const events: HistoryEvent[] = [];

        for (const historicalEvent of page.events) {
            const { encryptedBlob } = historicalEvent;
            if (!ageIdentity) {
                console.warn("No age identity provided, skipping encrypted event");
                continue;
            }

            try {
                const decryptedBytes = await decryptEventBlob(encryptedBlob, ageIdentity);
                const envelope = parseNarrativeEventEnvelope(decryptedBytes);
                if (!envelope) {
                    continue;
                }

                const event = parseHistoricalNarrativeEvent(
                    envelope.narrativeEvent,
                    value => new MoorVar(value).toJS(),
                    value => new MoorVar(value).asString(),
                );
                if (!event) continue;

                events.push({
                    event_id: envelope.eventId,
                    timestamp: envelope.timestampNanos / 1000000,
                    is_historical: historicalEvent.isHistorical,
                    event,
                });
            } catch (err) {
                console.error("Failed to decrypt/parse event:", err);
            }
        }

        return { ...page, events };
    } catch (err) {
        console.error("Exception during FlatBuffer history fetch:", err);
        throw err;
    }
}
