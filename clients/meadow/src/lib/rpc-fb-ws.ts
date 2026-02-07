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

import { SchedulerError } from "@moor/schema/generated/moor-rpc/scheduler-error";
import { SchedulerErrorUnion } from "@moor/schema/generated/moor-rpc/scheduler-error-union";
import { dispatchClientEvent, parseWsNarrativeEventMessage, schedulerErrorToNarrative } from "@moor/web-sdk";

import { parseInputMetadata } from "./input-metadata.js";
import { MoorVar } from "./MoorVar.js";
import { EventMetadata, LinkPreview, NarrativeMessageHandler } from "./rpc-fb-shared";

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
                                parsedNarrativeEvent.eventMeta as EventMetadata | undefined,
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
