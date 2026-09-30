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
        const sessionWrites = vi.spyOn(sessionStorage, "setItem");
        const localWrites = vi.spyOn(localStorage, "setItem");
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
            historyAuthToken: "auth-token",
            historyPlayerOid: "oid:42",
            playerFlags: 2,
            reconnectCredentials: {
                clientToken: "client-token",
                clientId: "11111111-1111-1111-1111-111111111111",
            },
        }, { encryptionPassword: "encryption-password" });
        expect(sessionWrites).not.toHaveBeenCalled();
        expect(localWrites).not.toHaveBeenCalled();
        const request = vi.mocked(fetch).mock.calls[0][1];
        expect(String(request?.body)).not.toContain("encryption-password");
    });
});

describe("OAuth account request cancellation", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("aborts a cancelled request and ignores a response that still arrives", async () => {
        window.history.replaceState({}, "", "/");
        let resolve!: (response: Response) => void;
        const pending = new Promise<Response>(done => {
            resolve = done;
        });
        const fetchMock = vi.fn(() => pending);
        vi.stubGlobal("fetch", fetchMock);
        const establishSession = vi.fn();
        const showMessage = vi.fn();
        const { result } = renderHook(() => useOAuth2Session(establishSession, showMessage));
        let request!: Promise<void>;
        act(() => {
            request = result.current.handleOAuth2AccountChoice({
                mode: "oauth2_create",
                oauth2_code: "code",
                encrypt_password: "private-password",
            });
        });
        const signal = vi.mocked(fetch).mock.calls[0][1]?.signal;
        act(() => result.current.clearOAuth2UserInfo());
        expect(signal?.aborted).toBe(true);
        await act(async () => {
            resolve(new Response(JSON.stringify({ success: true, auth_token: "old-token", player: "oid:7" })));
            await request;
        });
        expect(establishSession).not.toHaveBeenCalled();
        expect(showMessage).not.toHaveBeenCalled();
    });

    it("does not log a rejected request's credential-bearing error payload", async () => {
        const secret = "private-password";
        window.history.replaceState({}, "", "/");
        vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error(secret)));
        const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});
        const establishSession = vi.fn();
        const showMessage = vi.fn();
        const { result } = renderHook(() => useOAuth2Session(establishSession, showMessage));
        await act(async () => {
            await result.current.handleOAuth2AccountChoice({
                mode: "oauth2_create",
                oauth2_code: "code",
                encrypt_password: secret,
            });
        });
        expect(establishSession).not.toHaveBeenCalled();
        expect(errorLog).toHaveBeenCalledWith("OAuth2 account choice failed");
        expect(JSON.stringify(showMessage.mock.calls)).not.toContain(secret);
    });
});
