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

import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useOAuth2Session } from "./useOAuth2Session";

function installSessionStorageMock() {
    let store: Record<string, string> = {};
    Object.defineProperty(window, "sessionStorage", {
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

describe("useOAuth2Session", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("establishes an OAuth2 account session through the shared auth operation", async () => {
        installSessionStorageMock();
        window.history.replaceState({}, "", "/");
        vi.stubGlobal(
            "fetch",
            vi.fn(async () =>
                new Response(
                    JSON.stringify({
                        success: true,
                        auth_token: "auth-token",
                        player: "oid:42",
                        player_flags: 2,
                        client_token: "client-token",
                        client_id: "11111111-1111-1111-1111-111111111111",
                    }),
                    {
                        status: 200,
                        headers: { "Content-Type": "application/json" },
                    },
                )
            ),
        );
        const establishSession = vi.fn();
        const showMessage = vi.fn();
        const { result } = renderHook(() => useOAuth2Session(establishSession, showMessage));

        await act(async () => {
            await result.current.handleOAuth2AccountChoice({
                mode: "oauth2_create",
                oauth2_code: "handoff-code",
                player_name: "new-player",
                encrypt_password: "encryption-password",
            });
        });

        expect(establishSession).toHaveBeenCalledWith({
            authToken: "auth-token",
            playerOid: "oid:42",
            playerFlags: 2,
            reconnectCredentials: {
                clientToken: "client-token",
                clientId: "11111111-1111-1111-1111-111111111111",
            },
        });
        expect(sessionStorage.getItem("pending_encrypt_password")).toBe("encryption-password");
    });
});
