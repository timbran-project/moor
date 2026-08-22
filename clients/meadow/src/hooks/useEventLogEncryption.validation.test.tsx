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

// Deterministic stand-ins for the real Argon2/age primitives: equal (password,
// identifier) pairs produce equal identities/public keys, distinct ones do not.
vi.mock("../lib/keyDerivation", () => ({
    deriveKeyBytes: async (password: string, identifier: string) => {
        const bytes = new Uint8Array(32);
        const input = `${password}:${identifier}`;
        for (let i = 0; i < input.length; i++) {
            bytes[i % 32] = (bytes[i % 32] + input.charCodeAt(i) * (i + 1)) % 256;
        }
        return bytes;
    },
}));

vi.mock("../lib/age-decrypt", () => ({
    identityFromDerivedBytes: (bytes: Uint8Array) => {
        const hex = Array.from(bytes.slice(0, 8))
            .map(b => b.toString(16).padStart(2, "0"))
            .join("");
        return `AGE-SECRET-KEY-${hex}`;
    },
    publicKeyFromIdentity: async (identity: string) => `age1pub-${identity.slice(-16)}`,
}));

const IDENTITY_STORAGE_KEY = "moor_event_log_identity_oid:7";

function publicKeyFor(password: string): string {
    const bytes = new Uint8Array(32);
    const input = `${password}:oid:7`;
    for (let i = 0; i < input.length; i++) {
        bytes[i % 32] = (bytes[i % 32] + input.charCodeAt(i) * (i + 1)) % 256;
    }
    const hex = Array.from(bytes.slice(0, 8))
        .map(b => b.toString(16).padStart(2, "0"))
        .join("");
    return `age1pub-${hex}`;
}

function installFetch(registered: string | null, putCalls: Array<unknown>) {
    return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === "string" ? input : input.toString();
        if (url !== "/v1/event-log/pubkey") {
            throw new Error(`Unexpected fetch: ${url}`);
        }
        if (init?.method === "PUT") {
            putCalls.push(JSON.parse(String(init.body)));
            return new Response(JSON.stringify({ public_key: "set" }), { status: 200 });
        }
        return new Response(JSON.stringify({ public_key: registered }), { status: 200 });
    });
}

describe("useEventLogEncryption key validation", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
        localStorage.clear();
    });

    it("stores the identity on unlock with the correct password and never calls PUT", async () => {
        const putCalls: Array<unknown> = [];
        vi.stubGlobal("fetch", installFetch(publicKeyFor("correct"), putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.unlockEncryption("correct");
        });

        expect(outcome!.success).toBe(true);
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toMatch(/^AGE-SECRET-KEY-/);
        expect(putCalls).toEqual([]);
    });

    it("rejects unlock with the wrong password without storing anything", async () => {
        const putCalls: Array<unknown> = [];
        vi.stubGlobal("fetch", installFetch(publicKeyFor("correct"), putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.unlockEncryption("wrong");
        });

        expect(outcome!.success).toBe(false);
        expect(outcome!.error).toBe("Incorrect encryption password");
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toBeNull();
        expect(putCalls).toEqual([]);
    });

    it("refuses unlock when no key is registered", async () => {
        const putCalls: Array<unknown> = [];
        vi.stubGlobal("fetch", installFetch(null, putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.unlockEncryption("correct");
        });

        expect(outcome!.success).toBe(false);
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toBeNull();
        expect(putCalls).toEqual([]);
    });

    it("setup restores the local identity without overwriting when the password matches", async () => {
        const putCalls: Array<unknown> = [];
        vi.stubGlobal("fetch", installFetch(publicKeyFor("correct"), putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.setupEncryption("correct");
        });

        expect(outcome!.success).toBe(true);
        expect(result.current.encryptionState.ageIdentity).toMatch(/^AGE-SECRET-KEY-/);
        expect(result.current.encryptionState.hasEncryption).toBe(true);
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toMatch(/^AGE-SECRET-KEY-/);
        expect(putCalls).toEqual([]);
    });

    it("setup refuses to overwrite a registered key on a wrong password", async () => {
        const putCalls: Array<unknown> = [];
        vi.stubGlobal("fetch", installFetch(publicKeyFor("correct"), putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.setupEncryption("typo");
        });

        expect(outcome!.success).toBe(false);
        expect(outcome!.error).toBe("Incorrect encryption password");
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toBeNull();
        expect(putCalls).toEqual([]);
    });

    it("setup registers a key when none exists yet", async () => {
        const putCalls: Array<{ public_key: string }> = [];
        vi.stubGlobal("fetch", installFetch(null, putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.setupEncryption("fresh");
        });

        expect(outcome!.success).toBe(true);
        expect(putCalls).toEqual([{ public_key: publicKeyFor("fresh") }]);
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toMatch(/^AGE-SECRET-KEY-/);
    });

    it("explicit allowRekey overwrites a registered key", async () => {
        const putCalls: Array<{ public_key: string }> = [];
        vi.stubGlobal("fetch", installFetch(publicKeyFor("old"), putCalls));
        const { result } = renderHook(() => useEventLogEncryption("auth-token", "oid:7"));

        let outcome: { success: boolean; error?: string };
        await act(async () => {
            outcome = await result.current.setupEncryption("new", { allowRekey: true });
        });

        expect(outcome!.success).toBe(true);
        expect(putCalls).toEqual([{ public_key: publicKeyFor("new") }]);
        expect(localStorage.getItem(IDENTITY_STORAGE_KEY)).toMatch(/^AGE-SECRET-KEY-/);
    });
});
