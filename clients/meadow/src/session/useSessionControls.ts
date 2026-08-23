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

import { RefObject, useCallback } from "react";
import { NarrativeRef } from "../components/Narrative";
import { useAuthContext } from "../context/AuthContext";
import { useWebSocketContext } from "../context/WebSocketContext";
import { useOAuth2Session } from "../hooks/useOAuth2Session";
import { AuthSession } from "../lib/auth-session";

/**
 * Owns the interactive session entry points: login (connect/create), logout,
 * and the OAuth2 account-choice flow.
 */
export const useSessionControls = (
    establishSession: (session: AuthSession, isInitialAttach?: boolean) => void,
    showMessage: (message: string, duration?: number) => void,
    narrativeRef: RefObject<NarrativeRef | null>,
    onEncryptionStateReset: () => void,
    loginMode: "connect" | "create",
    setLoginMode: (mode: "connect" | "create") => void,
) => {
    const { authState, connect, disconnect } = useAuthContext();
    const { disconnect: disconnectWS } = useWebSocketContext();

    const { clearOAuth2UserInfo, handleOAuth2AccountChoice, oauth2UserInfo } = useOAuth2Session(
        establishSession,
        showMessage,
    );

    // Handle login and WebSocket connection
    const handleConnect = useCallback(async (
        mode: "connect" | "create",
        username: string,
        password: string,
        encryptPassword?: string,
    ) => {
        setLoginMode(mode);
        await connect(mode, username, password, encryptPassword);
    }, [connect, setLoginMode]);

    // Comprehensive logout handler
    const handleLogout = useCallback(() => {
        if (narrativeRef.current) {
            narrativeRef.current.clearAll();
        }
        disconnectWS("LOGOUT");
        onEncryptionStateReset();
        // Notify server of explicit logout (triggers user_disconnected if last connection)
        if (authState.player?.clientToken && authState.player?.clientId) {
            fetch("/auth/logout", {
                method: "POST",
                headers: {
                    "X-Moor-Auth-Token": authState.player.authToken,
                    "X-Moor-Client-Token": authState.player.clientToken,
                    "X-Moor-Client-Id": authState.player.clientId,
                },
            }).catch((e) => console.error("Failed to send logout notification:", e));
        }
        // Just disconnect from auth - identity-change effects handle the rest of cleanup
        disconnect();
    }, [authState.player, disconnect, disconnectWS, narrativeRef, onEncryptionStateReset]);

    return {
        oauth2UserInfo,
        clearOAuth2UserInfo,
        handleOAuth2AccountChoice,
        handleConnect,
        handleLogout,
    };
};
