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
import { useNarrativeLinks } from "./useNarrativeLinks";

vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));
vi.mock("../context/ExternalNavigationContext", () => ({
    useExternalNavigation: () => ({ openExternalLink: vi.fn() }),
}));

const options = () => ({
    authToken: "token",
    sendMessage: vi.fn(() => true),
    showMessage: vi.fn(),
    inspect: { inspectObject: vi.fn() },
});
const url = "moo://exit/oid:10/oid:20/passage-identity";

describe("bound exit routing", () => {
    beforeEach(() => vi.clearAllMocks());

    it("invokes the originating room and refreshes through the current connection", async () => {
        vi.mocked(invokeVerbFlatBuffer).mockResolvedValue({ result: { moved: true, message: "" }, output: [] });
        const args = options();
        const { result } = renderHook(() => useNarrativeLinks(args));
        await act(async () => {
            await result.current.handleLinkClick(url);
        });
        expect(invokeVerbFlatBuffer).toHaveBeenCalledWith("token", "oid:10", "follow_exit", expect.any(Uint8Array));
        expect(args.sendMessage).toHaveBeenCalledExactlyOnceWith("look");
    });

    it("shows the server's explanation without sending a direction command", async () => {
        vi.mocked(invokeVerbFlatBuffer).mockResolvedValue({
            result: { moved: false, message: "That exit is in another room." },
            output: [],
        });
        const args = options();
        const { result } = renderHook(() => useNarrativeLinks(args));
        await act(async () => {
            await result.current.handleLinkClick(url);
        });
        expect(args.showMessage).toHaveBeenCalledWith("That exit is in another room.", 4);
        expect(args.sendMessage).not.toHaveBeenCalled();
    });

    it("shares duplicate pending clicks and permits retry after completion", async () => {
        let resolve!: (value: Awaited<ReturnType<typeof invokeVerbFlatBuffer>>) => void;
        const pending = new Promise<Awaited<ReturnType<typeof invokeVerbFlatBuffer>>>(done => {
            resolve = done;
        });
        vi.mocked(invokeVerbFlatBuffer).mockReturnValueOnce(pending);
        const args = options();
        const { result } = renderHook(() => useNarrativeLinks(args));
        let first!: Promise<void>;
        let second!: Promise<void>;
        act(() => {
            first = result.current.handleLinkClick(url);
            second = result.current.handleLinkClick(url);
        });
        expect(invokeVerbFlatBuffer).toHaveBeenCalledTimes(1);
        await act(async () => {
            resolve({ result: { moved: false, message: "Closed" }, output: [] });
            await Promise.all([first, second]);
        });
        vi.mocked(invokeVerbFlatBuffer).mockResolvedValue({ result: { moved: true }, output: [] });
        await act(async () => {
            await result.current.handleLinkClick(url);
        });
        expect(invokeVerbFlatBuffer).toHaveBeenCalledTimes(2);
    });

    it("ignores responses from a previous player identity", async () => {
        let resolve!: (value: Awaited<ReturnType<typeof invokeVerbFlatBuffer>>) => void;
        vi.mocked(invokeVerbFlatBuffer).mockReturnValue(
            new Promise(done => {
                resolve = done;
            }),
        );
        const args = options();
        const { result, rerender } = renderHook(
            ({ authToken }) => useNarrativeLinks({ ...args, authToken }),
            { initialProps: { authToken: "first-token" } },
        );
        let request!: Promise<void>;
        act(() => {
            request = result.current.handleLinkClick(url);
        });
        rerender({ authToken: "second-token" });
        await act(async () => {
            resolve({ result: { moved: true }, output: [] });
            await request;
        });
        expect(args.sendMessage).not.toHaveBeenCalled();
        expect(args.showMessage).not.toHaveBeenCalled();
    });

    it.each([
        "moo://exit/oid:10/oid:20",
        "moo://exit/oid:10/no-room/id",
        "moo://exit/oid:10/oid:20/%zz",
    ])("rejects malformed exit URL %s", async invalid => {
        const args = options();
        const { result } = renderHook(() => useNarrativeLinks(args));
        await act(async () => {
            await result.current.handleLinkClick(invalid);
        });
        expect(invokeVerbFlatBuffer).not.toHaveBeenCalled();
        expect(args.showMessage).toHaveBeenCalled();
    });
});
