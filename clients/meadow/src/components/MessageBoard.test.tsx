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

import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MessageBoard, SystemMessageProvider, useSystemMessage } from "./MessageBoard";

function MessageHarness() {
    const { systemMessage, showMessage } = useSystemMessage();
    return (
        <>
            <button onClick={() => showMessage("First", 1)}>First</button>
            <button onClick={() => showMessage("Second", 2)}>Second</button>
            <MessageBoard {...systemMessage} />
        </>
    );
}

describe("SystemMessageProvider", () => {
    afterEach(() => {
        vi.useRealTimers();
    });

    it("keeps a newer message visible when an older timer would expire", () => {
        vi.useFakeTimers();
        render(
            <SystemMessageProvider>
                <MessageHarness />
            </SystemMessageProvider>,
        );

        fireEvent.click(screen.getByRole("button", { name: "First" }));
        act(() => vi.advanceTimersByTime(500));
        fireEvent.click(screen.getByRole("button", { name: "Second" }));
        act(() => vi.advanceTimersByTime(500));

        const board = screen.getByRole("status");
        expect(board.textContent).toBe("Second");
        expect(board.classList.contains("hidden")).toBe(false);

        act(() => vi.advanceTimersByTime(1500));
        expect(board.classList.contains("hidden")).toBe(true);
    });
});
