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
import { useState } from "react";
import { expect, it, vi } from "vitest";
import { lazySurface } from "./lazySurface";

function Editor({ visible, onClose }: { visible: boolean; onClose: () => void }) {
    const [text, setText] = useState("initial");
    if (!visible) return null;
    return (
        <>
            <input aria-label="Editor content" value={text} onChange={e => setText(e.target.value)} />
            <button onClick={onClose}>Done</button>
        </>
    );
}

it("defers loading until visible and preserves local edits while covered", async () => {
    const load = vi.fn(async () => ({ default: Editor }));
    const LazyEditor = lazySurface("test editor", load);
    const close = vi.fn();
    const { rerender } = render(<LazyEditor visible={false} onClose={close} />);
    expect(load).not.toHaveBeenCalled();
    await act(async () => rerender(<LazyEditor visible={true} onClose={close} />));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "unsaved changes" } });
    rerender(<LazyEditor visible={false} onClose={close} />);
    expect(screen.queryByRole("textbox")).toBeNull();
    rerender(<LazyEditor visible={true} onClose={close} />);
    expect((screen.getByRole("textbox") as HTMLInputElement).value).toBe("unsaved changes");
    expect(load).toHaveBeenCalledOnce();
});

it("keeps the transcript visible and permits closing a pending surface", async () => {
    let ready!: (value: { default: typeof Editor }) => void;
    const load = vi.fn(() =>
        new Promise<{ default: typeof Editor }>(resolve => {
            ready = resolve;
        })
    );
    const LazyEditor = lazySurface("test editor", load);
    const close = vi.fn();
    render(
        <>
            <p>Live transcript</p>
            <LazyEditor visible onClose={close} />
        </>,
    );
    expect(screen.getByText("Live transcript")).not.toBeNull();
    expect(screen.getByRole("status").textContent).toContain("Loading test editor");
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(close).toHaveBeenCalledOnce();
    await act(async () => ready({ default: Editor }));
    expect(screen.getByRole("textbox")).not.toBeNull();
    expect(screen.queryByRole("status")).toBeNull();
});

it("contains a failed import and retries without unmounting the transcript", async () => {
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});
    const ignoreExpectedError = (event: ErrorEvent) => event.preventDefault();
    window.addEventListener("error", ignoreExpectedError);
    try {
        const load = vi.fn().mockRejectedValueOnce(new Error("offline")).mockResolvedValue({ default: Editor });
        const LazyEditor = lazySurface("test editor", load);
        const close = vi.fn();
        await act(async () => {
            render(
                <>
                    <p>Live transcript</p>
                    <LazyEditor visible onClose={close} />
                </>,
            );
        });
        expect(screen.getByRole("status").textContent).toContain("Could not open test editor");
        expect(screen.getByText("Live transcript")).not.toBeNull();
        await act(async () => fireEvent.click(screen.getByRole("button", { name: "Retry" })));
        expect(screen.getByRole("textbox")).not.toBeNull();
        expect(load).toHaveBeenCalledTimes(2);
    } finally {
        window.removeEventListener("error", ignoreExpectedError);
        errorLog.mockRestore();
    }
});
