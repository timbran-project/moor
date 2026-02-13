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

import { buildWsAttach } from "@moor/web-sdk";
import { useCallback, useEffect, useRef, useState } from "react";
import { DataMessageHandlerEvent, EventMetadata, handleClientEventFlatBuffer, LinkPreview } from "../lib/rpc-fb";
import { InputMetadata } from "../types/input";
import { PresentationData } from "../types/presentation";
import { Player } from "./useAuth";

export interface WebSocketState {
    socket: WebSocket | null;
    isConnected: boolean;
    connectionStatus: "disconnected" | "connecting" | "connected" | "error";
}

export const useWebSocket = (
    player: Player | null,
    onSystemMessage: (message: string, duration?: number) => void,
    onPlayerConnectedChange?: (connected: boolean) => void,
    onPlayerFlagsChange?: (flags: number) => void,
    onNarrativeMessage?: (
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
    ) => void,
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

    const [inputMetadata, setInputMetadata] = useState<InputMetadata | null>(null);

    const socketRef = useRef<WebSocket | null>(null);
    const reconnectTimeoutRef = useRef<number | null>(null);
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

    // Application-level keepalive interval (45s) to prevent proxy idle timeouts
    // WebSocket-level pings don't count as traffic for proxies like Cloudflare
    const KEEPALIVE_INTERVAL_MS = 45000;
    // Single zero byte marker - definitely not a valid FlatBuffer (needs >= 4 bytes)
    const KEEPALIVE_MARKER = new Uint8Array([0x00]);

    // Application-level heartbeat markers
    // Server sends 0x02 to request heartbeat, client responds with 0x01
    // This proves JavaScript is actually processing messages (unlike WS ping/pong)
    const HEARTBEAT_REQUEST = 0x02;
    const HEARTBEAT_RESPONSE = new Uint8Array([0x01]);
    const RESUME_STALE_THRESHOLD_MS = 120000;
    const RESUME_RECONNECT_COOLDOWN_MS = 10000;

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

                    handleClientEventFlatBuffer(
                        data,
                        onSystemMessage,
                        onNarrativeMessage,
                        onPresentMessage,
                        onUnpresentMessage,
                        onDataMessage,
                        onPlayerFlagsChange,
                        lastEventTimestampRef,
                        setInputMetadata,
                    );
                } else {
                    console.error("Unexpected non-binary WebSocket message:", event.data);
                }
            } catch (error) {
                console.error("Failed to parse WebSocket message:", error);
            }
        });
    }, [onSystemMessage, onNarrativeMessage, onPresentMessage, onUnpresentMessage, onDataMessage, onPlayerFlagsChange]);

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
            console.log("[WebSocket] Already connected, skipping");
            return;
        }

        console.log("[WebSocket] Starting connection for player:", player.oid);
        lastConnectModeRef.current = mode;

        // If there's an existing socket that's not closed, close it first
        if (socketRef.current && socketRef.current.readyState !== WebSocket.CLOSED) {
            console.warn("[WebSocket] Found existing socket, closing it first. State:", socketRef.current.readyState);
            const oldSocket = socketRef.current;
            socketRef.current = null;
            oldSocket.onopen = null;
            oldSocket.onmessage = null;
            oldSocket.onerror = null;
            oldSocket.onclose = null;
            oldSocket.close(1000, "Replacing with new connection");
        }

        try {
            setWsState(prev => ({ ...prev, connectionStatus: "connecting" }));
            onSystemMessage("Establishing connection...", 2);

            // Build WebSocket URL
            const { host: baseUrl, secure: isSecure } = (await import("../lib/serverConfig")).getWebSocketBaseUrl();

            // Get connection credentials from sessionStorage (per-tab)
            const clientToken = sessionStorage.getItem("client_token");
            const clientId = sessionStorage.getItem("client_id");
            // Session active flag is retained for telemetry/coordination only.
            // Reattach hints are per-tab and should be sent whenever credentials exist.
            const sessionActive = localStorage.getItem("client_session_active") === "true";
            const includeClientHint = !!clientToken && !!clientId;

            if (player.isInitialAttach) {
                console.log("[WebSocket] Initial attach - will trigger user_connected");
            }
            if (includeClientHint) {
                console.log("[WebSocket] Reconnecting with existing client_id:", clientId);
            } else {
                console.log("[WebSocket] New connection (no stored tokens)");
            }
            console.log("[WebSocket] Attach decision:", {
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

            console.log("[WebSocket] Creating new WebSocket to:", wsUrl);
            const ws = new WebSocket(wsUrl, wsProtocols);
            socketRef.current = ws;
            console.log("[WebSocket] Socket created, readyState:", ws.readyState);

            // Set up event handlers
            ws.onopen = () => {
                lastSocketActivityAtRef.current = Date.now();
                setWsState(prev => ({
                    ...prev,
                    socket: ws,
                    isConnected: true,
                    connectionStatus: "connected",
                }));
                onSystemMessage("Connected!", 2);
                localStorage.setItem("client_session_active", "true");
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

            ws.onerror = (_error) => {
                setWsState(prev => ({ ...prev, connectionStatus: "error" }));
                onSystemMessage("Connection error", 5);
            };

            ws.onclose = (event) => {
                setWsState(prev => ({
                    ...prev,
                    socket: null,
                    isConnected: false,
                    connectionStatus: "disconnected",
                }));
                socketRef.current = null;

                // Stop keepalive interval
                if (keepaliveIntervalRef.current) {
                    clearInterval(keepaliveIntervalRef.current);
                    keepaliveIntervalRef.current = null;
                }

                if (event.reason === "LOGOUT") {
                    localStorage.setItem("client_session_active", "false");
                }

                // Update player connection status
                if (onPlayerConnectedChange) {
                    onPlayerConnectedChange(false);
                }

                if (event.code !== 1000) { // 1000 is normal closure
                    // If we've never successfully connected, this is likely an auth failure
                    if (!hasEverConnectedRef.current) {
                        console.log("[WebSocket] Connection failed on initial attempt - likely auth failure");
                        onSystemMessage("Authentication failed - please log in again", 5);
                        if (onAuthFailure) {
                            onAuthFailure();
                        }
                        return;
                    }

                    onSystemMessage(
                        `Connection closed: ${event.reason || "Server disconnected"}`,
                        5,
                    );

                    // Schedule reconnect for non-normal closures (only if we've connected before)
                    // Uses connectRef to get current connect function, avoiding stale closure issues
                    const delay = 3000;
                    if (!reconnectTimeoutRef.current) {
                        reconnectTimeoutRef.current = window.setTimeout(() => {
                            reconnectTimeoutRef.current = null;
                            if (connectionStatusRef.current !== "connected" && connectRef.current) {
                                connectRef.current(mode);
                            }
                        }, delay);
                    }
                }
            };
        } catch (error) {
            console.error("Failed to create WebSocket connection:", error);
            setWsState(prev => ({ ...prev, connectionStatus: "error" }));
            onSystemMessage(
                `Connection error: ${error instanceof Error ? error.message : "Unknown error"}`,
                5,
            );
        }
    }, [handleMessage, onPlayerConnectedChange, onSystemMessage, player, onInitialAttachComplete]);

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
                console.log("[WebSocket] Resume check skipped (fresh activity)", {
                    idleMs,
                    thresholdMs: RESUME_STALE_THRESHOLD_MS,
                });
                return;
            }

            const sinceLastResumeReconnect = now - lastResumeReconnectAtRef.current;
            if (sinceLastResumeReconnect < RESUME_RECONNECT_COOLDOWN_MS) {
                console.log("[WebSocket] Resume check skipped (cooldown)", {
                    sinceLastResumeReconnect,
                    cooldownMs: RESUME_RECONNECT_COOLDOWN_MS,
                });
                return;
            }

            console.log("[WebSocket] Resume-triggered reconnect", {
                idleMs,
                sinceLastResumeReconnect,
                mode: lastConnectModeRef.current,
                socketState: socketRef.current?.readyState,
            });
            lastResumeReconnectAtRef.current = now;
            onSystemMessage("Resuming connection...", 2);
            connectRef.current?.(lastConnectModeRef.current, true);
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

        if (reconnectTimeoutRef.current) {
            clearTimeout(reconnectTimeoutRef.current);
            reconnectTimeoutRef.current = null;
        }

        if (keepaliveIntervalRef.current) {
            clearInterval(keepaliveIntervalRef.current);
            keepaliveIntervalRef.current = null;
        }

        if (socketRef.current) {
            const oldSocket = socketRef.current;
            socketRef.current = null;

            // Remove event handlers to prevent them from firing
            oldSocket.onopen = null;
            oldSocket.onmessage = null;
            oldSocket.onerror = null;
            oldSocket.onclose = null;

            // Close the socket
            oldSocket.close(1000, reason ?? "Manual disconnect");

            // Immediately clear state
            setWsState({
                socket: null,
                isConnected: false,
                connectionStatus: "disconnected",
            });
        }

        if (reason === "LOGOUT") {
            localStorage.setItem("client_session_active", "false");
        }

        // Allow reconnect after a short delay
        setTimeout(() => {
            isDisconnectingRef.current = false;
        }, 100);
    }, []);

    // Send message (text string or binary data)
    const sendMessage = useCallback((message: string | Uint8Array | ArrayBuffer) => {
        if (socketRef.current?.readyState === WebSocket.OPEN) {
            socketRef.current.send(message);
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

    // Cleanup on unmount
    useEffect(() => {
        return () => {
            if (reconnectTimeoutRef.current) {
                clearTimeout(reconnectTimeoutRef.current);
            }
            if (keepaliveIntervalRef.current) {
                clearInterval(keepaliveIntervalRef.current);
            }
            if (socketRef.current) {
                socketRef.current.close(1000, "Component unmounting");
            }
        };
    }, []);

    // Reset state when player becomes null (logout)
    useEffect(() => {
        if (!player) {
            // Clear WebSocket state for new login
            setWsState({
                socket: null,
                isConnected: false,
                connectionStatus: "disconnected",
            });
            lastEventTimestampRef.current = null;
            hasEverConnectedRef.current = false;
        }
    }, [player]);

    return {
        wsState,
        connect,
        disconnect,
        sendMessage,
        inputMetadata,
        clearInputMetadata,
    };
};
