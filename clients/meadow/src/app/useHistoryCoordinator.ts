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

import { RefObject, useCallback, useEffect, useRef, useState } from "react";
import { NarrativeMessage, NarrativeRef } from "../components/Narrative";
import { usePresentationContext } from "../context/PresentationContext";
import { useWebSocketContext } from "../context/WebSocketContext";
import { useHistory } from "../hooks/useHistory";
import { computeHistoryBatchSignature, isRedundantHistoryBatch } from "./historyBatch";

const MIN_HIDDEN_DURATION_MS = 30000;
const RESYNC_COOLDOWN_MS = 2 * 60 * 1000;
const RECENT_ACTIVITY_WINDOW_MS = 60 * 1000;

export interface HistoryCoordinatorArgs {
    authToken: string | null;
    historyAuthToken: string | null;
    encryptionKeyForHistory: string | null;
    encryptionHasCheckedOnce: boolean;
    encryptionStatusError: unknown;
    eventLogEnabled: boolean | null;
    loginMode: "connect" | "create";
    narrativeRef: RefObject<NarrativeRef | null>;
    showMessage: (message: string, duration?: number) => void;
}

/**
 * Owns the encrypted event-history lifecycle: when it is safe to load, the
 * initial load and background resyncs, batch deduplication, presentation
 * restoration from historical events, pagination, and reload triggers after
 * tab visibility changes or WebSocket reconnects. Also connects the WebSocket
 * once history work has settled.
 */
export const useHistoryCoordinator = ({
    authToken,
    historyAuthToken,
    encryptionKeyForHistory,
    encryptionHasCheckedOnce,
    encryptionStatusError,
    eventLogEnabled,
    loginMode,
    narrativeRef,
    showMessage,
}: HistoryCoordinatorArgs) => {
    const [historyLoaded, setHistoryLoaded] = useState(false);
    const [pendingHistoricalMessages, setPendingHistoricalMessages] = useState<NarrativeMessage[]>([]);

    const historyResyncInFlightRef = useRef(false);
    const lastHistoryResyncAtRef = useRef<number>(0);
    const lastLiveNarrativeAtRef = useRef<number>(Date.now());
    const lastHistoryBatchSignatureRef = useRef<string | null>(null);
    const lastHistoryBatchAppliedAtRef = useRef<number>(0);
    // Track if a history reload is a background resync (skip toast) vs initial load (show toast)
    const isHistoryResyncRef = useRef(false);

    // Monotonic generation for history work. Captured when work is scheduled;
    // bumped whenever the identity changes or a reload is requested, so results
    // from an older generation are discarded instead of mutating the new session.
    const historyGenerationRef = useRef(0);
    const scheduledTimersRef = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());

    /** Bumps the generation and cancels every timer that has not fired yet. */
    const invalidateScheduledWork = useCallback(() => {
        historyGenerationRef.current += 1;
        historyResyncInFlightRef.current = false;
        for (const id of scheduledTimersRef.current) {
            clearTimeout(id);
        }
        scheduledTimersRef.current.clear();
    }, []);

    /** Schedules deferred history work tagged with the current generation. */
    const scheduleTimers = useCallback((fn: () => void, delayMs: number) => {
        const generation = historyGenerationRef.current;
        const id = setTimeout(() => {
            scheduledTimersRef.current.delete(id);
            if (historyGenerationRef.current !== generation) {
                return;
            }
            fn();
        }, delayMs);
        scheduledTimersRef.current.add(id);
    }, []);

    // Cancel pending timers and invalidate in-flight continuations on unmount.
    useEffect(() => {
        return invalidateScheduledWork;
    }, [invalidateScheduledWork]);

    const { addPresentation, removePresentation, fetchCurrentPresentations } = usePresentationContext();
    const { wsState, connect: connectWS } = useWebSocketContext();

    const {
        setHistoryBoundaryNow,
        fetchInitialHistory,
        fetchMoreHistory,
        resetHistoryRequestState,
        isLoadingHistory,
    } = useHistory(historyAuthToken, encryptionKeyForHistory);

    /** Requests a full history reload on the next pass (e.g. after unlock/setup),
     *  discarding any historical messages not yet attached to the transcript and
     *  invalidating work already scheduled for the previous key. */
    const markHistoryForReload = useCallback(() => {
        invalidateScheduledWork();
        resetHistoryRequestState(true);
        setHistoryLoaded(false);
        setPendingHistoricalMessages([]);
    }, [invalidateScheduledWork, resetHistoryRequestState]);

    /** Records that live narrative activity happened, throttling visibility resyncs. */
    const noteLiveActivity = useCallback(() => {
        lastLiveNarrativeAtRef.current = Date.now();
    }, []);

    // Invalidate scheduled/in-flight history work whenever the identity changes so
    // requests from a prior player can never mutate the new session (#494 mechanism)
    const previousHistoryAuthTokenRef = useRef(historyAuthToken);
    useEffect(() => {
        const historyIdentityChanged = previousHistoryAuthTokenRef.current !== historyAuthToken;
        previousHistoryAuthTokenRef.current = historyAuthToken;
        invalidateScheduledWork();
        resetHistoryRequestState(historyIdentityChanged);
    }, [authToken, historyAuthToken, invalidateScheduledWork, resetHistoryRequestState]);

    // Load history and connect WebSocket after authentication
    useEffect(() => {
        if (!authToken || eventLogEnabled === null) {
            return;
        }

        if (!historyLoaded && eventLogEnabled === false) {
            setHistoryLoaded(true);
            if (!wsState.isConnected) {
                scheduleTimers(() => connectWS(loginMode), 100);
            }
            return;
        }

        if (historyLoaded || !encryptionHasCheckedOnce) {
            return;
        }

        if (eventLogEnabled && !historyLoaded) {
            if (encryptionStatusError) {
                setHistoryLoaded(true);
                showMessage("History is unavailable; continuing without it", 4);
                if (!wsState.isConnected) {
                    scheduleTimers(() => connectWS(loginMode), 100);
                }
                return;
            }

            if (!encryptionKeyForHistory) {
                console.error(
                    "[HistoryError] No encryption key available. Cannot load history. User must set up encryption.",
                );
                historyResyncInFlightRef.current = false;
                setHistoryLoaded(true);
                if (!wsState.isConnected) {
                    scheduleTimers(() => connectWS(loginMode), 100);
                }
                return;
            }

            console.log("[HistoryDebug] Loading history with encryption key");
            setHistoryLoaded(true);
            const lastMsgTimestamp = narrativeRef.current?.getLastMessageTimestamp() || 0;
            setHistoryBoundaryNow(lastMsgTimestamp);

            // Capture the generation at request start; results from an older
            // generation (identity changed, unlock rekeyed, etc.) are discarded
            const generation = historyGenerationRef.current;
            const isCurrent = () => historyGenerationRef.current === generation;

            scheduleTimers(() => {
                fetchInitialHistory(isCurrent)
                    .then(async (result) => {
                        if (!result || !isCurrent()) {
                            return;
                        }
                        const historicalMessages = result.messages;
                        const historyPresentationActions = result.presentationActions;
                        const signature = computeHistoryBatchSignature(historicalMessages);
                        const now = Date.now();
                        const isRedundantBatch = isRedundantHistoryBatch(
                            signature,
                            lastHistoryBatchSignatureRef.current,
                            lastHistoryBatchAppliedAtRef.current,
                            now,
                        );

                        if (isRedundantBatch) {
                            console.log("[History] Skipping redundant history batch", {
                                count: historicalMessages.length,
                                sinceLastMs: now - lastHistoryBatchAppliedAtRef.current,
                            });
                        } else {
                            if (historyPresentationActions.length > 0) {
                                historyPresentationActions.forEach((action) => {
                                    if (action.kind === "present") {
                                        addPresentation(action.data);
                                        return;
                                    }
                                    removePresentation(action.id);
                                });
                            }
                            setPendingHistoricalMessages(historicalMessages);
                            lastHistoryBatchSignatureRef.current = signature;
                            lastHistoryBatchAppliedAtRef.current = now;
                        }

                        // Show toast for initial load, but not for background resyncs
                        if (historicalMessages.length > 0 && !isHistoryResyncRef.current) {
                            showMessage("History loaded successfully", 2);
                        }
                        isHistoryResyncRef.current = false;

                        try {
                            await fetchCurrentPresentations(authToken, encryptionKeyForHistory, isCurrent);
                        } catch {
                            // ignore
                        }

                        if (!isCurrent()) {
                            return;
                        }

                        if (!wsState.isConnected) {
                            connectWS(loginMode);
                        }
                    })
                    .catch(async (_error) => {
                        if (!isCurrent()) {
                            return;
                        }
                        if (!isHistoryResyncRef.current) {
                            showMessage("Failed to load history, continuing anyway...", 3);
                        }
                        isHistoryResyncRef.current = false;

                        try {
                            await fetchCurrentPresentations(authToken, encryptionKeyForHistory, isCurrent);
                        } catch {
                            // ignore
                        }

                        if (!isCurrent()) {
                            return;
                        }

                        if (!wsState.isConnected) {
                            connectWS(loginMode);
                        }
                    })
                    .finally(() => {
                        if (isCurrent()) {
                            historyResyncInFlightRef.current = false;
                        }
                    });
            }, 100);
        }
    }, [
        addPresentation,
        authToken,
        connectWS,
        encryptionHasCheckedOnce,
        encryptionKeyForHistory,
        scheduleTimers,
        encryptionStatusError,
        eventLogEnabled,
        fetchCurrentPresentations,
        fetchInitialHistory,
        historyLoaded,
        loginMode,
        narrativeRef,
        removePresentation,
        setHistoryBoundaryNow,
        showMessage,
        wsState.isConnected,
    ]);

    // Track if we were previously connected to distinguish reconnection from initial connection
    const wasConnectedRef = useRef(false);

    // Reset history loaded flag when WebSocket disconnects to ensure history is refetched on reconnection
    // Only reset if we were previously connected (not during initial connection flow)
    useEffect(() => {
        if (wsState.connectionStatus === "connected") {
            wasConnectedRef.current = true;
        } else if (wsState.connectionStatus === "disconnected" && wasConnectedRef.current && historyLoaded) {
            setHistoryLoaded(false);
            wasConnectedRef.current = false;
        }
    }, [wsState.connectionStatus, historyLoaded]);

    // Refs to track current state for visibility handler (avoids re-adding listener on every render)
    const wsConnectedRef = useRef(wsState.isConnected);
    const historyLoadedRef = useRef(historyLoaded);

    useEffect(() => {
        wsConnectedRef.current = wsState.isConnected;
    }, [wsState.isConnected]);

    useEffect(() => {
        historyLoadedRef.current = historyLoaded;
    }, [historyLoaded]);

    // Refetch history when tab becomes visible to catch up on messages missed while backgrounded
    // This handles cases where the websocket reconnected while backgrounded but the fetch was throttled
    // Only triggers if tab was hidden for at least 30 seconds to avoid reload on quick tab switches
    useEffect(() => {
        if (typeof document === "undefined") {
            return;
        }

        let hiddenTimestamp: number | null = null;

        const handleVisibilityChange = () => {
            if (document.hidden) {
                hiddenTimestamp = Date.now();
            } else {
                const wasHiddenLongEnough = hiddenTimestamp !== null
                    && (Date.now() - hiddenTimestamp) >= MIN_HIDDEN_DURATION_MS;
                hiddenTimestamp = null;

                if (wasHiddenLongEnough && wsConnectedRef.current && historyLoadedRef.current) {
                    const now = Date.now();
                    if (historyResyncInFlightRef.current) {
                        return;
                    }
                    if ((now - lastHistoryResyncAtRef.current) < RESYNC_COOLDOWN_MS) {
                        return;
                    }
                    if ((now - lastLiveNarrativeAtRef.current) < RECENT_ACTIVITY_WINDOW_MS) {
                        return;
                    }
                    console.log("[History] Tab became visible after being backgrounded - refetching history");
                    historyResyncInFlightRef.current = true;
                    lastHistoryResyncAtRef.current = now;
                    isHistoryResyncRef.current = true;
                    setHistoryLoaded(false);
                }
            }
        };

        document.addEventListener("visibilitychange", handleVisibilityChange);

        return () => {
            document.removeEventListener("visibilitychange", handleVisibilityChange);
        };
    }, []);

    // Add pending historical messages when narrative component becomes available
    useEffect(() => {
        if (narrativeRef.current && pendingHistoricalMessages.length > 0) {
            narrativeRef.current.addHistoricalMessages(pendingHistoricalMessages);
            setPendingHistoricalMessages([]);
        }
    }, [narrativeRef, pendingHistoricalMessages]);

    // Handle loading more history for infinite scroll
    const handleLoadMoreHistory = useCallback(async () => {
        if (!authToken || isLoadingHistory || eventLogEnabled === false) {
            return;
        }

        const generation = historyGenerationRef.current;
        const isCurrent = () => historyGenerationRef.current === generation;

        try {
            const result = await fetchMoreHistory(isCurrent);

            if (!result || !isCurrent()) {
                return;
            }

            if (result.messages.length > 0) {
                narrativeRef.current?.prependHistoricalMessages(result.messages);
            }
        } catch (error) {
            if (!isCurrent()) {
                return;
            }
            console.warn("Failed to load more history:", error);
        }
    }, [authToken, eventLogEnabled, fetchMoreHistory, isLoadingHistory, narrativeRef]);

    return {
        historyLoaded,
        isLoadingHistory,
        handleLoadMoreHistory,
        markHistoryForReload,
        noteLiveActivity,
    };
};
