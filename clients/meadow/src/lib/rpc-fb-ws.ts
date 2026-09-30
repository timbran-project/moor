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

import { NarrativeEventMessage } from "@moor/schema/generated/moor-rpc/narrative-event-message";
import { SchedulerError } from "@moor/schema/generated/moor-rpc/scheduler-error";
import { SchedulerErrorUnion } from "@moor/schema/generated/moor-rpc/scheduler-error-union";
import {
    decodeCredentialsUpdatedEvent,
    decodePlayerSwitchedEvent,
    dispatchClientEvent,
    parseWsNarrativeEventMessage,
    PlayerIdentityUpdate,
    schedulerErrorToNarrative,
    SessionCredentialsUpdate,
    type WsDataEvent,
} from "@moor/web-sdk";
import type { MutableRefObject } from "react";

import { InputMetadata } from "../types/input";
import { PresentationData } from "../types/presentation";
import { parseInputMetadata } from "./input-metadata.js";
import { MoorVar } from "./MoorVar.js";
import { NarrativeMessageHandler } from "./rpc-fb-shared";

export type DataMessageHandlerEvent = Omit<WsDataEvent, "kind"> & {
    timestamp: string;
    eventId?: string;
};

function narrativeEventIdHex(narrative: NarrativeEventMessage): string | undefined {
    const bytes = narrative.event()?.eventId()?.dataArray();
    return bytes?.length === 16 ? Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("") : undefined;
}

function handleTaskError(
    schedulerError: SchedulerError,
    onNarrativeMessage?: NarrativeMessageHandler,
): void {
    const errorNarrative = schedulerErrorToNarrative(schedulerError);
    if (errorNarrative && onNarrativeMessage) {
        const fullMessage = errorNarrative.description
            ? `${errorNarrative.message}\n${errorNarrative.description.join("\n")}`
            : errorNarrative.message;
        onNarrativeMessage(
            fullMessage,
            new Date().toISOString(),
            "text/traceback",
            false,
            false,
            undefined,
            undefined,
            undefined,
            undefined,
        );
        return;
    }

    const errorType = schedulerError.errorType();
    console.warn(`[WS] Unhandled task error type: ${SchedulerErrorUnion[errorType]}`, schedulerError);
}

export interface ClientEventHandlers {
    onTaskComplete?: () => void;
    onSystemMessage?: (message: string, duration?: number) => void;
    onNarrativeMessage?: NarrativeMessageHandler;
    onPresentMessage?: (presentData: PresentationData) => void;
    onUnpresentMessage?: (id: string) => void;
    onDataMessage?: (event: DataMessageHandlerEvent) => void;
    onPlayerSwitched?: (identity: PlayerIdentityUpdate) => void;
    onCredentialsUpdated?: (credentials: SessionCredentialsUpdate) => void;
    lastEventTimestampRef?: MutableRefObject<bigint | null>;
    onInputMetadata?: (metadata: InputMetadata | null) => void;
}

export function handleClientEventFlatBuffer(bytes: Uint8Array, handlers: ClientEventHandlers): void {
    const {
        onSystemMessage,
        onNarrativeMessage,
        onPresentMessage,
        onUnpresentMessage,
        onDataMessage,
        onPlayerSwitched,
        onCredentialsUpdated,
        lastEventTimestampRef,
        onInputMetadata,
    } = handlers;

    try {
        dispatchClientEvent(bytes, {
            onNarrativeEventMessage: (narrative) => {
                const event = narrative.event();
                if (!event) {
                    console.error("[WS] Missing narrative event");
                    return;
                }
                const eventId = narrativeEventIdHex(narrative);

                const timestampNanos = event.timestamp();
                const timestamp = new Date(Number(timestampNanos) / 1000000).toISOString();

                if (lastEventTimestampRef) {
                    if (lastEventTimestampRef.current !== null && timestampNanos < lastEventTimestampRef.current) {
                        console.warn(
                            `[WS] OUT OF ORDER MESSAGE DETECTED! Current: ${timestampNanos}, Previous: ${lastEventTimestampRef.current}, Diff: ${
                                lastEventTimestampRef.current - timestampNanos
                            }ns`,
                        );
                    }
                    lastEventTimestampRef.current = timestampNanos;
                }

                const parsedNarrativeEvent = parseWsNarrativeEventMessage(
                    narrative,
                    (value) => new MoorVar(value).toJS(),
                    (value) => new MoorVar(value).asString(),
                );
                if (!parsedNarrativeEvent) {
                    console.warn("[WS] Unknown or invalid inner narrative event");
                    return;
                }

                switch (parsedNarrativeEvent.kind) {
                    case "notify":
                        if (onNarrativeMessage) {
                            const mergedEventMetadata = eventId
                                ? { ...(parsedNarrativeEvent.eventMeta ?? {}), eventId }
                                : { ...(parsedNarrativeEvent.eventMeta ?? {}) };
                            onNarrativeMessage(
                                parsedNarrativeEvent.content,
                                timestamp,
                                parsedNarrativeEvent.contentType,
                                false,
                                parsedNarrativeEvent.noNewline,
                                parsedNarrativeEvent.presentationHint,
                                parsedNarrativeEvent.groupId,
                                parsedNarrativeEvent.ttsText,
                                parsedNarrativeEvent.thumbnail,
                                parsedNarrativeEvent.linkPreview,
                                mergedEventMetadata,
                                parsedNarrativeEvent.rewritable,
                                parsedNarrativeEvent.rewriteTarget,
                            );
                        }
                        break;
                    case "present":
                        if (onPresentMessage) {
                            onPresentMessage({ ...parsedNarrativeEvent.presentData, eventId });
                        }
                        break;
                    case "unpresent":
                        if (parsedNarrativeEvent.presentationId && onUnpresentMessage) {
                            onUnpresentMessage(parsedNarrativeEvent.presentationId);
                        }
                        break;
                    case "traceback":
                        if (onNarrativeMessage) {
                            onNarrativeMessage(
                                parsedNarrativeEvent.tracebackText,
                                timestamp,
                                "text/traceback",
                                false,
                                false,
                                undefined,
                                undefined,
                                undefined,
                                undefined,
                                undefined,
                                undefined,
                            );
                        }
                        break;
                    case "data":
                        onDataMessage?.({
                            namespace: parsedNarrativeEvent.namespace,
                            eventKind: parsedNarrativeEvent.eventKind,
                            payload: parsedNarrativeEvent.payload,
                            timestamp,
                            eventId,
                        });
                        break;
                }
            },
            onSystemMessageEvent: (sysMsg) => {
                const message = sysMsg.message();
                if (message && onSystemMessage) {
                    onSystemMessage(message, 5);
                }
            },
            onRequestInputEvent: (requestInput) => {
                const metadataPairs = [];
                const metadataLength = requestInput.metadataLength();
                for (let i = 0; i < metadataLength; i++) {
                    const pair = requestInput.metadata(i);
                    if (pair) {
                        metadataPairs.push(pair);
                    }
                }

                const metadata = parseInputMetadata(metadataPairs.length > 0 ? metadataPairs : null);
                if (onInputMetadata) {
                    onInputMetadata(metadata);
                }
            },
            onTaskErrorEvent: (taskError) => {
                handlers.onTaskComplete?.();
                const error = taskError.error();
                if (!error) {
                    console.error("[WS] Missing scheduler error");
                    return;
                }
                handleTaskError(error, onNarrativeMessage);
            },
            onTaskSuccessEvent: () => {
                handlers.onTaskComplete?.();
            },
            onCredentialsUpdatedEvent: (credentials) => {
                const update = decodeCredentialsUpdatedEvent(credentials);
                if (!update) {
                    console.warn("[WS] CredentialsUpdatedEvent missing fields");
                    return;
                }
                onCredentialsUpdated?.(update);
            },
            onPlayerSwitchedEvent: (playerSwitched) => {
                const identity = decodePlayerSwitchedEvent(playerSwitched);
                if (!identity) {
                    console.error("[WS] PlayerSwitchedEvent missing player or auth token");
                    return;
                }
                onPlayerSwitched?.(identity);
            },
            onUnknownEvent: (eventType) => {
                console.warn(`[WS] Unknown event type: ${eventType}`);
            },
            onMalformedEvent: (eventType, expected) => {
                console.error(`[WS] Failed to parse ${expected} for event type ${eventType}`);
            },
        });
    } catch (err) {
        console.error("[WS] Failed to parse ClientEvent FlatBuffer:", err);
    }
}
