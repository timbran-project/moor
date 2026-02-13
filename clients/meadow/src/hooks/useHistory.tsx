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

import { parseHistoricalNarrativeEvent, toPresentationData } from "@moor/web-sdk";
import { useCallback, useRef, useState } from "react";
import { NarrativeMessage } from "../components/Narrative";
import { MoorVar } from "../lib/MoorVar";
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

export const useHistory = (authToken: string | null, encryptionKey: string | null = null) => {
    const [historyBoundary, setHistoryBoundary] = useState<number | null>(null);
    const [earliestHistoryEventId, setEarliestHistoryEventId] = useState<string | null>(null);
    const [isLoadingHistory, setIsLoadingHistory] = useState(false);
    const lastPresentationActionsRef = useRef<HistoryPresentationAction[]>([]);

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

    const convertFlatBufferHistoricalEvent = useCallback((event: HistoryEvent): ConvertedHistoricalEvent => {
        try {
            const narrativeEvent = event.narrative_event;
            const eventId = event.event_id;
            const timestamp = event.timestamp;

            const parsedEvent = parseHistoricalNarrativeEvent(
                narrativeEvent,
                (value) => new MoorVar(value as any).toJS(),
                (value) => new MoorVar(value as any).asString(),
            );
            if (!parsedEvent) {
                return { message: null };
            }

            switch (parsedEvent.kind) {
                case "present":
                    return {
                        message: null,
                        presentationAction: {
                            kind: "present",
                            data: toPresentationData(parsedEvent.presentation),
                        },
                    };
                case "unpresent":
                    return {
                        message: null,
                        presentationAction: {
                            kind: "unpresent",
                            id: parsedEvent.presentationId,
                        },
                    };
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
                            content: parsedEvent.content as string | string[],
                            type: "narrative",
                            timestamp,
                            isHistorical: true,
                            contentType: parsedEvent.contentType,
                            presentationHint: parsedEvent.presentationHint,
                            groupId: parsedEvent.groupId,
                            thumbnail: parsedEvent.thumbnail,
                            eventMetadata: parsedEvent.deliveryId
                                ? { deliveryId: parsedEvent.deliveryId, delivery_id: parsedEvent.deliveryId }
                                : undefined,
                        },
                    };
            }
        } catch (error) {
            console.error("Failed to convert FlatBuffer event:", error);
            return { message: null };
        }
    }, []);

    // Fetch history from API
    const fetchHistory = useCallback(async (
        limit: number = 100,
        sinceSeconds?: number,
        untilEvent?: string,
    ): Promise<NarrativeMessage[]> => {
        if (!authToken) {
            throw new Error("No auth token available");
        }

        setIsLoadingHistory(true);

        try {
            // Use FlatBuffer endpoint with client-side decryption
            const events = await fetchHistoryFlatBuffer(
                authToken,
                encryptionKey,
                limit,
                sinceSeconds,
                untilEvent,
            );

            // Convert events to narrative messages
            const narrativeMessages: NarrativeMessage[] = [];
            const presentationActions: HistoryPresentationAction[] = [];
            for (const event of events) {
                const converted = convertFlatBufferHistoricalEvent(event);
                if (converted.presentationAction) {
                    presentationActions.push(converted.presentationAction);
                }
                const message = converted.message;
                if (message) {
                    narrativeMessages.push(message);
                }
            }
            lastPresentationActionsRef.current = presentationActions;

            // Filter out MCP sequences before returning
            const filteredMessages = filterMCPSequences(narrativeMessages);

            // Update earliest event ID for pagination
            if (events.length > 0) {
                setEarliestHistoryEventId(events[0].event_id);
            }

            return filteredMessages;
        } catch (error) {
            console.error("Failed to fetch more history:", error);
            throw error;
        } finally {
            setIsLoadingHistory(false);
        }
    }, [authToken, convertFlatBufferHistoricalEvent, encryptionKey]);

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
    const fetchInitialHistory = useCallback(async (): Promise<NarrativeMessage[]> => {
        const dynamicLimit = calculateInitialLoad();
        return await fetchHistory(dynamicLimit, 86400); // 24 hours = 86400 seconds
    }, [fetchHistory, calculateInitialLoad]);

    // Fetch more history for infinite scroll
    const fetchMoreHistory = useCallback(async (): Promise<NarrativeMessage[]> => {
        if (!earliestHistoryEventId) {
            return [];
        }
        return await fetchHistory(50, undefined, earliestHistoryEventId);
    }, [fetchHistory, earliestHistoryEventId]);

    const consumePresentationActions = useCallback((): HistoryPresentationAction[] => {
        if (lastPresentationActionsRef.current.length === 0) {
            return [];
        }
        const actions = lastPresentationActionsRef.current;
        lastPresentationActionsRef.current = [];
        return actions;
    }, []);

    return {
        historyBoundary,
        setHistoryBoundaryNow,
        isHistoricalDuplicate,
        fetchInitialHistory,
        fetchMoreHistory,
        consumePresentationActions,
        isLoadingHistory,
    };
};
