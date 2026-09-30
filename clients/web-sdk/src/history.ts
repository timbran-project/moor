// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

import { Event } from "@moor/schema/generated/moor-common/event";
import { NarrativeEvent } from "@moor/schema/generated/moor-common/narrative-event";
import { HistoryResponseReply } from "@moor/schema/generated/moor-rpc/history-response-reply";
import * as flatbuffers from "flatbuffers";

import { parseClientReplyUnion } from "./reply.js";

function replyTypeName(value: unknown): string {
    return value?.constructor?.name ?? typeof value;
}

export interface EncryptedHistoricalEvent {
    encryptedBlob: Uint8Array;
    isHistorical: boolean;
}

export interface EncryptedHistoryPage {
    events: EncryptedHistoricalEvent[];
    eventCount: number;
    hasMoreBefore: boolean;
    earliestEventId: string | null;
}

/** Reads pagination metadata independently of event decryption. */
export function parseEncryptedHistoryPage(bytes: Uint8Array): EncryptedHistoryPage {
    const replyUnion = parseClientReplyUnion(bytes, "History fetch");
    if (!(replyUnion instanceof HistoryResponseReply)) {
        throw new Error(`Unexpected reply type: ${replyTypeName(replyUnion)}`);
    }

    const historyResponse = replyUnion.response();
    if (!historyResponse) {
        throw new Error("Missing history response");
    }

    const events: EncryptedHistoricalEvent[] = [];
    for (let i = 0; i < historyResponse.eventsLength(); i++) {
        const historicalEvent = historyResponse.events(i);
        if (!historicalEvent) {
            continue;
        }
        const encryptedBlob = historicalEvent.encryptedBlobArray();
        if (!encryptedBlob) {
            continue;
        }
        events.push({
            encryptedBlob,
            isHistorical: historicalEvent.isHistorical(),
        });
    }
    const cursorBytes = historyResponse.earliestEventId()?.dataArray();
    return {
        events,
        eventCount: historyResponse.eventsLength(),
        hasMoreBefore: historyResponse.hasMoreBefore(),
        earliestEventId: cursorBytes?.length === 16
            ? Array.from(cursorBytes, byte => byte.toString(16).padStart(2, "0")).join("")
            : null,
    };
}

export function parseEncryptedHistoryEvents(bytes: Uint8Array): EncryptedHistoricalEvent[] {
    return parseEncryptedHistoryPage(bytes).events;
}

export interface ParsedNarrativeEventEnvelope {
    eventId: string;
    timestampNanos: number;
    event: Event;
    narrativeEvent: NarrativeEvent;
}

export { parseNarrativeValue as parseHistoricalNarrativeEvent } from "./ws-narrative.js";
export type {
    ParsedNarrativePayload as ParsedHistoricalNarrativeEvent,
    WsDataEvent as ParsedHistoricalDataEvent,
    WsNotifyEvent as ParsedHistoricalNotifyEvent,
    WsPresentEvent as ParsedHistoricalPresentEvent,
    WsTracebackEvent as ParsedHistoricalTracebackEvent,
    WsUnpresentEvent as ParsedHistoricalUnpresentEvent,
} from "./ws-narrative.js";

export function parseNarrativeEventEnvelope(bytes: Uint8Array): ParsedNarrativeEventEnvelope | null {
    const narrativeEvent = NarrativeEvent.getRootAsNarrativeEvent(
        new flatbuffers.ByteBuffer(bytes),
    );

    const eventData = narrativeEvent.event();
    if (!eventData) {
        return null;
    }

    const eventId = narrativeEvent.eventId()?.dataArray();
    const eventIdStr = eventId
        ? Array.from(eventId).map((b: number) => b.toString(16).padStart(2, "0")).join("")
        : "";

    return {
        eventId: eventIdStr,
        timestampNanos: Number(narrativeEvent.timestamp()),
        event: eventData,
        narrativeEvent,
    };
}
