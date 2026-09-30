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
import { fetchHistoryFlatBuffer, type HistoryPage } from "../lib/rpc-fb";
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

function page(cursor: string | null, hasMoreBefore = false, eventCount = cursor ? 1 : 0): HistoryPage {
    return { events: [], earliestEventId: cursor, hasMoreBefore, eventCount };
}

describe("useHistory request generations", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("does not commit pagination state from a stale request", async () => {
        const request = deferred<HistoryPage>();
        vi.mocked(fetchHistoryFlatBuffer)
            .mockResolvedValueOnce(page("current-cursor"))
            .mockReturnValueOnce(request.promise)
            .mockResolvedValueOnce(page(null));

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
        request.resolve(page("old-event"));

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

describe("useHistory pagination", () => {
    beforeEach(() => {
        vi.resetAllMocks();
    });

    async function initialHistory(initialPage = page("initial")) {
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(initialPage);
        const hook = renderHook(() => useHistory("history-token", "age-key"));
        await act(async () => {
            await hook.result.current.fetchInitialHistory();
        });
        return hook;
    }

    it("keeps a short initial time window pageable, including pages with no decrypted messages", async () => {
        const { result } = await initialHistory();
        expect(result.current.hasMoreHistory).toBe(true);
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("older", true, 50));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(result.current.hasMoreHistory).toBe(true);
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page(null));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(vi.mocked(fetchHistoryFlatBuffer).mock.calls[2][4]).toBe("older");
    });

    it.each([
        ["empty", page(null)],
        ["short", page("oldest")],
        ["full terminal", page("oldest", false, 50)],
    ])("stops loading after an %s terminal page", async (_name, terminalPage) => {
        const { result } = await initialHistory();
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(terminalPage);
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(result.current.hasMoreHistory).toBe(false);
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(fetchHistoryFlatBuffer).toHaveBeenCalledTimes(2);
    });

    it.each([page("initial", true, 50), page(null, true, 50)])(
        "rejects nonempty pages with repeated or missing cursors",
        async invalidPage => {
            const { result } = await initialHistory();
            vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(invalidPage);
            await act(async () => {
                await expect(result.current.fetchMoreHistory()).rejects.toThrow(/cursor/);
            });
            expect(result.current.hasMoreHistory).toBe(false);
            await act(async () => {
                await result.current.fetchMoreHistory();
            });
            expect(fetchHistoryFlatBuffer).toHaveBeenCalledTimes(2);
        },
    );

    it("rejects a cursor cycle across several pages", async () => {
        const { result } = await initialHistory();
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("older", true, 50));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("initial", true, 50));
        await act(async () => {
            await expect(result.current.fetchMoreHistory()).rejects.toThrow(/repeated/);
        });
        expect(result.current.hasMoreHistory).toBe(false);
    });

    it("preserves exhaustion across resyncs and clears it for a new identity", async () => {
        const { result } = await initialHistory();
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("oldest"));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("newer", true));
        await act(async () => {
            await result.current.fetchInitialHistory();
        });
        expect(result.current.hasMoreHistory).toBe(false);
        act(() => {
            result.current.resetHistoryRequestState(true);
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("initial"));
        await act(async () => {
            await result.current.fetchInitialHistory();
        });
        expect(result.current.hasMoreHistory).toBe(true);
    });

    it("does not rewind the oldest cursor during a resync", async () => {
        const { result } = await initialHistory();
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("older", true, 50));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("newer", true));
        await act(async () => {
            await result.current.fetchInitialHistory();
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page(null));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(vi.mocked(fetchHistoryFlatBuffer).mock.calls[3][4]).toBe("older");
    });

    it("coalesces scroll requests before React renders the loading state", async () => {
        const { result } = await initialHistory();
        const pending = deferred<HistoryPage>();
        vi.mocked(fetchHistoryFlatBuffer).mockReturnValueOnce(pending.promise);
        await act(async () => {
            const first = result.current.fetchMoreHistory();
            expect(await result.current.fetchMoreHistory()).toBeNull();
            pending.resolve(page(null));
            await first;
        });
        expect(fetchHistoryFlatBuffer).toHaveBeenCalledTimes(2);
    });

    it("initializes the cursor when a resync finds events after an empty initial window", async () => {
        const { result } = await initialHistory(page(null));
        expect(result.current.hasMoreHistory).toBe(false);
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("first"));
        await act(async () => {
            await result.current.fetchInitialHistory();
        });
        expect(result.current.hasMoreHistory).toBe(true);
    });

    it("invalidates an in-flight request on reset without requiring a caller guard", async () => {
        const { result } = await initialHistory();
        const pending = deferred<HistoryPage>();
        vi.mocked(fetchHistoryFlatBuffer).mockReturnValueOnce(pending.promise);
        let oldRequest!: ReturnType<typeof result.current.fetchMoreHistory>;
        act(() => {
            oldRequest = result.current.fetchMoreHistory();
        });
        act(() => {
            result.current.resetHistoryRequestState(true);
        });
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page("new-identity"));
        await act(async () => {
            await result.current.fetchInitialHistory();
        });
        await act(async () => {
            pending.resolve(page(null));
            expect(await oldRequest).toBeNull();
        });
        expect(result.current.hasMoreHistory).toBe(true);
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page(null));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(vi.mocked(fetchHistoryFlatBuffer).mock.calls[3][4]).toBe("new-identity");
    });

    it("allows retry after a network failure", async () => {
        const { result } = await initialHistory();
        vi.mocked(fetchHistoryFlatBuffer).mockRejectedValueOnce(new Error("offline"));
        await act(async () => {
            await expect(result.current.fetchMoreHistory()).rejects.toThrow("offline");
        });
        expect(result.current.hasMoreHistory).toBe(true);
        expect(result.current.isLoadingHistory).toBe(false);
        vi.mocked(fetchHistoryFlatBuffer).mockResolvedValueOnce(page(null));
        await act(async () => {
            await result.current.fetchMoreHistory();
        });
        expect(fetchHistoryFlatBuffer).toHaveBeenCalledTimes(3);
    });
});
