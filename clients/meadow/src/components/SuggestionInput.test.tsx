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

import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { InspectPopover } from "./InspectPopover";

vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));
const choices = {
    items: [
        { id: "#65", label: "a brass key", value: "#65", detail: "#65" },
        { id: "#70", label: "a brass key", value: "#70", detail: "#70" },
    ],
    more: false,
};
const source = { provider: "oid:66", source: "contents" };
const data = {
    title: "Cupboard",
    description: "",
    actions: [{
        id: "take_from",
        label: "Take from",
        command: "get {input} from #66",
        input: { label: "Which item?", placeholder: "Find an item", suggestions: source },
    }],
};
beforeEach(() => {
    vi.useFakeTimers();
    vi.mocked(invokeVerbFlatBuffer).mockReset().mockResolvedValue({ result: choices, output: [] });
});
afterEach(() => vi.useRealTimers());
async function open(onCommand = vi.fn(() => true), onClose = vi.fn()) {
    render(
        <InspectPopover
            data={data}
            position={{ x: 20, y: 20 }}
            authToken="token"
            onCommand={onCommand}
            onClose={onClose}
        />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Take from" }));
    await act(async () => {
        await vi.advanceTimersByTimeAsync(125);
    });
    return { input: screen.getByRole("combobox"), onCommand, onClose };
}
it("shows choices on focus and selects a stable reference without executing", async () => {
    const { input, onCommand } = await open();
    expect(screen.getAllByRole("option")).toHaveLength(2);
    fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "ArrowDown" });
    fireEvent.keyDown(input, { key: "Enter" });
    expect((input as HTMLInputElement).value).toBe("a brass key");
    expect(screen.getByText("get #70 from #66")).toBeDefined();
    expect(onCommand).not.toHaveBeenCalled();
    fireEvent.submit(input.closest("form")!);
    expect(onCommand).toHaveBeenCalledExactlyOnceWith("get #70 from #66");
});
it("clears the selected reference when its displayed text is edited", async () => {
    const { input, onCommand } = await open();
    fireEvent.click(screen.getAllByRole("option")[0]);
    fireEvent.change(input, { target: { value: "other key" } });
    fireEvent.submit(input.closest("form")!);
    expect(onCommand).toHaveBeenCalledExactlyOnceWith("get other key from #66");
});
it("dismisses suggestions before the inspector on Escape", async () => {
    const { input, onClose } = await open();
    fireEvent.keyDown(input, { key: "Escape" });
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.keyDown(input, { key: "Escape" });
    expect(onClose).toHaveBeenCalledOnce();
});
it("keeps manual input usable after a suggestion request fails", async () => {
    vi.mocked(invokeVerbFlatBuffer).mockRejectedValue(new Error("offline"));
    const { input, onCommand } = await open();
    expect(screen.getByText(/Suggestions unavailable/)).toBeDefined();
    fireEvent.change(input, { target: { value: "key" } });
    fireEvent.submit(input.closest("form")!);
    expect(onCommand).toHaveBeenCalledExactlyOnceWith("get key from #66");
});
