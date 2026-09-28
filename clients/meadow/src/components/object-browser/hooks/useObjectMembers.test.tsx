// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
import { act, renderHook } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { getPropertyFlatBuffer, getVerbCodeFlatBuffer } from "../../../lib/rpc-fb";
import { ObjectData, PropertyData, VerbData } from "../types";
import { useObjectMembers } from "./useObjectMembers";
vi.mock(
    "../../../lib/rpc-fb",
    () => ({
        getPropertyFlatBuffer: vi.fn(),
        getVerbCodeFlatBuffer: vi.fn(),
        getPropertiesFlatBuffer: vi.fn(),
        getVerbsFlatBuffer: vi.fn(),
    }),
);
afterEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
});
const object = { obj: "#65", name: "Key" } as ObjectData;
const verb = { location: "#25", names: ["get"], indexInLocation: 1 } as VerbData;
it("ignores a late source reply after a new member selection", async () => {
    let resolve!: (value: Awaited<ReturnType<typeof getVerbCodeFlatBuffer>>) => void;
    vi.mocked(getVerbCodeFlatBuffer).mockReturnValueOnce(
        new Promise(done => {
            resolve = done;
        }),
    );
    const { result } = renderHook(() => useObjectMembers({ authToken: "session", selectedObject: object }));
    let pending!: Promise<void>;
    act(() => {
        pending = result.current.handleVerbSelect(verb);
    });
    vi.mocked(getVerbCodeFlatBuffer).mockResolvedValueOnce(
        { codeLength: () => 1, code: () => "return 2;" } as Awaited<ReturnType<typeof getVerbCodeFlatBuffer>>,
    );
    await act(async () => result.current.handleVerbSelect({ ...verb, names: ["drop"] }));
    await act(async () => {
        resolve({ codeLength: () => 1, code: () => "return 1;" } as Awaited<ReturnType<typeof getVerbCodeFlatBuffer>>);
        await pending;
    });
    expect(result.current.selectedVerb?.names).toEqual(["drop"]);
    expect(result.current.verbCode).toBe("return 2;");
});
it("does not open an editor for denied source or property reads, and reads inherited values through the receiver", async () => {
    const quiet = vi.spyOn(console, "error").mockImplementation(() => {});
    const { result } = renderHook(() => useObjectMembers({ authToken: "session", selectedObject: object }));
    vi.mocked(getVerbCodeFlatBuffer).mockRejectedValueOnce(new Error("Permission denied"));
    await act(async () => result.current.handleVerbSelect(verb));
    expect(result.current.editorVisible).toBe(false);
    expect(result.current.memberError).toContain("permission");
    vi.mocked(getPropertyFlatBuffer).mockRejectedValueOnce(new Error("Permission denied"));
    await act(async () => result.current.handlePropertySelect({ name: "secret", location: "#25" } as PropertyData));
    expect(getPropertyFlatBuffer).toHaveBeenCalledWith("session", "oid:65", "secret");
    expect(result.current.editorVisible).toBe(false);
    expect(result.current.memberError).toContain("permission");
    quiet.mockRestore();
});
