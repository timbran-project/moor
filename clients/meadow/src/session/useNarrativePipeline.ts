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

import { useCallback, useRef, useState } from "react";
import { NarrativeRef } from "../components/Narrative";
import { usePresentationContext } from "../context/PresentationContext";
import { useMCPHandler } from "../hooks/useMCPHandler";
import { readReconnectCredentials } from "../lib/auth-session";
import { roomSnapshotToPresentation } from "../lib/room-snapshot-presentation";
import { DataMessageHandlerEvent } from "../lib/rpc-fb";
import type { EventMetadata, LinkPreview } from "../lib/rpc-fb";
import type { EditorLaunchBridge } from "./editorLaunchBridge";
import { NarrativeMessageContent } from "./narrativePipelineTypes";

const LIVE_EVENT_DIAG_RETENTION_MS = 5 * 60 * 1000;

export interface WebSocketEventHandlers {
    handleNarrativeMessage: (
        content: string | string[],
        timestamp?: string,
        contentType?: string,
        isHistorical?: boolean,
        noNewline?: boolean,
        presentationHint?: string,
        groupId?: string,
        ttsText?: string,
        thumbnail?: { contentType: string; data: string },
        linkPreview?: LinkPreview,
        eventMetadata?: EventMetadata,
    ) => void;
    handlePresentMessage: (presentData: import("../types/presentation").PresentationData) => void;
    handleUnpresentMessage: (id: string) => void;
    handleDataMessage: (event: DataMessageHandlerEvent) => void;
}

/**
 * Owns the narrative ingestion pipeline between the WebSocket and the
 * transcript: MCP command filtering, buffering for messages that arrive before
 * the narrative surface mounts, duplicate live-event diagnostics, and
 * room-snapshot data messages converted into presentations.
 *
 * Takes the editor launch bridge directly: this hook runs above the bridge's
 * context provider (inside SessionCoordinator), so it cannot consume it.
 */
export const useNarrativePipeline = (bridge: EditorLaunchBridge) => {
    const { addPresentation, removePresentation } = usePresentationContext();

    const narrativeRef = useRef<NarrativeRef | null>(null);
    const recentLiveEventIdsRef = useRef<Map<string, { count: number; firstSeenAt: number; lastSeenAt: number }>>(
        new Map(),
    );

    const [pendingMessages, setPendingMessages] = useState<NarrativeMessageContent[]>([]);

    // MCP handler for parsing edit commands; editors are launched through the shared bridge
    const { handleNarrativeMessage: mcpHandler } = useMCPHandler(
        (title, objectCurie, verbName, content, uploadAction) => {
            const showVerbEditor = bridge.current.showVerbEditor;
            if (showVerbEditor) {
                showVerbEditor(title, objectCurie, verbName, content, uploadAction);
            }
        },
        (title, objectCurie, propertyName, content, uploadAction) => {
            const showPropertyEditor = bridge.current.showPropertyEditor;
            if (showPropertyEditor) {
                showPropertyEditor(title, objectCurie, propertyName, content, uploadAction);
            }
        },
    );

    const appendToNarrativeOrBuffer = useCallback((message: NarrativeMessageContent) => {
        const {
            content,
            contentType,
            noNewline,
            presentationHint,
            groupId,
            ttsText,
            thumbnail,
            linkPreview,
            eventMetadata,
            rewritable,
            rewriteTarget,
            eventTimestampMs,
        } = message;
        if (narrativeRef.current) {
            narrativeRef.current.addNarrativeContent(
                content as string | string[],
                contentType as "text/plain" | "text/djot" | "text/html",
                noNewline,
                presentationHint,
                groupId,
                ttsText,
                thumbnail,
                linkPreview,
                eventMetadata,
                rewritable,
                rewriteTarget,
                eventTimestampMs,
            );
        } else {
            setPendingMessages(prev => [...prev, message]);
        }
    }, []);

    const handleNarrativeMessage = useCallback((
        content: string | string[],
        timestamp?: string,
        contentType?: string,
        isHistorical?: boolean,
        noNewline?: boolean,
        presentationHint?: string,
        groupId?: string,
        ttsText?: string,
        thumbnail?: { contentType: string; data: string },
        linkPreview?: LinkPreview,
        eventMetadata?: EventMetadata,
        rewritable?: { id: string; owner: string; ttl: number; fallback?: string },
        rewriteTarget?: string,
    ) => {
        const parsedTimestamp = timestamp ? new Date(timestamp).getTime() : NaN;
        const eventTimestampMs = Number.isFinite(parsedTimestamp) ? parsedTimestamp : undefined;
        const metadata = eventMetadata as {
            eventId?: string;
            verb?: string;
        } | undefined;
        const liveEventId = metadata?.eventId;
        if (!isHistorical && liveEventId) {
            const now = Date.now();
            const recentIds = recentLiveEventIdsRef.current;
            if (recentIds.size > 2048) {
                for (const [id, entry] of recentIds.entries()) {
                    if ((now - entry.lastSeenAt) > LIVE_EVENT_DIAG_RETENTION_MS) {
                        recentIds.delete(id);
                    }
                }
            }

            const existing = recentIds.get(liveEventId);
            if (existing) {
                existing.count += 1;
                existing.lastSeenAt = now;
                console.warn("[WS] Duplicate live eventId observed", {
                    eventId: liveEventId,
                    seenCount: existing.count,
                    sinceFirstMs: now - existing.firstSeenAt,
                    clientId: readReconnectCredentials()?.clientId ?? null,
                });
            } else {
                recentIds.set(liveEventId, {
                    count: 1,
                    firstSeenAt: now,
                    lastSeenAt: now,
                });
            }
        }

        if (Array.isArray(content)) {
            // Handle array content by filtering out MCP lines and showing the rest
            const filteredContent: string[] = [];
            for (const line of content) {
                // If mcpHandler returns false, the line was not MCP-related and should be shown
                if (!mcpHandler(line, isHistorical || false)) {
                    filteredContent.push(line);
                }
            }

            // Only add content if there are non-MCP lines
            if (filteredContent.length > 0) {
                appendToNarrativeOrBuffer({
                    content: filteredContent,
                    contentType,
                    noNewline,
                    presentationHint,
                    groupId,
                    ttsText,
                    thumbnail,
                    linkPreview,
                    eventMetadata,
                    rewritable,
                    rewriteTarget,
                    eventTimestampMs,
                });
            }
        } else {
            if (!mcpHandler(content, isHistorical || false)) {
                appendToNarrativeOrBuffer({
                    content,
                    contentType,
                    noNewline,
                    presentationHint,
                    groupId,
                    ttsText,
                    thumbnail,
                    linkPreview,
                    eventMetadata,
                    rewritable,
                    rewriteTarget,
                    eventTimestampMs,
                });
            }
        }
    }, [appendToNarrativeOrBuffer, mcpHandler]);

    const handlePresentMessage = useCallback((presentData: import("../types/presentation").PresentationData) => {
        addPresentation(presentData);
    }, [addPresentation]);

    const handleUnpresentMessage = useCallback((id: string) => {
        removePresentation(id);
    }, [removePresentation]);

    const handleDataMessage = useCallback((event: DataMessageHandlerEvent) => {
        console.debug("[Meadow] handleDataMessage received", {
            namespace: event.namespace,
            eventKind: event.eventKind,
            payloadType: typeof event.payload,
            payloadIsArray: Array.isArray(event.payload),
            payloadKeys: event.payload && typeof event.payload === "object" && !Array.isArray(event.payload)
                ? Object.keys(event.payload as Record<string, unknown>)
                : [],
            timestamp: event.timestamp,
            eventId: event.eventId,
        });

        if (event.namespace !== "state" || event.eventKind !== "room_snapshot") {
            console.debug("[Meadow] handleDataMessage ignored (namespace/kind mismatch)", {
                namespace: event.namespace,
                eventKind: event.eventKind,
            });
            return;
        }

        const presentation = roomSnapshotToPresentation(event.payload);
        if (!presentation) {
            console.debug("[Meadow] room_snapshot payload rejected by roomSnapshotToPresentation", {
                payload: event.payload,
            });
            return;
        }
        console.debug("[Meadow] room_snapshot converted to presentation", {
            id: presentation.id,
            target: presentation.target,
            attributes: presentation.attributes,
        });
        addPresentation(presentation);
    }, [addPresentation]);

    // Flush buffered messages when the narrative surface becomes available.
    // The callback must stay identity-stable: SessionCoordinator publishes it
    // once through a ref-backed context, so it reads the current buffer
    // through a ref instead of closing over state.
    const pendingMessagesRef = useRef(pendingMessages);
    pendingMessagesRef.current = pendingMessages;

    const narrativeCallbackRef = useCallback((node: NarrativeRef | null) => {
        if (node) {
            for (const message of pendingMessagesRef.current) {
                node.addNarrativeContent(
                    message.content as string | string[],
                    message.contentType as "text/plain" | "text/djot" | "text/html",
                    message.noNewline,
                    message.presentationHint,
                    message.groupId,
                    message.ttsText,
                    message.thumbnail,
                    message.linkPreview,
                    message.eventMetadata,
                    message.rewritable,
                    message.rewriteTarget,
                    message.eventTimestampMs,
                );
            }
            if (pendingMessagesRef.current.length > 0) {
                setPendingMessages([]);
            }
        }
        narrativeRef.current = node;
    }, []);

    return {
        narrativeRef,
        narrativeCallbackRef,
        handlers: {
            handleNarrativeMessage,
            handlePresentMessage,
            handleUnpresentMessage,
            handleDataMessage,
        } satisfies WebSocketEventHandlers,
    };
};
