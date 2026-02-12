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

import { NotifyEvent } from "@moor/schema/generated/moor-common/notify-event";
import { ClientEvent } from "@moor/schema/generated/moor-rpc/client-event";
import { ClientEventUnion } from "@moor/schema/generated/moor-rpc/client-event-union";
import { CredentialsUpdatedEvent } from "@moor/schema/generated/moor-rpc/credentials-updated-event";
import { SchedulerError } from "@moor/schema/generated/moor-rpc/scheduler-error";
import { SchedulerErrorUnion } from "@moor/schema/generated/moor-rpc/scheduler-error-union";
import { dispatchClientEvent, parseWsNarrativeEventMessage, schedulerErrorToNarrative } from "@moor/web-sdk";
import * as flatbuffers from "flatbuffers";

import { parseInputMetadata } from "./input-metadata.js";
import { MoorVar } from "./MoorVar.js";
import { EventMetadata, LinkPreview, NarrativeMessageHandler } from "./rpc-fb-shared";

function uuidBytesToString(bytes: Uint8Array): string | null {
    if (bytes.length !== 16) {
        return null;
    }

    const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function maybeHandleCredentialsUpdatedEvent(bytes: Uint8Array): boolean {
    try {
        const event = ClientEvent.getRootAsClientEvent(new flatbuffers.ByteBuffer(bytes));
        if (event.eventType() !== ClientEventUnion.CredentialsUpdatedEvent) {
            return false;
        }

        const creds = event.event(new CredentialsUpdatedEvent());
        if (!creds) {
            console.warn("[WS] CredentialsUpdatedEvent missing payload");
            return true;
        }

        const clientToken = creds.clientToken()?.token();
        const clientIdBytes = creds.clientId()?.dataArray();
        const clientId = clientIdBytes ? uuidBytesToString(clientIdBytes) : null;

        if (!clientToken || !clientId) {
            console.warn("[WS] CredentialsUpdatedEvent missing fields");
            return true;
        }

        sessionStorage.setItem("client_token", clientToken);
        sessionStorage.setItem("client_id", clientId);
        console.log("[WS] Updated session credentials from server event", { clientId });
        return true;
    } catch (error) {
        console.error("[WS] Failed to decode CredentialsUpdatedEvent:", error);
        return false;
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

export function handleClientEventFlatBuffer(
    bytes: Uint8Array,
    onSystemMessage?: (message: string, duration?: number) => void,
    onNarrativeMessage?: NarrativeMessageHandler,
    onPresentMessage?: (presentData: any) => void,
    onUnpresentMessage?: (id: string) => void,
    onPlayerFlagsChange?: (flags: number) => void,
    lastEventTimestampRef?: React.MutableRefObject<bigint | null>,
    onInputMetadata?: (metadata: import("../types/input").InputMetadata | null) => void,
): void {
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
            onUnknownEvent: (eventType) => {
                if (eventType === ClientEventUnion.CredentialsUpdatedEvent) {
                    if (maybeHandleCredentialsUpdatedEvent(bytes)) {
                        return;
                    }
                }
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
