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

import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { fetchHistoryFlatBuffer } from "../lib/rpc-fb";
import { useHistory } from "./useHistory";

vi.mock("@moor/web-sdk", async (importOriginal) => ({
    ...await importOriginal<typeof import("@moor/web-sdk")>(),
    parseHistoricalNarrativeEvent: vi.fn(() => null),
}));

vi.mock("../lib/rpc-fb", () => ({
    fetchHistoryFlatBuffer: vi.fn(),
}));

interface Deferred<T> {
    promise: Promise<T>;
    resolve: (value: T) => void;
}

const deferred = <T,>(): Deferred<T> => {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>((resolvePromise) => {
        resolve = resolvePromise;
    });
    return { promise, resolve };
};

describe("useHistory request generations", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("does not commit pagination state from a stale request", async () => {
        const request = deferred<Array<{ event_id: string; timestamp: number; narrative_event: unknown }>>();
        vi.mocked(fetchHistoryFlatBuffer)
            .mockResolvedValueOnce([{ event_id: "current-cursor", timestamp: 2, narrative_event: {} }])
            .mockReturnValueOnce(request.promise)
            .mockResolvedValueOnce([]);

        const { result } = renderHook(() => useHistory("history-token", "age-key"));
        await act(async () => {
            await result.current.fetchInitialHistory(() => true);
        });
        let current = true;
        let staleRequest!: ReturnType<typeof result.current.fetchMoreHistory>;

        act(() => {
            staleRequest = result.current.fetchMoreHistory(() => current);
        });
        expect(result.current.isLoadingHistory).toBe(true);
        expect(vi.mocked(fetchHistoryFlatBuffer).mock.calls[1][4]).toBe("current-cursor");

        current = false;
        request.resolve([{ event_id: "old-event", timestamp: 1, narrative_event: {} }]);

        await act(async () => {
            expect(await staleRequest).toBeNull();
        });

        act(() => result.current.resetHistoryRequestState());
        expect(result.current.isLoadingHistory).toBe(false);

        let nextPage;
        await act(async () => {
            nextPage = await result.current.fetchMoreHistory(() => true);
        });

        expect(nextPage).toEqual({ messages: [], presentationActions: [] });
        expect(fetchHistoryFlatBuffer).toHaveBeenCalledTimes(3);
        expect(vi.mocked(fetchHistoryFlatBuffer).mock.calls[2][4]).toBe("current-cursor");
    });
});
