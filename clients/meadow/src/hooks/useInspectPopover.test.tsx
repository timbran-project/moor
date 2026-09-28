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
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { useInspectPopover } from "./useInspectPopover";

vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));

const deferredInspection = () => {
    let resolve!: (value: { result: { title: string; description: string }; output: [] }) => void;
    const promise = new Promise<Parameters<typeof resolve>[0]>(done => {
        resolve = done;
    });
    return { promise, resolve: (title: string) => resolve({ result: { title, description: "" }, output: [] }) };
};

const args = () => ({
    authToken: "token",
    showMessage: vi.fn(),
    sendMessage: vi.fn(() => true),
    addPresentation: vi.fn(),
});

describe("inspection request lifecycle", () => {
    beforeEach(() => vi.clearAllMocks());

    it("keeps the latest selected object when requests finish out of order", async () => {
        const first = deferredInspection();
        const second = deferredInspection();
        vi.mocked(invokeVerbFlatBuffer)
            .mockReturnValueOnce(first.promise as never)
            .mockReturnValueOnce(second.promise as never);
        const { result } = renderHook(() => useInspectPopover(args()));
        let firstRequest!: Promise<void>;
        let secondRequest!: Promise<void>;
        act(() => {
            firstRequest = result.current.inspectObject("oid:1");
            secondRequest = result.current.inspectObject("oid:2");
        });
        await act(async () => {
            second.resolve("Second");
            await secondRequest;
        });
        await act(async () => {
            first.resolve("First");
            await firstRequest;
        });
        expect(result.current.inspectPopover?.data.title).toBe("Second");
    });

    it.each(["close", "release", "identity"])("does not reopen after %s", async operation => {
        const pending = deferredInspection();
        vi.mocked(invokeVerbFlatBuffer).mockReturnValueOnce(pending.promise as never);
        const options = args();
        const { result, rerender } = renderHook(
            ({ authToken }) => useInspectPopover({ ...options, authToken }),
            { initialProps: { authToken: "token" } },
        );
        let request!: Promise<void>;
        act(() => {
            request = result.current.inspectObject("oid:1", undefined, operation === "release");
        });
        act(() => {
            if (operation === "close") result.current.closeInspectPopover();
            if (operation === "release") result.current.handleLinkHoldEnd();
            if (operation === "identity") rerender({ authToken: "other-token" });
        });
        await act(async () => {
            pending.resolve("Late response");
            await request;
        });
        expect(result.current.inspectPopover).toBeNull();
    });

    it("refreshes available actions after a transfer", async () => {
        const take = { label: "Take", target: "oid:42", verb: "get" };
        const drop = { label: "Drop", target: "oid:42", verb: "drop" };
        vi.mocked(invokeVerbFlatBuffer)
            .mockResolvedValueOnce({ result: { title: "Key", description: "", actions: [take] }, output: [] } as never)
            .mockResolvedValueOnce({ result: null, output: [] } as never)
            .mockResolvedValueOnce({ result: { title: "Key", description: "", actions: [drop] }, output: [] } as never);
        const options = args();
        const { result } = renderHook(() => useInspectPopover(options));
        await act(async () => {
            await result.current.inspectObject("oid%3A42");
        });
        await act(async () => {
            await result.current.executeInspectAction(take);
        });
        expect(result.current.inspectPopover?.data.actions).toEqual([drop]);
        expect(invokeVerbFlatBuffer).toHaveBeenLastCalledWith("token", "oid:42", "inspection");
    });

    it("reports failed command delivery so the action can be retried", async () => {
        const options = args();
        options.sendMessage.mockReturnValue(false);
        const { result } = renderHook(() => useInspectPopover(options));
        await expect(result.current.executeInspectAction({ label: "Take", command: "get #42" }))
            .rejects.toThrow("Not connected");
    });
});
