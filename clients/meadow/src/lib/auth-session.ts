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

const AUTH_TOKEN_KEY = "auth_token";
const PLAYER_OID_KEY = "player_oid";
const PLAYER_FLAGS_KEY = "player_flags";
const HISTORY_AUTH_TOKEN_KEY = "history_auth_token";
const HISTORY_PLAYER_OID_KEY = "history_player_oid";
const CLIENT_TOKEN_KEY = "client_token";
const CLIENT_ID_KEY = "client_id";
const CLIENT_SESSION_ACTIVE_KEY = "client_session_active";

const OBSOLETE_AUTH_KEYS = [
    "oauth2_auth_token",
    "oauth2_player_oid",
    "oauth2_player_flags",
] as const;

export interface ReconnectCredentials {
    clientId: string;
    clientToken: string;
}

export interface AuthSession {
    playerOid: string;
    authToken: string;
    historyPlayerOid: string;
    historyAuthToken: string;
    playerFlags: number;
    reconnectCredentials: ReconnectCredentials | null;
}

export function readReconnectCredentials(): ReconnectCredentials | null {
    const clientId = sessionStorage.getItem(CLIENT_ID_KEY);
    const clientToken = sessionStorage.getItem(CLIENT_TOKEN_KEY);
    if (!clientId || !clientToken) {
        if (clientId || clientToken) {
            persistReconnectCredentials(null);
        }
        return null;
    }
    return { clientId, clientToken };
}

export function persistReconnectCredentials(credentials: ReconnectCredentials | null): void {
    if (!credentials) {
        sessionStorage.removeItem(CLIENT_ID_KEY);
        sessionStorage.removeItem(CLIENT_TOKEN_KEY);
        return;
    }

    sessionStorage.setItem(CLIENT_ID_KEY, credentials.clientId);
    sessionStorage.setItem(CLIENT_TOKEN_KEY, credentials.clientToken);
}

export function readAuthSession(): AuthSession | null {
    const authToken = localStorage.getItem(AUTH_TOKEN_KEY);
    const playerOid = localStorage.getItem(PLAYER_OID_KEY);
    if (!authToken || !playerOid) {
        return null;
    }

    const storedFlags = localStorage.getItem(PLAYER_FLAGS_KEY);
    const parsedFlags = storedFlags === null ? 0 : Number.parseInt(storedFlags, 10);
    return {
        playerOid,
        authToken,
        historyPlayerOid: localStorage.getItem(HISTORY_PLAYER_OID_KEY) ?? playerOid,
        historyAuthToken: localStorage.getItem(HISTORY_AUTH_TOKEN_KEY) ?? authToken,
        playerFlags: Number.isFinite(parsedFlags) ? parsedFlags : 0,
        reconnectCredentials: readReconnectCredentials(),
    };
}

export function persistAuthSession(session: AuthSession): void {
    localStorage.setItem(AUTH_TOKEN_KEY, session.authToken);
    localStorage.setItem(PLAYER_OID_KEY, session.playerOid);
    localStorage.setItem(HISTORY_PLAYER_OID_KEY, session.historyPlayerOid);
    localStorage.setItem(HISTORY_AUTH_TOKEN_KEY, session.historyAuthToken);
    localStorage.setItem(PLAYER_FLAGS_KEY, session.playerFlags.toString());
    persistReconnectCredentials(session.reconnectCredentials);
    for (const key of OBSOLETE_AUTH_KEYS) {
        localStorage.removeItem(key);
    }
}

export function setClientSessionActive(active: boolean): void {
    localStorage.setItem(CLIENT_SESSION_ACTIVE_KEY, active ? "true" : "false");
}

export function isClientSessionActive(): boolean {
    return localStorage.getItem(CLIENT_SESSION_ACTIVE_KEY) === "true";
}

export function clearAuthSession(): void {
    localStorage.removeItem(AUTH_TOKEN_KEY);
    localStorage.removeItem(PLAYER_OID_KEY);
    localStorage.removeItem(PLAYER_FLAGS_KEY);
    localStorage.removeItem(HISTORY_PLAYER_OID_KEY);
    localStorage.removeItem(HISTORY_AUTH_TOKEN_KEY);
    for (const key of OBSOLETE_AUTH_KEYS) {
        localStorage.removeItem(key);
    }
    persistReconnectCredentials(null);
    setClientSessionActive(false);
}
