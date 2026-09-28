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
const TAB_IDENTITY_KEY = "tab_identity_initialized";
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

function persistIdentity(storage: Storage, session: AuthSession): void {
    storage.setItem(AUTH_TOKEN_KEY, session.authToken);
    storage.setItem(PLAYER_OID_KEY, session.playerOid);
    storage.setItem(HISTORY_PLAYER_OID_KEY, session.historyPlayerOid);
    storage.setItem(HISTORY_AUTH_TOKEN_KEY, session.historyAuthToken);
    storage.setItem(PLAYER_FLAGS_KEY, session.playerFlags.toString());
}

export function readAuthSession(): AuthSession | null {
    // Pin the remembered login to this tab before another tab can switch it.
    const storage = sessionStorage.getItem(TAB_IDENTITY_KEY) ? sessionStorage : localStorage;
    const authToken = storage.getItem(AUTH_TOKEN_KEY);
    const playerOid = storage.getItem(PLAYER_OID_KEY);
    if (!authToken || !playerOid) {
        return null;
    }

    const storedFlags = storage.getItem(PLAYER_FLAGS_KEY);
    const parsedFlags = storedFlags === null ? 0 : Number.parseInt(storedFlags, 10);
    const session = {
        playerOid,
        authToken,
        historyPlayerOid: storage.getItem(HISTORY_PLAYER_OID_KEY) ?? playerOid,
        historyAuthToken: storage.getItem(HISTORY_AUTH_TOKEN_KEY) ?? authToken,
        playerFlags: Number.isFinite(parsedFlags) ? parsedFlags : 0,
        reconnectCredentials: readReconnectCredentials(),
    };
    if (storage === localStorage) {
        persistIdentity(sessionStorage, session);
        sessionStorage.setItem(TAB_IDENTITY_KEY, "true");
    }
    return session;
}

export function persistAuthSession(session: AuthSession): void {
    persistIdentity(sessionStorage, session);
    sessionStorage.setItem(TAB_IDENTITY_KEY, "true");
    persistIdentity(localStorage, session);
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
    const clearRememberedIdentity = !sessionStorage.getItem(TAB_IDENTITY_KEY)
        || sessionStorage.getItem(AUTH_TOKEN_KEY) === localStorage.getItem(AUTH_TOKEN_KEY);
    const keys = [AUTH_TOKEN_KEY, PLAYER_OID_KEY, PLAYER_FLAGS_KEY, HISTORY_PLAYER_OID_KEY, HISTORY_AUTH_TOKEN_KEY];
    for (const key of keys) {
        sessionStorage.removeItem(key);
        if (clearRememberedIdentity) localStorage.removeItem(key);
    }
    // A logged-out tab must not adopt another tab's remembered login on refresh.
    sessionStorage.setItem(TAB_IDENTITY_KEY, "true");
    for (const key of OBSOLETE_AUTH_KEYS) {
        localStorage.removeItem(key);
    }
    persistReconnectCredentials(null);
    setClientSessionActive(false);
}
