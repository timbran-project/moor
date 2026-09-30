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

import type { NarrativeMessageHandler } from "@moor/web-sdk";
import { buildWsAttach } from "@moor/web-sdk";
import type { PlayerIdentityUpdate } from "@moor/web-sdk";
import { useCallback, useEffect, useRef, useState } from "react";
import {
    isClientSessionActive,
    readReconnectCredentials,
    ReconnectCredentials,
    setClientSessionActive,
} from "../lib/auth-session";
import { DataMessageHandlerEvent, handleClientEventFlatBuffer } from "../lib/rpc-fb";
import { getWebSocketBaseUrl } from "../lib/serverConfig";
import { InputMetadata } from "../types/input";
import { PresentationData } from "../types/presentation";
import { Player } from "./useAuth";

// Application-level keepalive interval (45s) to prevent proxy idle timeouts
// WebSocket-level pings don't count as traffic for proxies like Cloudflare
const KEEPALIVE_INTERVAL_MS = 45000;
const HANDSHAKE_TIMEOUT_MS = 15000;
const AUTH_CHECK_TIMEOUT_MS = 5000;
const RECONNECT_DELAY_MS = 3000;
// Single zero byte marker - definitely not a valid FlatBuffer (needs >= 4 bytes)
const KEEPALIVE_MARKER = new Uint8Array([0x00]);

// Application-level heartbeat markers
// Server sends 0x02 to request heartbeat, client responds with 0x01
// This proves JavaScript is actually processing messages (unlike WS ping/pong)
const HEARTBEAT_REQUEST = 0x02;
const HEARTBEAT_RESPONSE = new Uint8Array([0x01]);
const RESUME_STALE_THRESHOLD_MS = 120000;
const RESUME_RECONNECT_COOLDOWN_MS = 10000;

/** Correlate attempts even on HTTP development origins without randomUUID. */
function createHandshakeId(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return Array.from(
        bytes,
        (byte, index) => ([4, 6, 8, 10].includes(index) ? "-" : "") + byte.toString(16).padStart(2, "0"),
    ).join("");
}

export interface WebSocketState {
    socket: WebSocket | null;
    isConnected: boolean;
    connectionStatus: "disconnected" | "connecting" | "connected" | "error";
    connectionError?: string;
}

export const useWebSocket = (
    player: Player | null,
    onSystemMessage: (message: string, duration?: number) => void,
    onPlayerConnectedChange?: (connected: boolean) => void,
    onPlayerSwitched?: (identity: PlayerIdentityUpdate) => void,
    onCredentialsUpdated?: (credentials: ReconnectCredentials) => void,
    onNarrativeMessage?: NarrativeMessageHandler,
    onPresentMessage?: (presentData: PresentationData) => void,
    onUnpresentMessage?: (id: string) => void,
    onDataMessage?: (event: DataMessageHandlerEvent) => void,
    onAuthFailure?: () => void,
    onInitialAttachComplete?: () => void,
) => {
    const [wsState, setWsState] = useState<WebSocketState>({
        socket: null,
        isConnected: false,
        connectionStatus: "disconnected",
    });

    const [stateRevision, setStateRevision] = useState(0);
    const [inputMetadata, setInputMetadata] = useState<InputMetadata | null>(null);

    const socketRef = useRef<WebSocket | null>(null);
    const reconnectTimeoutRef = useRef<number | null>(null);
    const handshakeTimeoutRef = useRef<number | null>(null);
    const authCheckRef = useRef<AbortController | null>(null);
    const attemptGenerationRef = useRef(0);

    const keepaliveIntervalRef = useRef<number | null>(null);
    const lastEventTimestampRef = useRef<bigint | null>(null);
    const processingRef = useRef<Promise<void>>(Promise.resolve());
    const isDisconnectingRef = useRef(false);
    const connectionStatusRef = useRef<WebSocketState["connectionStatus"]>("disconnected");
    const hasEverConnectedRef = useRef(false);
    // Ref to current connect function - used by reconnect timeout to avoid stale closures
    const connectRef = useRef<((mode: "connect" | "create", force?: boolean) => Promise<void>) | null>(null);
    const lastConnectModeRef = useRef<"connect" | "create">("connect");
    const lastSocketActivityAtRef = useRef<number>(Date.now());
    const lastResumeReconnectAtRef = useRef<number>(0);

    const stopConnection = useCallback(() => {
        attemptGenerationRef.current++;
        for (const ref of [handshakeTimeoutRef, reconnectTimeoutRef, keepaliveIntervalRef]) {
            if (ref.current !== null) clearTimeout(ref.current);
            ref.current = null;
        }
        authCheckRef.current?.abort();
        authCheckRef.current = null;
        const ws = socketRef.current;
        socketRef.current = null;
        if (!ws) return;
        ws.onopen = null;
        ws.onmessage = null;
        ws.onerror = null;
        ws.onclose = null;
        ws.close(1000, "Closing connection");
    }, []);

    useEffect(() => {
        connectionStatusRef.current = wsState.connectionStatus;
    }, [wsState.connectionStatus]);

    // Handle incoming WebSocket messages
    const handleMessage = useCallback(async (event: MessageEvent) => {
        // Queue message processing to ensure sequential handling
        // This prevents race conditions when async processing causes reordering
        processingRef.current = processingRef.current.then(async () => {
            try {
                // All messages are now binary FlatBuffer format
                if (event.data instanceof ArrayBuffer || event.data instanceof Blob) {
                    // Convert Blob to ArrayBuffer if needed
                    const arrayBuffer = event.data instanceof Blob
                        ? await event.data.arrayBuffer()
                        : event.data;

                    const data = new Uint8Array(arrayBuffer);

                    // Check for heartbeat request (single byte 0x02)
                    // Server sends this to verify JS is processing; we must respond with 0x01
                    if (data.byteLength === 1 && data[0] === HEARTBEAT_REQUEST) {
                        lastSocketActivityAtRef.current = Date.now();
                        if (socketRef.current?.readyState === WebSocket.OPEN) {
                            socketRef.current.send(HEARTBEAT_RESPONSE);
                        }
                        return;
                    }

                    lastSocketActivityAtRef.current = Date.now();

                    handleClientEventFlatBuffer(data, {
                        onSystemMessage,
                        onNarrativeMessage,
                        onPresentMessage,
                        onUnpresentMessage,
                        onDataMessage: event => {
                            onDataMessage?.(event);
                            if (event.namespace === "state" && event.eventKind === "room_snapshot") {
                                setStateRevision(value => value + 1);
                            }
                        },
                        onTaskComplete: () => setStateRevision(value => value + 1),
                        onPlayerSwitched,
                        onCredentialsUpdated,
                        lastEventTimestampRef,
                        onInputMetadata: setInputMetadata,
                    });
                } else {
                    console.error("Unexpected non-binary WebSocket message:", event.data);
                }
            } catch (error) {
                console.error("Failed to parse WebSocket message:", error);
            }
        });
    }, [
        onSystemMessage,
        onNarrativeMessage,
        onPresentMessage,
        onUnpresentMessage,
        onDataMessage,
        onPlayerSwitched,
        onCredentialsUpdated,
    ]);

    // Connect to WebSocket
    const connect = useCallback(async (mode: "connect" | "create", force: boolean = false) => {
        if (!player || !player.authToken) {
            console.error("[WebSocket] Cannot connect: No player or auth token");
            return;
        }

        if (isDisconnectingRef.current) {
            console.warn("[WebSocket] Cannot connect: Disconnect in progress");
            return;
        }

        if (!force && socketRef.current?.readyState === WebSocket.OPEN) {
            console.debug("[WebSocket] Already connected, skipping");
            return;
        }

        stopConnection();
        const generation = attemptGenerationRef.current;
        const attempt = createHandshakeId();
        const startedAt = performance.now();
        const logTiming = (phase: string, code?: number) => {
            const elapsedMs = Math.round(performance.now() - startedAt);
            const noteworthy = phase === "timed_out" || phase === "creation_failed"
                || phase === "session_validation_unavailable"
                || (phase === "closed" && code !== 1000)
                || (phase === "session_validated" && code !== 200)
                || (phase === "opened" && elapsedMs >= 1000);
            if (!noteworthy && import.meta.env.VITE_WS_DEBUG !== "true") return;
            const write = noteworthy ? console.warn : console.debug;
            write(
                "[WebSocket] handshake",
                JSON.stringify({
                    attempt,
                    phase,
                    at: new Date().toISOString(),
                    elapsedMs,
                    ...(code === undefined ? {} : { code }),
                }),
            );
        };
        const scheduleReconnect = () => {
            if (generation !== attemptGenerationRef.current) return;
            reconnectTimeoutRef.current = window.setTimeout(() => {
                reconnectTimeoutRef.current = null;
                if (generation === attemptGenerationRef.current) {
                    void connectRef.current?.("connect");
                }
            }, RECONNECT_DELAY_MS);
        };
        lastConnectModeRef.current = mode;

        try {
            setWsState(prev => ({ ...prev, connectionStatus: "connecting", connectionError: undefined }));
            onSystemMessage("Establishing connection...", 2);

            // Build WebSocket URL
            const { host: baseUrl, secure: isSecure } = getWebSocketBaseUrl();

            const reconnectCredentials = readReconnectCredentials();
            const clientToken = reconnectCredentials?.clientToken ?? null;
            const clientId = reconnectCredentials?.clientId ?? null;
            // Session active flag is retained for telemetry/coordination only.
            // Reattach hints are per-tab and should be sent whenever credentials exist.
            const sessionActive = isClientSessionActive();
            const includeClientHint = reconnectCredentials !== null;

            if (player.isInitialAttach) {
                console.debug("[WebSocket] Initial attach - will trigger user_connected");
            }
            if (includeClientHint) {
                console.debug("[WebSocket] Reconnecting with existing client_id:", clientId);
            } else {
                console.debug("[WebSocket] New connection (no stored tokens)");
            }
            console.debug("[WebSocket] Attach decision:", {
                mode,
                force,
                isInitialAttach: player.isInitialAttach,
                sessionActive,
                hasClientId: !!clientId,
                hasClientToken: !!clientToken,
                includeClientHint,
            });

            const wsBaseUrl = `${isSecure ? "wss://" : "ws://"}${baseUrl}`;
            const { wsUrl, protocols: wsProtocols } = buildWsAttach(wsBaseUrl, {
                mode,
                credentials: {
                    authToken: player.authToken,
                    isInitialAttach: player.isInitialAttach,
                    clientId: includeClientHint ? clientId : null,
                    clientToken: includeClientHint ? clientToken : null,
                },
            });

            const url = new URL(wsUrl);
            url.searchParams.set("attempt", attempt);
            logTiming("starting");
            const ws = new WebSocket(url.toString(), wsProtocols);
            socketRef.current = ws;
            let opened = false;
            const clearHandshakeTimeout = () => {
                if (handshakeTimeoutRef.current !== null) {
                    clearTimeout(handshakeTimeoutRef.current);
                    handshakeTimeoutRef.current = null;
                }
            };
            handshakeTimeoutRef.current = window.setTimeout(() => {
                if (socketRef.current !== ws || opened) return;
                clearHandshakeTimeout();
                logTiming("timed_out");
                // Retire this attempt before closing: late events must not affect its replacement.
                socketRef.current = null;
                ws.onopen = null;
                ws.onmessage = null;
                ws.onerror = null;
                ws.onclose = null;
                ws.close();
                setWsState({
                    socket: null,
                    isConnected: false,
                    connectionStatus: "error",
                    connectionError: "Connection timed out after 15 seconds",
                });
                onPlayerConnectedChange?.(false);
                scheduleReconnect();
            }, HANDSHAKE_TIMEOUT_MS);

            // Set up event handlers
            ws.onopen = () => {
                if (socketRef.current !== ws) return;
                opened = true;
                clearHandshakeTimeout();
                logTiming("opened");
                lastSocketActivityAtRef.current = Date.now();
                setWsState(prev => ({
                    ...prev,
                    socket: ws,
                    isConnected: true,
                    connectionStatus: "connected",
                    connectionError: undefined,
                }));
                onSystemMessage("Connected!", 2);
                setClientSessionActive(true);
                hasEverConnectedRef.current = true;

                // Update player connection status
                if (onPlayerConnectedChange) {
                    onPlayerConnectedChange(true);
                }

                // Notify parent to update isInitialAttach based on history encryption
                if (player?.isInitialAttach && onInitialAttachComplete) {
                    onInitialAttachComplete();
                }

                // Clear any reconnection timeout
                if (reconnectTimeoutRef.current) {
                    clearTimeout(reconnectTimeoutRef.current);
                    reconnectTimeoutRef.current = null;
                }

                // Start application-level keepalive to prevent proxy idle timeouts
                if (keepaliveIntervalRef.current) {
                    clearInterval(keepaliveIntervalRef.current);
                }
                keepaliveIntervalRef.current = window.setInterval(() => {
                    if (ws.readyState === WebSocket.OPEN) {
                        ws.send(KEEPALIVE_MARKER);
                    }
                }, KEEPALIVE_INTERVAL_MS);
            };

            ws.onmessage = handleMessage;

            ws.onerror = () => {
                if (socketRef.current !== ws) return;
                logTiming("error");
            };

            ws.onclose = async (event) => {
                if (socketRef.current !== ws) return;
                clearHandshakeTimeout();
                logTiming("closed", event.code);
                socketRef.current = null;
                setWsState({
                    socket: null,
                    isConnected: false,
                    connectionStatus: event.code === 1000 ? "disconnected" : "error",
                    connectionError: event.code === 1000
                        ? undefined
                        : opened
                        ? "Connection to server lost"
                        : "Unable to connect to server",
                });

                if (keepaliveIntervalRef.current) {
                    clearInterval(keepaliveIntervalRef.current);
                    keepaliveIntervalRef.current = null;
                }
                if (event.reason === "LOGOUT") setClientSessionActive(false);
                onPlayerConnectedChange?.(false);
                if (event.code === 1000) return;

                let unauthorized = event.code === 4401;
                // Browsers hide failed upgrade HTTP statuses behind close code 1006.
                // A transport failure alone is not evidence that credentials have expired.
                if (!opened && !unauthorized) {
                    const controller = new AbortController();
                    authCheckRef.current = controller;
                    const timer = window.setTimeout(() => controller.abort(), AUTH_CHECK_TIMEOUT_MS);
                    logTiming("validating_session");
                    try {
                        const response = await fetch("/auth/validate", {
                            headers: { "X-Moor-Auth-Token": player.authToken },
                            signal: controller.signal,
                        });
                        unauthorized = response.status === 401;
                        logTiming("session_validated", response.status);
                    } catch {
                        logTiming("session_validation_unavailable");
                    } finally {
                        clearTimeout(timer);
                        if (authCheckRef.current === controller) authCheckRef.current = null;
                    }
                }
                if (generation !== attemptGenerationRef.current) return;
                if (unauthorized) {
                    setWsState(prev => ({ ...prev, connectionError: "Session expired — please log in again" }));
                    onSystemMessage("Session expired — please log in again", 5);
                    onAuthFailure?.();
                    return;
                }
                scheduleReconnect();
            };
        } catch (error) {
            logTiming("creation_failed");
            setWsState(prev => ({
                ...prev,
                connectionStatus: "error",
                connectionError: "Unable to connect to server",
            }));
            scheduleReconnect();
            onSystemMessage(
                `Connection error: ${error instanceof Error ? error.message : "Unknown error"}`,
                5,
            );
        }
    }, [
        stopConnection,
        handleMessage,
        onAuthFailure,
        onInitialAttachComplete,
        onPlayerConnectedChange,
        onSystemMessage,
        player,
    ]);

    // Keep connectRef updated so reconnect timeouts use current function
    useEffect(() => {
        connectRef.current = connect;
    }, [connect]);

    useEffect(() => {
        if (typeof window === "undefined" || typeof document === "undefined") {
            return;
        }

        const maybeReconnectOnResume = () => {
            if (document.hidden) {
                return;
            }
            if (!hasEverConnectedRef.current) {
                return;
            }
            if (isDisconnectingRef.current) {
                return;
            }
            if (socketRef.current?.readyState !== WebSocket.OPEN) {
                return;
            }

            const now = Date.now();
            const idleMs = now - lastSocketActivityAtRef.current;
            if (idleMs < RESUME_STALE_THRESHOLD_MS) {
                console.debug("[WebSocket] Resume check skipped (fresh activity)", {
                    idleMs,
                    thresholdMs: RESUME_STALE_THRESHOLD_MS,
                });
                return;
            }

            const sinceLastResumeReconnect = now - lastResumeReconnectAtRef.current;
            if (sinceLastResumeReconnect < RESUME_RECONNECT_COOLDOWN_MS) {
                console.debug("[WebSocket] Resume check skipped (cooldown)", {
                    sinceLastResumeReconnect,
                    cooldownMs: RESUME_RECONNECT_COOLDOWN_MS,
                });
                return;
            }

            console.debug("[WebSocket] Resume-triggered reconnect", {
                idleMs,
                sinceLastResumeReconnect,
                socketState: socketRef.current?.readyState,
            });
            lastResumeReconnectAtRef.current = now;
            onSystemMessage("Resuming connection...", 2);
            // Always reconnect as "connect" -- create is one-time for new accounts.
            connectRef.current?.("connect", true);
        };

        const handleVisibility = () => {
            if (!document.hidden) {
                maybeReconnectOnResume();
            }
        };

        window.addEventListener("focus", maybeReconnectOnResume);
        window.addEventListener("online", maybeReconnectOnResume);
        document.addEventListener("visibilitychange", handleVisibility);

        return () => {
            window.removeEventListener("focus", maybeReconnectOnResume);
            window.removeEventListener("online", maybeReconnectOnResume);
            document.removeEventListener("visibilitychange", handleVisibility);
        };
    }, [onSystemMessage]);

    // Disconnect from WebSocket
    const disconnect = useCallback((reason?: string) => {
        isDisconnectingRef.current = true;
        stopConnection();

        setWsState({ socket: null, isConnected: false, connectionStatus: "disconnected" });
        if (reason === "LOGOUT") {
            setClientSessionActive(false);
        }

        // Allow reconnect after a short delay
        setTimeout(() => {
            isDisconnectingRef.current = false;
        }, 100);
    }, [stopConnection]);

    // Send message (text string or binary data)
    const sendMessage = useCallback((message: string | Uint8Array | ArrayBuffer) => {
        if (socketRef.current?.readyState === WebSocket.OPEN) {
            // WebSocket does not accept views over shared memory.
            if (message instanceof Uint8Array && !(message.buffer instanceof ArrayBuffer)) {
                throw new TypeError("WebSocket messages must use an ArrayBuffer");
            }
            socketRef.current.send(message as string | Uint8Array<ArrayBuffer> | ArrayBuffer);
            return true;
        } else {
            onSystemMessage("Not connected to server", 3);
            return false;
        }
    }, [onSystemMessage]);

    // Clear input metadata
    const clearInputMetadata = useCallback(() => {
        setInputMetadata(null);
    }, []);

    useEffect(() => stopConnection, [stopConnection]);

    // Reset state when player becomes null (logout)
    useEffect(() => {
        if (!player) {
            stopConnection();
            // Clear WebSocket state for new login
            setWsState({
                socket: null,
                isConnected: false,
                connectionStatus: "disconnected",
            });
            lastEventTimestampRef.current = null;
            hasEverConnectedRef.current = false;
        }
    }, [player, stopConnection]);

    return {
        stateRevision,
        wsState,
        connect,
        disconnect,
        sendMessage,
        inputMetadata,
        clearInputMetadata,
    };
};
