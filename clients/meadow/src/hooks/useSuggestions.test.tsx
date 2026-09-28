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
import { afterEach, expect, it, vi } from "vitest";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { useSuggestions } from "./useSuggestions";

vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));
afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
});
it("debounces requests and rejects late results from another query or identity", async () => {
    vi.useFakeTimers();
    let finish!: (value: { result: unknown; output: [] }) => void;
    vi.mocked(invokeVerbFlatBuffer).mockReturnValueOnce(
        new Promise(resolve => {
            finish = resolve;
        }),
    );
    const { result, rerender } = renderHook(({ query, token }) =>
        useSuggestions(
            token,
            {
                provider: "oid:66",
                source: "contents",
                template: "get {input} from #66",
            },
            query,
            true,
        ), { initialProps: { query: "b", token: "first" } });
    rerender({ query: "br", token: "first" });
    await act(async () => {
        await vi.advanceTimersByTimeAsync(125);
    });
    expect(invokeVerbFlatBuffer).toHaveBeenCalledTimes(1);
    rerender({ query: "key", token: "second" });
    await act(async () => {
        finish({ result: { items: [{ id: "stale" }], more: false }, output: [] });
    });
    expect(result.current.items).toEqual([]);
    expect(result.current.loading).toBe(true);
    vi.mocked(invokeVerbFlatBuffer).mockResolvedValueOnce({
        result: {
            items: [{ id: "new", label: "Key", value: "#65", detail: "#65" }],
            more: false,
        },
        output: [],
    });
    await act(async () => {
        await vi.advanceTimersByTimeAsync(125);
    });
    expect(result.current.items[0].id).toBe("new");
});
