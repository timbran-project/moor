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
import { useEventLogEncryption } from "./useEventLogEncryption";

describe("useEventLogEncryption status checks", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
        localStorage.clear();
    });

    it.each([401, 500])("finishes with a degraded state after a %i response", async status => {
        vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status })));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        await act(async () => {
            await result.current.checkEncryptionStatus();
        });

        expect(result.current.encryptionState).toMatchObject({
            playerOid: "oid:7",
            hasEncryption: false,
            isChecking: false,
            hasCheckedOnce: true,
            statusError: `Encryption status request failed with status ${status}`,
        });
    });
});
