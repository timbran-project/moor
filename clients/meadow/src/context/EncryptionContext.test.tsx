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

import { render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { EncryptionProvider, useEncryptionContext } from "./EncryptionContext";

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

function EncryptionIdentity() {
    const { encryptionState } = useEncryptionContext();
    return <div>{encryptionState.ageIdentity ?? "none"}</div>;
}

describe("EncryptionProvider identity rotation", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("loads encryption state for the active player", async () => {
        installLocalStorageMock();
        localStorage.setItem("moor_event_log_identity_oid:1", "identity-one");
        localStorage.setItem("moor_event_log_identity_oid:2", "identity-two");
        vi.stubGlobal(
            "fetch",
            vi.fn(async () =>
                new Response(JSON.stringify({ public_key: "age-public-key" }), {
                    status: 200,
                    headers: { "Content-Type": "application/json" },
                })
            ),
        );

        const { rerender } = render(
            <EncryptionProvider authToken="token-one" playerOid="oid:1">
                <EncryptionIdentity />
            </EncryptionProvider>,
        );
        expect(screen.getByText("identity-one")).toBeDefined();

        rerender(
            <EncryptionProvider authToken="token-two" playerOid="oid:2">
                <EncryptionIdentity />
            </EncryptionProvider>,
        );

        await waitFor(() => expect(screen.getByText("identity-two")).toBeDefined());
    });
});
