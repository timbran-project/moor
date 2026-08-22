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

import { DataEvent } from "@moor/schema/generated/moor-common/data-event";
import { EventUnion } from "@moor/schema/generated/moor-common/event-union";
import { NotifyEvent } from "@moor/schema/generated/moor-common/notify-event";
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
} from "@moor/web-sdk";
import type { MutableRefObject } from "react";

import { InputMetadata } from "../types/input";
import { PresentationData } from "../types/presentation";
import { parseInputMetadata } from "./input-metadata.js";
import { MoorVar } from "./MoorVar.js";
import { EventMetadata, LinkPreview, NarrativeMessageHandler } from "./rpc-fb-shared";

export interface DataMessageHandlerEvent {
    namespace: string;
    eventKind: string;
    payload: unknown;
    timestamp: string;
    eventId?: string;
}

function tryDecodeDataMessageFromNarrative(
    narrative: any,
): { namespace: string; eventKind: string; payload: unknown } | null {
    try {
        const narrativeEvent = narrative?.event?.();
        const eventUnion = narrativeEvent?.event?.();
        if (!eventUnion || eventUnion.eventType() !== EventUnion.DataEvent) {
            return null;
        }

        const data = eventUnion.event(new DataEvent()) as DataEvent | null;
        if (!data) {
            return null;
        }

        const namespace = data.domain()?.value();
        const eventKind = data.kind()?.value();
        const payloadRef = data.payload();
        if (!namespace || !eventKind || !payloadRef) {
            return null;
        }

        return {
            namespace,
            eventKind,
            payload: new MoorVar(payloadRef as any).toJS(),
        };
    } catch {
        return null;
    }
}

function narrativeEventIdHex(narrative: any): string | undefined {
    const eventIdBytes: Uint8Array | null | undefined = narrative?.event?.()?.eventId?.()?.dataArray?.();
    if (!eventIdBytes || eventIdBytes.length === 0) {
        return undefined;
    }
    return Array.from(eventIdBytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extractNotifyMetadataAugments(
    narrative: any,
): { lookKind?: string; lookRoom?: unknown; deliveryId?: string; delivery_id?: string } {
    try {
        const event = narrative?.event?.();
        if (!event) {
            return {};
        }
        const eventData = event.event();
        if (!eventData) {
            return {};
        }
        const notify = eventData.event(new NotifyEvent()) as NotifyEvent | null;
        if (!notify) {
            return {};
        }

        let lookKind: string | undefined;
        let lookRoom: unknown = undefined;
        let deliveryId: string | undefined;
        const metadataLength = notify.metadataLength();
        for (let i = 0; i < metadataLength; i++) {
            const metadata = notify.metadata(i);
            if (!metadata) {
                continue;
            }
            const key = metadata.key()?.value();
            if (!key) {
                continue;
            }
            const rawValue = metadata.value();
            const decodedValue = rawValue ? new MoorVar(rawValue as any).toJS() : null;
            if (key === "look_kind" && typeof decodedValue === "string") {
                lookKind = decodedValue;
                continue;
            }
            if (key === "look_room") {
                lookRoom = decodedValue;
                continue;
            }
            if (key === "delivery_id" && typeof decodedValue === "string") {
                deliveryId = decodedValue;
            }
        }
        return { lookKind, lookRoom, deliveryId, delivery_id: deliveryId };
    } catch {
        return {};
    }
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
                    (value) => new MoorVar(value as any).toJS(),
                    (value) => new MoorVar(value as any).asString(),
                );
                if (!parsedNarrativeEvent) {
                    if (onDataMessage) {
                        const decodedData = tryDecodeDataMessageFromNarrative(narrative);
                        if (decodedData) {
                            onDataMessage({
                                namespace: decodedData.namespace,
                                eventKind: decodedData.eventKind,
                                payload: decodedData.payload,
                                timestamp,
                                eventId,
                            });
                            return;
                        }
                    }
                    console.warn("[WS] Unknown or invalid inner narrative event");
                    return;
                }

                switch (parsedNarrativeEvent.kind) {
                    case "notify":
                        if (onNarrativeMessage) {
                            const metadataAugments = extractNotifyMetadataAugments(narrative);
                            const mergedEventMetadata = eventId
                                ? { ...(parsedNarrativeEvent.eventMeta ?? {}), ...metadataAugments, eventId }
                                : { ...(parsedNarrativeEvent.eventMeta ?? {}), ...metadataAugments };
                            onNarrativeMessage(
                                parsedNarrativeEvent.content as string | string[],
                                timestamp,
                                parsedNarrativeEvent.contentType || undefined,
                                false,
                                parsedNarrativeEvent.noNewline,
                                parsedNarrativeEvent.presentationHint,
                                parsedNarrativeEvent.groupId,
                                parsedNarrativeEvent.ttsText,
                                parsedNarrativeEvent.thumbnail,
                                parsedNarrativeEvent.linkPreview as LinkPreview | undefined,
                                mergedEventMetadata as EventMetadata,
                                parsedNarrativeEvent.rewritable,
                                parsedNarrativeEvent.rewriteTarget,
                            );
                        }
                        break;
                    case "present":
                        if (onPresentMessage) {
                            onPresentMessage(parsedNarrativeEvent.presentData);
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
                    default:
                        // Meadow may typecheck against a web-sdk release that does not yet
                        // include kind: "data" in the ParsedWsNarrativeEvent union.
                        // Probe dynamically so runtime data events still flow through.
                        if (onDataMessage) {
                            const maybeData = parsedNarrativeEvent as {
                                kind?: string;
                                namespace?: string;
                                eventKind?: string;
                                payload?: unknown;
                            };
                            if (
                                maybeData.kind === "data"
                                && typeof maybeData.namespace === "string"
                                && typeof maybeData.eventKind === "string"
                            ) {
                                console.debug("[WS] DataEvent (dynamic path)", {
                                    namespace: maybeData.namespace,
                                    eventKind: maybeData.eventKind,
                                    payloadType: typeof maybeData.payload,
                                    eventId,
                                    timestamp,
                                });
                                onDataMessage({
                                    namespace: maybeData.namespace,
                                    eventKind: maybeData.eventKind,
                                    payload: maybeData.payload,
                                    timestamp,
                                    eventId,
                                });
                            }
                        }
                        // Future narrative event kinds may be non-visual state channels.
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
                const error = taskError.error();
                if (!error) {
                    console.error("[WS] Missing scheduler error");
                    return;
                }
                handleTaskError(error, onNarrativeMessage);
            },
            onTaskSuccessEvent: (_taskSuccess) => {
                // Task completed successfully - these now come via HTTP response for verb invocations
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
