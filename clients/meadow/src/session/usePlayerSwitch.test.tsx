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
//

import { renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { usePlayerSwitch } from "./usePlayerSwitch";

const noop = () => {};

describe("usePlayerSwitch", () => {
    it("does nothing before the first identity is known", () => {
        const handlers = {
            onAuthorityReset: vi.fn(),
            onSessionEnded: vi.fn(),
            onHistoryIdentityChanged: vi.fn(),
        };
        const { rerender } = renderHook(({ oid, historyOid }) => usePlayerSwitch(oid, historyOid, handlers), {
            initialProps: { oid: null as string | null, historyOid: null as string | null },
        });

        rerender({ oid: "player-1", historyOid: "player-1" });

        expect(handlers.onAuthorityReset).not.toHaveBeenCalled();
        expect(handlers.onSessionEnded).not.toHaveBeenCalled();
        expect(handlers.onHistoryIdentityChanged).not.toHaveBeenCalled();
    });

    it("resets authority-scoped UI on a player switch without ending the session", () => {
        const handlers = {
            onAuthorityReset: vi.fn(),
            onSessionEnded: vi.fn(),
            onHistoryIdentityChanged: vi.fn(),
        };
        const { rerender } = renderHook(({ oid, historyOid }) => usePlayerSwitch(oid, historyOid, handlers), {
            initialProps: { oid: "player-1" as string | null, historyOid: "player-1" as string | null },
        });

        rerender({ oid: "player-2", historyOid: "player-2" });

        expect(handlers.onAuthorityReset).toHaveBeenCalledTimes(1);
        expect(handlers.onSessionEnded).not.toHaveBeenCalled();
    });

    it("only resets history when the history owner changes", () => {
        const handlers = {
            onAuthorityReset: vi.fn(),
            onSessionEnded: vi.fn(),
            onHistoryIdentityChanged: vi.fn(),
        };
        const { rerender } = renderHook(({ oid, historyOid }) => usePlayerSwitch(oid, historyOid, handlers), {
            initialProps: { oid: "player-1" as string | null, historyOid: "history-1" as string | null },
        });

        // Same history owner (e.g. character switch within one account)
        rerender({ oid: "player-2", historyOid: "history-1" });
        expect(handlers.onAuthorityReset).toHaveBeenCalledTimes(1);
        expect(handlers.onHistoryIdentityChanged).not.toHaveBeenCalled();

        // New history owner
        rerender({ oid: "player-3", historyOid: "history-3" });
        expect(handlers.onAuthorityReset).toHaveBeenCalledTimes(2);
        expect(handlers.onHistoryIdentityChanged).toHaveBeenCalledTimes(1);
    });

    it("reports session end only when no player remains attached", () => {
        const handlers = {
            onAuthorityReset: vi.fn(noop),
            onSessionEnded: vi.fn(),
            onHistoryIdentityChanged: vi.fn(),
        };
        const { rerender } = renderHook(({ oid, historyOid }) => usePlayerSwitch(oid, historyOid, handlers), {
            initialProps: { oid: "player-1" as string | null, historyOid: "player-1" as string | null },
        });

        rerender({ oid: null, historyOid: null });
        expect(handlers.onSessionEnded).toHaveBeenCalledTimes(1);
        expect(handlers.onHistoryIdentityChanged).toHaveBeenCalledTimes(1);
    });
});
