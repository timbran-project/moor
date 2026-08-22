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

import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAuth } from "./useAuth";

function installLocalStorageMock() {
    let store: Record<string, string> = {};
    Object.defineProperty(window, "localStorage", {
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

describe("useAuth player switching", () => {
    afterEach(() => {
        localStorage.clear();
        sessionStorage.clear();
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("replaces the stored identity and refreshes player flags", async () => {
        installLocalStorageMock();
        localStorage.setItem("auth_token", "old-token");
        localStorage.setItem("player_oid", "oid:1");
        localStorage.setItem("player_flags", "7");

        const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
            const token = new Headers(init?.headers).get("X-Moor-Auth-Token");
            if (token === "new-token") {
                return new Response(null, {
                    status: 200,
                    headers: {
                        "X-Moor-Player": "oid:42",
                        "X-Moor-Player-Flags": "2",
                    },
                });
            }
            return new Response(null, { status: 200 });
        });
        vi.stubGlobal("fetch", fetchMock);

        const onSystemMessage = vi.fn();
        const { result } = renderHook(() => useAuth(onSystemMessage));
        await waitFor(() => expect(result.current.authState.player?.oid).toBe("oid:1"));

        await act(async () => {
            await result.current.setPlayerIdentity("oid:42", "new-token");
        });

        expect(fetchMock).toHaveBeenLastCalledWith("/auth/validate", {
            method: "GET",
            headers: { "X-Moor-Auth-Token": "new-token" },
        });
        expect(result.current.authState.player).toMatchObject({
            oid: "oid:42",
            authToken: "new-token",
            flags: 2,
        });
        expect(localStorage.getItem("auth_token")).toBe("new-token");
        expect(localStorage.getItem("player_oid")).toBe("oid:42");
        expect(localStorage.getItem("player_flags")).toBe("2");
    });
});
