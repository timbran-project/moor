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
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AuthSession } from "../lib/auth-session";
import { useAuth } from "./useAuth";

const session: AuthSession = {
    playerOid: "oid:7",
    authToken: "auth-seven",
    historyPlayerOid: "oid:7",
    historyAuthToken: "auth-seven",
    playerFlags: 0,
    reconnectCredentials: null,
};
const password = "pending-encryption-secret";

function pendingSession() {
    const showMessage = vi.fn();
    const hook = renderHook(() => useAuth(showMessage));
    act(() => hook.result.current.establishSession(session, { encryptionPassword: password }));
    return hook;
}

describe("pending encryption credentials", () => {
    beforeEach(() => {
        localStorage.clear();
        sessionStorage.clear();
        vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 200 })));
    });
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("keeps the password outside storage and rendered auth state, consuming it once", () => {
        const localWrites = vi.spyOn(localStorage, "setItem");
        const sessionWrites = vi.spyOn(sessionStorage, "setItem");
        const { result } = pendingSession();
        expect(JSON.stringify([...localWrites.mock.calls, ...sessionWrites.mock.calls])).not.toContain(password);
        expect(JSON.stringify(result.current.authState)).not.toContain(password);
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBe(password);
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it("does not let an unrelated session consume the password", () => {
        const { result } = pendingSession();
        expect(result.current.takePendingEncryptionPassword("other-token", "oid:7")).toBeNull();
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:8")).toBeNull();
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBe(password);
    });

    it("clears pending credentials on logout, even before the next render", () => {
        const { result } = pendingSession();
        act(() => {
            result.current.disconnect();
            expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
        });
    });

    it("clears a pending password when another session is established without one", () => {
        const { result } = pendingSession();
        act(() => result.current.establishSession(session));
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it.each([false, true])("clears credentials on player switch (preserve history: %s)", async preserveHistory => {
        const { result } = pendingSession();
        await act(async () => {
            await result.current.rotatePlayerIdentity("oid:8", "auth-eight", false, preserveHistory);
        });
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
        expect(result.current.takePendingEncryptionPassword("auth-eight", "oid:8")).toBeNull();
    });

    it("clears credentials when starting a different login attempt", async () => {
        const { result } = pendingSession();
        await act(async () => {
            await result.current.connect("connect", "", "");
        });
        expect(result.current.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it("clears the ref on unmount", () => {
        const { result, unmount } = pendingSession();
        const take = result.current.takePendingEncryptionPassword;
        unmount();
        expect(take("auth-seven", "oid:7")).toBeNull();
    });
});
