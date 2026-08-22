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

import { ClientSuccess } from "@moor/schema/generated/moor-rpc/client-success";
import { unionToDaemonToClientReplyUnion } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply-union";
import { LoginResult } from "@moor/schema/generated/moor-rpc/login-result";
import { ReplyResult } from "@moor/schema/generated/moor-rpc/reply-result";
import { ReplyResultUnion, unionToReplyResultUnion } from "@moor/schema/generated/moor-rpc/reply-result-union";
import * as flatbuffers from "flatbuffers";
import { useCallback, useEffect, useState } from "react";
import {
    AuthSession,
    clearAuthSession,
    persistAuthSession,
    persistReconnectCredentials,
    readAuthSession,
    readReconnectCredentials,
    ReconnectCredentials,
} from "../lib/auth-session";
import { generateKeypairFromPassword } from "../lib/keyDerivation";
import { objToCurie } from "../lib/var";

export interface Player {
    oid: string;
    authToken: string;
    historyOid: string;
    historyAuthToken: string;
    connected: boolean;
    flags: number;
    clientToken?: string | null;
    clientId?: string | null;
    isInitialAttach?: boolean;
    lastSwitchSilent?: boolean;
    lastSwitchPreservedHistory?: boolean;
}

export interface AuthState {
    player: Player | null;
    isConnecting: boolean;
    error: string | null;
}

export const useAuth = (onSystemMessage: (message: string, duration?: number) => void) => {
    const [authState, setAuthState] = useState<AuthState>({
        player: null,
        isConnecting: false,
        error: null,
    });

    // Check for auth credentials in localStorage on mount and validate them
    useEffect(() => {
        const validateAndRestore = async () => {
            const session = readAuthSession();
            if (!session) {
                console.log("No user session - requiring fresh login");
                clearAuthSession();
                return;
            }

            // Check if event log encryption is set up for this player
            const eventLogEncryptionKey = localStorage.getItem(
                `moor_event_log_identity_${session.historyPlayerOid}`,
            );
            const hasEventLogEncryption = eventLogEncryptionKey !== null;

            // Validate the stored auth token with the server
            // Client credentials are optional - new tabs won't have them
            try {
                const headers: Record<string, string> = {
                    "X-Moor-Auth-Token": session.authToken,
                };
                // Only include client credentials if we have them (same tab reload)
                if (session.reconnectCredentials) {
                    headers["X-Moor-Client-Token"] = session.reconnectCredentials.clientToken;
                    headers["X-Moor-Client-Id"] = session.reconnectCredentials.clientId;
                }

                const response = await fetch("/auth/validate", {
                    method: "GET",
                    headers,
                });

                if (!response.ok) {
                    // Validation failed - auth token expired or invalid
                    console.log("Auth token validation failed - clearing credentials");
                    clearAuthSession();
                    return;
                }

                // Auth token is valid - restore session
                // Client credentials may be null (new tab) - WebSocket will create new connection
                setAuthState({
                    player: {
                        oid: session.playerOid,
                        authToken: session.authToken,
                        historyOid: session.historyPlayerOid,
                        historyAuthToken: session.historyAuthToken,
                        connected: false,
                        flags: session.playerFlags,
                        clientToken: session.reconnectCredentials?.clientToken,
                        clientId: session.reconnectCredentials?.clientId,
                        // New tab (no client credentials) = new connection = trigger :user_connected
                        // Same tab reload with credentials = reattach = no :user_connected
                        // Also: if no event log encryption, treat as initial to trigger :user_connected
                        isInitialAttach: !session.reconnectCredentials || !hasEventLogEncryption,
                    },
                    isConnecting: false,
                    error: null,
                });

                onSystemMessage(
                    hasEventLogEncryption
                        ? "Restoring session..."
                        : "Session restored",
                    2,
                );
            } catch (error) {
                console.error("Error validating auth token:", error);
                onSystemMessage("Error restoring session", 3);
            }
        };

        validateAndRestore();
    }, [onSystemMessage]);

    const establishSession = useCallback((session: AuthSession, isInitialAttach = true) => {
        persistAuthSession(session);
        setAuthState({
            player: {
                oid: session.playerOid,
                authToken: session.authToken,
                historyOid: session.historyPlayerOid,
                historyAuthToken: session.historyAuthToken,
                connected: false,
                flags: session.playerFlags,
                clientToken: session.reconnectCredentials?.clientToken,
                clientId: session.reconnectCredentials?.clientId,
                isInitialAttach,
            },
            isConnecting: false,
            error: null,
        });
    }, []);

    const connect = useCallback(async (
        mode: "connect" | "create",
        username: string,
        password: string,
        encryptPassword?: string,
    ) => {
        let generatedIdentity: string | null = null;

        try {
            setAuthState(prev => ({ ...prev, isConnecting: true, error: null }));

            // Validate inputs
            if (!username.trim()) {
                onSystemMessage("Please enter a username", 3);
                return;
            }

            if (!password) {
                onSystemMessage("Please enter a password", 3);
                return;
            }

            // Build authentication request
            const url = `/auth/${mode}`;
            const data = new URLSearchParams();
            data.set("player", username.trim());
            data.set("password", password);

            // For create mode, generate encryption keypair using username as salt
            // This is done BEFORE the server request so the pubkey can be bundled with account creation
            // Use provided encryption password or fall back to account password
            if (mode === "create") {
                onSystemMessage("Setting up encryption...", 2);
                const effectiveEncryptPassword = encryptPassword || password;
                try {
                    const { identity, publicKey } = await generateKeypairFromPassword(
                        effectiveEncryptPassword,
                        username.trim(),
                    );
                    generatedIdentity = identity;
                    data.set("event_log_pubkey", publicKey);
                    console.log("Generated encryption keypair for new account");
                } catch (keyError) {
                    console.error("Failed to generate encryption keypair:", keyError);
                    // Continue without encryption - user can set it up later
                }
            }

            // Show connecting status
            onSystemMessage("Connecting to server...", 2);

            // Send authentication request
            const result = await fetch(url, {
                method: "POST",
                body: data,
            });

            // Handle HTTP errors
            if (!result.ok) {
                const errorMessage = result.status === 401
                    ? "Invalid username or password"
                    : `Failed to connect (${result.status}: ${result.statusText})`;

                console.error(`Authentication failed: ${result.status}`, result);
                onSystemMessage(errorMessage, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error: errorMessage }));
                return;
            }

            // Parse FlatBuffer response
            const arrayBuffer = await result.arrayBuffer();
            const bytes = new Uint8Array(arrayBuffer);
            const replyResult = ReplyResult.getRootAsReplyResult(
                new flatbuffers.ByteBuffer(bytes),
            );
            const authToken = result.headers.get("X-Moor-Auth-Token");
            const clientToken = result.headers.get("X-Moor-Client-Token");
            const clientId = result.headers.get("X-Moor-Client-Id");

            // Validate authentication token
            if (!authToken) {
                const error = "Authentication failed: No token received";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            // Extract player info from LoginResult
            const resultType = replyResult.resultType();
            if (resultType !== ReplyResultUnion.ClientSuccess) {
                const error = `Authentication failed: ${ReplyResultUnion[resultType]}`;
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const clientSuccess = unionToReplyResultUnion(
                resultType,
                (obj) => replyResult.result(obj),
            ) as ClientSuccess | null;

            if (!clientSuccess) {
                const error = "Authentication failed: Failed to parse response";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const daemonReply = clientSuccess.reply();
            if (!daemonReply) {
                const error = "Authentication failed: Missing daemon reply";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const replyType = daemonReply.replyType();
            const replyUnion = unionToDaemonToClientReplyUnion(
                replyType,
                (obj: any) => daemonReply.reply(obj),
            );

            if (!replyUnion || !(replyUnion instanceof LoginResult)) {
                const error = "Authentication failed: Invalid login result";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const loginResult = replyUnion as LoginResult;

            if (!loginResult.success()) {
                const error = "Authentication failed: Login not successful";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const playerObj = loginResult.player();
            if (!playerObj) {
                const error = "Authentication failed: No player object";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const playerOid = objToCurie(playerObj);
            if (!playerOid) {
                const error = "Authentication failed: Invalid player object";
                console.error(error);
                onSystemMessage(error, 5);
                setAuthState(prev => ({ ...prev, isConnecting: false, error }));
                return;
            }

            const playerFlags = loginResult.playerFlags() || 0;

            // For create mode, store the generated encryption identity keyed by playerOid
            if (mode === "create" && generatedIdentity) {
                const storageKey = `moor_event_log_identity_${playerOid}`;
                localStorage.setItem(storageKey, generatedIdentity);
                console.log("Stored encryption identity for new account:", playerOid);
            }

            const reconnectCredentials = clientToken && clientId
                ? { clientToken, clientId }
                : null;
            establishSession({
                playerOid,
                authToken,
                historyPlayerOid: playerOid,
                historyAuthToken: authToken,
                playerFlags,
                reconnectCredentials,
            });

            // Check if user has history encryption to show appropriate message
            const hasHistory = localStorage.getItem(`moor_event_log_identity_${playerOid}`) !== null;
            onSystemMessage(hasHistory ? "Authenticated! Loading history..." : "Authenticated!", 2);

            // TODO: Fetch and display historical events and current presentations
            // WebSocket connection will be handled by useWebSocket hook
        } catch (error) {
            const errorMessage = `Connection error: ${error instanceof Error ? error.message : "Unknown error"}`;
            console.error("Connection error:", error);
            onSystemMessage(errorMessage, 5);
            setAuthState(prev => ({
                ...prev,
                isConnecting: false,
                error: errorMessage,
            }));
        }
    }, [establishSession, onSystemMessage]);

    const disconnect = useCallback(() => {
        clearAuthSession();

        setAuthState({
            player: null,
            isConnecting: false,
            error: null,
        });
        onSystemMessage("Disconnected", 2);
    }, [onSystemMessage]);

    const setPlayerConnected = useCallback((connected: boolean) => {
        setAuthState(prev => ({
            ...prev,
            player: prev.player ? { ...prev.player, connected } : null,
        }));
    }, []);

    const updateReconnectCredentials = useCallback((credentials: ReconnectCredentials) => {
        persistReconnectCredentials(credentials);
        setAuthState(prev => ({
            ...prev,
            player: prev.player
                ? {
                    ...prev.player,
                    clientId: credentials.clientId,
                    clientToken: credentials.clientToken,
                }
                : null,
        }));
    }, []);

    const rotatePlayerIdentity = useCallback(async (
        playerOid: string,
        authToken: string,
        silent: boolean,
        preserveHistory: boolean,
    ) => {
        const reconnectCredentials = readReconnectCredentials();
        const previousSession = readAuthSession();
        const historyPlayerOid = preserveHistory
            ? previousSession?.historyPlayerOid ?? previousSession?.playerOid ?? playerOid
            : playerOid;
        const historyAuthToken = preserveHistory
            ? previousSession?.historyAuthToken ?? previousSession?.authToken ?? authToken
            : authToken;
        persistAuthSession({
            playerOid,
            authToken,
            historyPlayerOid,
            historyAuthToken,
            playerFlags: 0,
            reconnectCredentials,
        });

        setAuthState(prev => ({
            ...prev,
            player: {
                oid: playerOid,
                authToken,
                historyOid: historyPlayerOid,
                historyAuthToken,
                flags: 0,
                connected: prev.player?.connected ?? true,
                clientId: reconnectCredentials?.clientId,
                clientToken: reconnectCredentials?.clientToken,
                isInitialAttach: false,
                lastSwitchSilent: silent,
                lastSwitchPreservedHistory: preserveHistory,
            },
        }));

        try {
            const response = await fetch("/auth/validate", {
                method: "GET",
                headers: { "X-Moor-Auth-Token": authToken },
            });
            if (!response.ok) {
                console.warn("Unable to refresh player flags after player switch");
                return;
            }

            const validatedPlayer = response.headers.get("X-Moor-Player");
            if (validatedPlayer && validatedPlayer !== playerOid) {
                console.warn("Player switch validation returned a different player");
                return;
            }

            const flagsHeader = response.headers.get("X-Moor-Player-Flags");
            const flags = flagsHeader === null ? Number.NaN : Number.parseInt(flagsHeader, 10);
            if (!Number.isFinite(flags)) {
                console.warn("Player switch validation did not return player flags");
                return;
            }

            const currentSession = readAuthSession();
            if (currentSession?.authToken !== authToken || currentSession.playerOid !== playerOid) {
                return;
            }
            persistAuthSession({
                playerOid,
                authToken,
                historyPlayerOid: currentSession.historyPlayerOid,
                historyAuthToken: currentSession.historyAuthToken,
                playerFlags: flags,
                reconnectCredentials: readReconnectCredentials(),
            });
            setAuthState(prev => {
                if (prev.player?.authToken !== authToken || prev.player.oid !== playerOid) {
                    return prev;
                }
                return {
                    ...prev,
                    player: { ...prev.player, flags },
                };
            });
        } catch (error) {
            console.warn("Unable to refresh player flags after player switch", error);
        }
    }, []);

    const clearInitialAttach = useCallback(() => {
        setAuthState(prev => {
            if (!prev.player) return prev;
            // Check if user has history encryption - if not, keep isInitialAttach true
            // so reconnects will trigger user_connected (otherwise they'd see a blank page)
            const hasEventLogEncryption = localStorage.getItem(
                `moor_event_log_identity_${prev.player.oid}`,
            ) !== null;
            return {
                ...prev,
                player: { ...prev.player, isInitialAttach: !hasEventLogEncryption },
            };
        });
    }, []);

    return {
        authState,
        connect,
        disconnect,
        establishSession,
        setPlayerConnected,
        updateReconnectCredentials,
        rotatePlayerIdentity,
        clearInitialAttach,
    };
};
