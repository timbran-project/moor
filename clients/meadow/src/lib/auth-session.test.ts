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

import { beforeEach, describe, expect, it } from "vitest";
import { clearAuthSession, persistAuthSession, readAuthSession, readReconnectCredentials } from "./auth-session";

function installStorageMock(name: "localStorage" | "sessionStorage") {
    let store: Record<string, string> = {};
    Object.defineProperty(window, name, {
        configurable: true,
        value: {
            getItem: (key: string) => store[key] ?? null,
            setItem: (key: string, value: string) => {
                store[key] = value;
            },
            removeItem: (key: string) => {
                delete store[key];
            },
            clear: () => {
                store = {};
            },
        },
    });
}

describe("auth session persistence", () => {
    beforeEach(() => {
        installStorageMock("localStorage");
        installStorageMock("sessionStorage");
    });

    it("round-trips identity and reconnect credentials through canonical keys", () => {
        localStorage.setItem("oauth2_auth_token", "obsolete-token");
        persistAuthSession({
            playerOid: "oid:42",
            authToken: "auth-token",
            historyPlayerOid: "oid:1",
            historyAuthToken: "history-token",
            playerFlags: 2,
            reconnectCredentials: {
                clientId: "11111111-1111-1111-1111-111111111111",
                clientToken: "client-token",
            },
        });

        expect(readAuthSession()).toEqual({
            playerOid: "oid:42",
            authToken: "auth-token",
            historyPlayerOid: "oid:1",
            historyAuthToken: "history-token",
            playerFlags: 2,
            reconnectCredentials: {
                clientId: "11111111-1111-1111-1111-111111111111",
                clientToken: "client-token",
            },
        });
        expect(localStorage.getItem("oauth2_auth_token")).toBeNull();
    });

    it("keeps a restored tab's identity paired with its connection when another tab switches", () => {
        localStorage.setItem("auth_token", "alice-token");
        localStorage.setItem("player_oid", "oid:42");
        localStorage.setItem("history_auth_token", "alice-history-token");
        localStorage.setItem("history_player_oid", "oid:1");
        localStorage.setItem("player_flags", "2");
        sessionStorage.setItem("client_id", "alice-connection");
        sessionStorage.setItem("client_token", "alice-client-token");
        const restored = readAuthSession();

        // Another tab switches players, then refreshes its flags.
        localStorage.setItem("auth_token", "bob-token");
        localStorage.setItem("player_oid", "oid:43");
        localStorage.setItem("history_auth_token", "bob-token");
        localStorage.setItem("history_player_oid", "oid:43");
        localStorage.setItem("player_flags", "0");

        expect(readAuthSession()).toEqual(restored);
        expect(readAuthSession()?.playerOid).toBe("oid:42");

        // Logging out this tab must not erase the other player's remembered login.
        clearAuthSession();
        expect(localStorage.getItem("auth_token")).toBe("bob-token");
        expect(readAuthSession()).toBeNull();

        // A newly opened tab can still use the remembered login.
        installStorageMock("sessionStorage");
        expect(readAuthSession()).toMatchObject({
            playerOid: "oid:43",
            historyPlayerOid: "oid:43",
            reconnectCredentials: null,
        });
    });

    it("clears stale reconnect credentials as a pair", () => {
        sessionStorage.setItem("client_id", "11111111-1111-1111-1111-111111111111");

        expect(readReconnectCredentials()).toBeNull();

        expect(sessionStorage.getItem("client_id")).toBeNull();
        expect(sessionStorage.getItem("client_token")).toBeNull();
    });

    it("clears identity and reconnect state together", () => {
        persistAuthSession({
            playerOid: "oid:42",
            authToken: "auth-token",
            historyPlayerOid: "oid:42",
            historyAuthToken: "auth-token",
            playerFlags: 2,
            reconnectCredentials: {
                clientId: "11111111-1111-1111-1111-111111111111",
                clientToken: "client-token",
            },
        });

        clearAuthSession();

        expect(readAuthSession()).toBeNull();
        expect(sessionStorage.getItem("client_id")).toBeNull();
        expect(sessionStorage.getItem("client_token")).toBeNull();
        expect(localStorage.getItem("client_session_active")).toBe("false");
    });
});
