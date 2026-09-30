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
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createTranscript, type Transcript } from "../lib/transcript";
import { useTranscriptWindow } from "./useTranscriptWindow";

const messages = (start: number, count: number) =>
    Array.from({ length: count }, (_, i) => ({
        id: String(start + i),
        content: `message ${start + i}`,
        type: "narrative" as const,
        isHistorical: true,
    }));

function Harness({ transcript, loadOlder }: { transcript: Transcript; loadOlder?: () => void }) {
    const window = useTranscriptWindow(transcript, loadOlder);
    return (
        <div
            ref={window.outputRef}
            data-testid="output"
            data-history={window.isViewingHistory}
            onScroll={window.handleScroll}
        >
            <button onClick={window.older} disabled={!window.hasOlder}>Older</button>
            <button onClick={window.newer} disabled={!window.hasNewer}>Newer</button>
            <button onClick={window.jumpToNow}>Now</button>
            {window.visibleGroups.map(group => (
                <div key={group.id} data-transcript-group={group.id}>
                    {group.messages.map(message => (
                        <span key={message.id} data-transcript-message={message.id}>{message.content}</span>
                    ))}
                </div>
            ))}
        </div>
    );
}

let resize: () => void;
let extraHeight = 0;
const rect = (top: number, height: number) => ({
    top,
    bottom: top + height,
    height,
    left: 0,
    right: 800,
    width: 800,
    x: 0,
    y: top,
    toJSON() {},
});

beforeEach(() => {
    extraHeight = 0;
    vi.stubGlobal(
        "ResizeObserver",
        class {
            constructor(callback: () => void) {
                resize = callback;
            }
            observe() {}
            disconnect() {}
        },
    );
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function(this: HTMLElement) {
        const parent = this.closest("[data-testid=\"output\"]") as HTMLElement;
        const group = this.closest<HTMLElement>("[data-transcript-group]");
        if (!group) return rect(0, 200);
        const groups = Array.from(parent.querySelectorAll<HTMLElement>("[data-transcript-group]"));
        const index = groups.indexOf(group);
        const before = groups.slice(0, index).reduce((sum, row) => sum + row.children.length * 20, 0);
        const top = 40 + before + (index > 0 ? extraHeight : 0) - parent.scrollTop;
        if (this.hasAttribute("data-transcript-message")) {
            return rect(top + Array.from(group.children).indexOf(this) * 20, 20);
        }
        return rect(top, group.children.length * 20 + (index === 0 ? extraHeight : 0));
    });
});
afterEach(() => {
    document.getSelection()?.removeAllRanges();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
});

function setup(count = 500, loadOlder?: () => void) {
    const transcript = createTranscript();
    transcript.replace(messages(0, count));
    render(<Harness transcript={transcript} loadOlder={loadOlder} />);
    const output = screen.getByTestId("output");
    Object.defineProperty(output, "clientHeight", { configurable: true, value: 200 });
    Object.defineProperty(output, "scrollHeight", {
        configurable: true,
        get: () => 40 + output.querySelectorAll("[data-transcript-message]").length * 20 + extraHeight,
    });
    let scrollTop = 0;
    Object.defineProperty(output, "scrollTop", {
        configurable: true,
        get: () => scrollTop,
        set: value => {
            scrollTop = Math.max(0, Math.min(value, output.scrollHeight - output.clientHeight));
        },
    });
    act(() => resize());
    return {
        transcript,
        output,
        first: () => output.querySelector<HTMLElement>("[data-transcript-group]")!.dataset.transcriptGroup,
    };
}
function scroll(output: HTMLElement, top: number) {
    output.scrollTop = top;
    fireEvent.scroll(output);
}

describe("transcript moving window", () => {
    it("pages by complete groups with explicit controls and returns to the live tail", async () => {
        const { transcript, output, first } = setup();
        expect(first()).toBe("300");
        act(() => screen.getByText("Older").focus());
        fireEvent.click(screen.getByText("Older"));
        expect(first()).toBe("200");
        expect(output.scrollTop).toBe(0);
        expect(document.activeElement).toBe(screen.getByText("Older"));
        fireEvent.click(screen.getByText("Newer"));
        expect(first()).toBe("300");
        fireEvent.click(screen.getByText("Now"));
        expect(output.scrollTop).toBe(output.scrollHeight - output.clientHeight);
        await act(async () => {
            (document.activeElement as HTMLElement).blur();
            transcript.append(messages(500, 1)[0]);
        });
        expect(first()).toBe("301");
    });

    it("preserves a group's viewport offset when scrolling into older and newer windows", () => {
        const { output, first } = setup();
        scroll(output, 20);
        expect(first()).toBe("200");
        expect(output.querySelector("[data-transcript-group=\"300\"]")!.getBoundingClientRect().top).toBe(20);
        scroll(output, output.scrollHeight - output.clientHeight);
        expect(first()).toBe("300");
        expect(output.querySelector("[data-transcript-group=\"390\"]")!.getBoundingClientRect().top).toBe(0);
    });

    it("anchors appends, history prepends, and image/container resizes while reading", () => {
        const { transcript, output, first } = setup();
        scroll(output, 1020);
        const position = () => output.querySelector("[data-transcript-group=\"350\"]")!.getBoundingClientRect().top;
        const before = position();
        act(() => transcript.append(messages(500, 1)[0]));
        expect(first()).toBe("300");
        expect(position()).toBe(before);
        act(() => transcript.prepend(messages(-100, 100)));
        expect(position()).toBe(before);
        extraHeight = 60;
        act(() => resize());
        expect(position()).toBe(before);
    });

    it.each(["selection", "focus"])("holds the window while %s is active", (interaction) => {
        const { transcript, output, first } = setup();
        if (interaction === "selection") {
            const row = output.querySelector("[data-transcript-group=\"300\"]")!;
            const range = document.createRange();
            range.selectNodeContents(row);
            document.getSelection()!.addRange(range);
            fireEvent(document, new Event("selectionchange"));
        } else act(() => screen.getByText("Older").focus());
        act(() => transcript.append(messages(500, 1)[0]));
        scroll(output, 20);
        expect(first()).toBe("300");
        if (interaction === "selection") expect(document.getSelection()!.toString()).toBe("message 300");
        fireEvent.click(screen.getByText("Older"));
        expect(first()).toBe("200");
    });

    it.each(["selection", "focus"])("resumes the live tail after %s ends without scrolling", async (interaction) => {
        const { transcript, output, first } = setup();
        if (interaction === "selection") {
            const range = document.createRange();
            range.selectNodeContents(output.querySelector("[data-transcript-group=\"499\"]")!);
            document.getSelection()!.addRange(range);
            fireEvent(document, new Event("selectionchange"));
        } else act(() => screen.getByText("Older").focus());
        expect(output.dataset.history).toBe("false");
        // A scroll event at the same live position must not turn focus into history either.
        scroll(output, output.scrollHeight - output.clientHeight);
        scroll(output, output.scrollHeight - output.clientHeight);
        expect(output.dataset.history).toBe("false");
        act(() => transcript.append(messages(500, 1)[0]));
        expect(first()).toBe("300");
        expect(output.dataset.history).toBe("true");
        await act(async () => {
            if (interaction === "selection") {
                document.getSelection()!.removeAllRanges();
                document.dispatchEvent(new Event("selectionchange"));
            } else (document.activeElement as HTMLElement).blur();
        });
        expect(first()).toBe("301");
        expect(output.dataset.history).toBe("false");
        expect(output.scrollTop).toBe(output.scrollHeight - output.clientHeight);
    });

    it("keeps the reading position when focus ends after scrolling into history", async () => {
        const { transcript, output, first } = setup();
        act(() => screen.getByText("Older").focus());
        scroll(output, 1020);
        await act(async () => (document.activeElement as HTMLElement).blur());
        act(() => transcript.append(messages(500, 1)[0]));
        expect(first()).toBe("300");
        expect(output.dataset.history).toBe("true");
        expect(output.scrollTop).toBe(1020);
    });

    it("recognizes scrolling back to the live tail while a control remains focused", () => {
        const { output } = setup();
        act(() => screen.getByText("Older").focus());
        scroll(output, 1020);
        expect(output.dataset.history).toBe("true");
        scroll(output, output.scrollHeight - output.clientHeight);
        expect(output.dataset.history).toBe("false");
    });

    it("uses cached groups before fetching and displays a requested older page", () => {
        const loadOlder = vi.fn();
        const { transcript, first } = setup(300, loadOlder);
        fireEvent.click(screen.getByText("Older"));
        expect(loadOlder).not.toHaveBeenCalled();
        expect(first()).toBe("0");
        fireEvent.click(screen.getByText("Older"));
        expect(loadOlder).toHaveBeenCalledTimes(1);
        act(() => transcript.prepend(messages(-100, 100)));
        expect(first()).toBe("-100");
    });

    it("keeps one large presentation group intact at the window edge", () => {
        const { transcript, output } = setup();
        act(() => {
            for (const message of messages(500, 250)) {
                transcript.append({ ...message, presentationHint: "inset", groupId: "whole" });
            }
        });
        expect(output.querySelectorAll("[data-transcript-group]")).toHaveLength(200);
        expect(output.querySelector("[data-transcript-group=\"500\"]")!.querySelectorAll("span")).toHaveLength(250);
    });

    it("anchors a visible message when an older page extends its group", () => {
        const { transcript, output } = setup();
        const grouped = (start: number, count: number) =>
            messages(start, count).map(message => ({
                ...message,
                presentationHint: "inset",
                groupId: "room",
            }));
        act(() => transcript.replace([...grouped(0, 50), ...messages(50, 100)]));
        scroll(output, 450);
        const visible = () => output.querySelector("[data-transcript-message=\"20\"]")!.getBoundingClientRect().top;
        const before = visible();
        act(() => transcript.prepend(grouped(-5, 5)));
        expect(visible()).toBe(before);
        expect(output.scrollTop).toBe(550);
    });

    it("resumes following after the transcript is cleared", () => {
        const { transcript, output } = setup();
        fireEvent.click(screen.getByText("Older"));
        act(() => transcript.replace([]));
        act(() => transcript.append(messages(1000, 1)[0]));
        expect(output.querySelector("[data-transcript-group=\"1000\"]")).not.toBeNull();
        expect(output.scrollTop).toBe(Math.max(0, output.scrollHeight - output.clientHeight));
    });
});
