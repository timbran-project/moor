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
import { NarrativeMessage } from "../components/Narrative";
import { fetchHistoryFlatBuffer, HistoryEvent } from "../lib/rpc-fb";
import { PresentationData } from "../types/presentation";

// Filter out MCP sequences from historical messages
const filterMCPSequences = (messages: NarrativeMessage[]): NarrativeMessage[] => {
    const filtered: NarrativeMessage[] = [];
    let inMCPSpool = false;

    for (const message of messages) {
        const content = Array.isArray(message.content) ? message.content.join("").trim() : message.content.trim();

        // Filter out ALL MCP messages (anything starting with "#$#")
        if (content.startsWith("#$#")) {
            // Check if this starts an MCP edit sequence
            if (content.startsWith("#$# edit")) {
                inMCPSpool = true;
            }
            continue; // Skip all MCP command lines
        }

        // Check if this ends an MCP spool sequence
        if (inMCPSpool && content === ".") {
            inMCPSpool = false;
            continue; // Skip the terminator
        }

        // Skip any content while we're in an MCP spool
        if (inMCPSpool) {
            continue;
        }

        // Keep all other messages
        filtered.push(message);
    }

    return filtered;
};

type HistoryPresentationAction = {
    kind: "present";
    data: PresentationData;
} | {
    kind: "unpresent";
    id: string;
};

interface ConvertedHistoricalEvent {
    message: NarrativeMessage | null;
    presentationAction?: HistoryPresentationAction;
}

export interface HistoryFetchResult {
    messages: NarrativeMessage[];
    presentationActions: HistoryPresentationAction[];
}

type IsCurrentHistoryRequest = () => boolean;

export const useHistory = (authToken: string | null, encryptionKey: string | null = null) => {
    const [historyBoundary, setHistoryBoundary] = useState<number | null>(null);
    const earliestHistoryEventId = useRef<string | null>(null);
    const paginationInitialized = useRef(false);
    const seenCursors = useRef(new Set<string>());
    const activeRequest = useRef<object | null>(null);
    const [hasMoreHistory, setHasMoreHistory] = useState(false);
    const [isLoadingHistory, setIsLoadingHistory] = useState(false);

    // Set history boundary timestamp to prevent duplicates with WebSocket events
    const setHistoryBoundaryNow = useCallback((lastMessageBeforeDisconnect?: number) => {
        void lastMessageBeforeDisconnect;
        const boundary = Date.now();
        setHistoryBoundary(boundary);
    }, []);

    // Check if a WebSocket event timestamp is before history boundary (duplicate)
    const isHistoricalDuplicate = useCallback((eventTimestamp: number): boolean => {
        return historyBoundary !== null && eventTimestamp < historyBoundary;
    }, [historyBoundary]);

    const convertHistoricalEvent = useCallback((event: HistoryEvent): ConvertedHistoricalEvent => {
        const parsedEvent = event.event;
        const eventId = event.event_id;
        const timestamp = event.timestamp;

        switch (parsedEvent.kind) {
            case "present":
                return { message: null };
            case "unpresent":
                return { message: null };
            case "traceback":
                return {
                    message: {
                        id: `history_${eventId}_${timestamp}`,
                        eventId,
                        content: parsedEvent.tracebackText,
                        type: "narrative",
                        timestamp,
                        isHistorical: true,
                        contentType: "text/traceback",
                    },
                };
            case "notify":
                return {
                    message: {
                        id: `history_${eventId}_${timestamp}`,
                        eventId,
                        content: parsedEvent.content,
                        type: "narrative",
                        timestamp,
                        isHistorical: true,
                        contentType: parsedEvent.contentType,
                        presentationHint: parsedEvent.presentationHint,
                        groupId: parsedEvent.groupId,
                        thumbnail: parsedEvent.thumbnail,
                        eventMetadata: {
                            deliveryId: parsedEvent.eventMeta?.deliveryId,
                            delivery_id: parsedEvent.eventMeta?.deliveryId,
                            annotations: parsedEvent.eventMeta?.annotations,
                            collapseTitle: parsedEvent.eventMeta?.collapseTitle,
                        },
                    },
                };
            default:
                return { message: null };
        }
    }, []);

    // Fetch history from API
    const fetchHistory = useCallback(async (
        limit: number = 100,
        sinceSeconds?: number,
        untilEvent?: string,
        isCurrent: IsCurrentHistoryRequest = () => true,
    ): Promise<HistoryFetchResult | null> => {
        if (!authToken) {
            throw new Error("No auth token available");
        }

        if (!isCurrent() || activeRequest.current) {
            return null;
        }
        const request = {};
        activeRequest.current = request;
        const isCurrentRequest = () => isCurrent() && activeRequest.current === request;
        setIsLoadingHistory(true);

        try {
            // Use FlatBuffer endpoint with client-side decryption
            const page = await fetchHistoryFlatBuffer(
                authToken,
                encryptionKey,
                limit,
                sinceSeconds,
                untilEvent,
            );

            if (!isCurrentRequest()) {
                return null;
            }

            // A time-limited resync must not rewind pagination or reopen an exhausted history.
            if (sinceSeconds === undefined || !paginationInitialized.current) {
                const cursor = page.earliestEventId;
                if (page.eventCount > 0 && (!cursor || seenCursors.current.has(cursor))) {
                    setHasMoreHistory(false);
                    throw new Error("History pagination stopped because the page cursor is missing or repeated");
                }
                paginationInitialized.current = sinceSeconds === undefined || cursor !== null;
                earliestHistoryEventId.current = cursor;
                if (cursor) {
                    seenCursors.current.add(cursor);
                }
                // The initial 24-hour window says nothing about events before that window.
                setHasMoreHistory(page.eventCount > 0 && (sinceSeconds !== undefined || page.hasMoreBefore));
            }

            // Convert events to narrative messages
            const narrativeMessages: NarrativeMessage[] = [];
            const presentationActions: HistoryPresentationAction[] = [];
            for (const event of page.events) {
                const converted = convertHistoricalEvent(event);
                if (converted.presentationAction) {
                    presentationActions.push(converted.presentationAction);
                }
                const message = converted.message;
                if (message) {
                    narrativeMessages.push(message);
                }
            }
            // Filter out MCP sequences before returning
            const filteredMessages = filterMCPSequences(narrativeMessages);

            if (!isCurrentRequest()) {
                return null;
            }

            return {
                messages: filteredMessages,
                presentationActions,
            };
        } catch (error) {
            if (!isCurrentRequest()) {
                return null;
            }
            console.error("Failed to fetch more history:", error);
            throw error;
        } finally {
            if (isCurrentRequest()) {
                activeRequest.current = null;
                setIsLoadingHistory(false);
            }
        }
    }, [authToken, convertHistoricalEvent, encryptionKey]);

    // Calculate optimal initial load based on viewport
    const calculateInitialLoad = useCallback(() => {
        // Estimate messages needed to fill viewport + some overflow for scrolling
        const viewportHeight = window.innerHeight;
        const estimatedMessageHeight = 25; // pixels per line of text
        const messagesNeededToFill = Math.ceil(viewportHeight / estimatedMessageHeight);

        // Add 50% more messages to ensure scrollable content
        const initialLoad = Math.min(Math.max(messagesNeededToFill * 1.5, 20), 100);

        return Math.floor(initialLoad);
    }, []);

    // Fetch initial history on connect (dynamically sized based on viewport)
    const fetchInitialHistory = useCallback(async (
        isCurrent?: IsCurrentHistoryRequest,
    ): Promise<HistoryFetchResult | null> => {
        const dynamicLimit = calculateInitialLoad();
        return await fetchHistory(dynamicLimit, 86400, undefined, isCurrent); // 24 hours = 86400 seconds
    }, [fetchHistory, calculateInitialLoad]);

    // Fetch more history for infinite scroll
    const fetchMoreHistory = useCallback(async (
        isCurrent?: IsCurrentHistoryRequest,
    ): Promise<HistoryFetchResult | null> => {
        if (!hasMoreHistory || !earliestHistoryEventId.current) {
            return { messages: [], presentationActions: [] };
        }
        return await fetchHistory(50, undefined, earliestHistoryEventId.current, isCurrent);
    }, [fetchHistory, hasMoreHistory]);

    /** Clears request-owned state after invalidation. */
    const resetHistoryRequestState = useCallback((resetPagination: boolean = false) => {
        setIsLoadingHistory(false);
        activeRequest.current = null;
        if (resetPagination) {
            earliestHistoryEventId.current = null;
            paginationInitialized.current = false;
            seenCursors.current.clear();
            setHasMoreHistory(false);
        }
    }, []);

    return {
        historyBoundary,
        setHistoryBoundaryNow,
        isHistoricalDuplicate,
        fetchInitialHistory,
        fetchMoreHistory,
        resetHistoryRequestState,
        isLoadingHistory,
        hasMoreHistory,
    };
};
