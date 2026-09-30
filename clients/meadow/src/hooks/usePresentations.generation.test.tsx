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
import { getCurrentPresentationsFlatBuffer } from "../lib/rpc-fb";
import type { PresentationData } from "../types/presentation";
import { usePresentations } from "./usePresentations";

const sdkMocks = vi.hoisted(() => ({
    parsePresentationBytes: vi.fn(),
    parsePresentationSnapshot: vi.fn(),
    toPresentationData: vi.fn(),
}));

vi.mock("@moor/web-sdk", () => sdkMocks);

vi.mock("../lib/rpc-fb", () => ({
    getCurrentPresentationsFlatBuffer: vi.fn(),
}));

vi.mock("./useMediaQuery", () => ({
    useMediaQuery: vi.fn(() => false),
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

describe("usePresentations request generations", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        sessionStorage.clear();
    });

    it("does not restore presentations after the request becomes stale", async () => {
        const request = deferred<{
            presentationsLength: () => number;
            presentations: (index: number) => unknown;
        }>();
        vi.mocked(getCurrentPresentationsFlatBuffer).mockReturnValue(request.promise as never);

        const { result } = renderHook(() => usePresentations());
        let current = true;
        let fetchRequest!: Promise<boolean>;

        act(() => {
            fetchRequest = result.current.fetchCurrentPresentations(
                "old-token",
                "old-key",
                () => current,
            );
        });

        current = false;
        request.resolve({
            presentationsLength: () => 1,
            presentations: () => ({}),
        });

        await act(async () => {
            expect(await fetchRequest).toBe(false);
        });

        expect(result.current.presentations).toEqual([]);
        expect(sdkMocks.parsePresentationSnapshot).not.toHaveBeenCalled();
    });
    it("keeps dismissed events closed across reload while accepting a fresh open for the same panel", async () => {
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
        try {
            const panel = {
                id: "editor",
                target: "property-value-editor",
                content: "",
                content_type: "text/plain",
                attributes: [],
            } satisfies PresentationData;
            const first = renderHook(() => usePresentations());
            act(() => {
                first.result.current.addPresentation({ ...panel, eventId: "event-1" });
                first.result.current.addPresentation({ ...panel, eventId: "event-2" });
            });
            await act(async () => {
                await first.result.current.dismissPresentation("editor", "auth-token");
            });
            expect(first.result.current.presentations).toEqual([]);
            first.unmount();

            const reloaded = renderHook(() => usePresentations());
            act(() => {
                reloaded.result.current.addPresentation({ ...panel, eventId: "event-1" });
                reloaded.result.current.addPresentation({ ...panel, eventId: "event-2" });
            });
            expect(reloaded.result.current.presentations).toEqual([]);
            act(() => {
                reloaded.result.current.addPresentation({ ...panel, eventId: "fresh-event" });
            });
            expect(reloaded.result.current.presentations.map(p => p.id)).toEqual(["editor"]);
        } finally {
            vi.unstubAllGlobals();
        }
    });
});
