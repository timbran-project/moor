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
import { expect, it, vi } from "vitest";
import { inspectionCommand, InspectPopover } from "./InspectPopover";

const take = { id: "transfer", label: "Take", command: "get #42" };
const put = {
    id: "put",
    label: "Put inside",
    command: "put {input} in #66",
    input: { label: "Which item?", placeholder: "Item name" },
};
const data = { title: "Cupboard", description: "A wooden cupboard.", state: ["Open"], actions: [take, put] };
const position = { x: 20, y: 20 };

it("shows the exact command and submits one command for a double-click", () => {
    const onCommand = vi.fn(() => true);
    render(<InspectPopover data={data} position={position} onClose={vi.fn()} onCommand={onCommand} />);
    expect(screen.getByText("get #42")).toBeDefined();
    fireEvent.click(screen.getByRole("button", { name: "Take" }), { detail: 1 });
    fireEvent.click(screen.getByRole("button", { name: "Take" }), { detail: 2 });
    expect(onCommand).toHaveBeenCalledExactlyOnceWith("get #42");
    expect(screen.getByRole("status").textContent).toBe("Sent: get #42");
});

it("collects input inline, preserves it across state refreshes, and submits through the parser", () => {
    const onCommand = vi.fn(() => true);
    const props = { position, onClose: vi.fn(), onCommand };
    const { rerender } = render(<InspectPopover {...props} data={data} />);
    fireEvent.click(screen.getByRole("button", { name: "Put inside" }));
    const input = screen.getByLabelText("Which item?");
    expect(document.activeElement).toBe(input);
    fireEvent.change(input, { target: { value: "brass key" } });
    rerender(<InspectPopover {...props} data={{ ...data, state: ["Carrying", "Open"] }} />);
    expect((screen.getByLabelText("Which item?") as HTMLInputElement).value).toBe("brass key");
    fireEvent.submit(input.closest("form")!);
    expect(onCommand).toHaveBeenCalledExactlyOnceWith("put brass key in #66");
});

it("keeps the card and input available when disconnected", () => {
    render(<InspectPopover data={data} position={position} onClose={vi.fn()} onCommand={() => false} />);
    fireEvent.click(screen.getByRole("button", { name: "Take" }));
    expect(screen.getByRole("alert").textContent).toContain("not sent");
    expect(screen.getByRole("dialog")).toBeDefined();
});

it("rejects multiple command lines", () => {
    expect(() => inspectionCommand(put, "key\ndrop all")).toThrow("single-line");
    expect(() => inspectionCommand({ ...take, command: "get #42\ndrop #42" })).toThrow("single-line");
});

it("stays open and returns keyboard focus on Escape", () => {
    vi.useFakeTimers();
    const origin = document.createElement("button");
    document.body.append(origin);
    origin.focus();
    const onClose = vi.fn();
    const { unmount } = render(
        <InspectPopover
            data={data}
            position={position}
            returnFocusTo={origin}
            onClose={onClose}
            onCommand={() => true}
        />,
    );
    expect(document.activeElement).toBe(screen.getByRole("dialog"));
    act(() => vi.advanceTimersByTime(30000));
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(onClose).toHaveBeenCalledOnce();
    expect(document.activeElement).toBe(origin);
    unmount();
    origin.remove();
    vi.useRealTimers();
});

it("keeps held previews noninteractive", () => {
    render(<InspectPopover data={data} position={position} isPreview onClose={vi.fn()} onCommand={() => true} />);
    expect(screen.getByRole("tooltip")).toBeDefined();
    expect(screen.queryByRole("button")).toBeNull();
});

it("briefly flashes the copied reference beside its titled icon", async () => {
    vi.useFakeTimers();
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } });
    const onClose = vi.fn();
    render(
        <InspectPopover data={data} reference="oid:42" position={position} onClose={onClose} onCommand={() => true} />,
    );
    const copy = screen.getByRole("button", { name: "Copy reference" });
    expect(copy.closest(".inspect-popover-title-row")?.textContent).toBe("Cupboard");
    expect(copy.querySelector("svg")).not.toBeNull();
    expect(copy.textContent).toBe("");
    expect(copy.title).toBe("Copy reference #42");
    await act(async () => fireEvent.click(copy));
    expect(writeText).toHaveBeenCalledExactlyOnceWith("#42");
    expect(screen.getByText("Copied #42").getAttribute("role")).toBe("status");
    expect(onClose).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(1800));
    expect(screen.queryByText("Copied #42")).toBeNull();
    vi.useRealTimers();
});
