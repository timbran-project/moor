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
import { describe, expect, it, vi } from "vitest";
import { ContentRenderer } from "./ContentRenderer";

vi.mock("./Toast", () => ({
    useToast: () => ({ showToast: vi.fn() }),
}));

describe("ContentRenderer URI embeds", () => {
    it.each([
        "javascript:alert(document.domain)",
        "data:text/html,<script>alert(document.domain)</script>",
        "file:///etc/passwd",
        "http://[",
    ])("blocks an unsafe URI: %s", uri => {
        const { container } = render(<ContentRenderer content={uri} contentType="text/x-uri" />);

        expect(container.querySelector("iframe")).toBeNull();
        expect(screen.getByText(/embedded content was blocked/i)).toBeDefined();
    });

    it("isolates an HTTPS embed in a script-only sandbox", () => {
        render(<ContentRenderer content="https://example.com/welcome" contentType="text/x-uri" />);

        const iframe = screen.getByTitle("Embedded content");
        expect(iframe.getAttribute("src")).toBe("https://example.com/welcome");
        expect(iframe.getAttribute("sandbox")).toBe("allow-scripts");
    });

    it("resolves a relative embed against the application origin", () => {
        render(<ContentRenderer content="/welcome" contentType="text/x-uri" />);

        expect(screen.getByTitle("Embedded content").getAttribute("src")).toBe(
            `${window.location.origin}/welcome`,
        );
    });
});

describe("ContentRenderer historical links", () => {
    const content = "<a href=\"moo://inspect/oid:42\"><strong>Key</strong></a> "
        + "<a href=\"moo://cmd/go%20north\">North</a> "
        + "<a href=\"moo://help/movement\">Help</a> "
        + "<a href=\"https://example.com\">Website</a>";

    it("keeps references, help, and external links keyboard-accessible after a message expires", () => {
        const onLinkClick = vi.fn();
        const { container, rerender } = render(
            <ContentRenderer content={content} contentType="text/html" onLinkClick={onLinkClick} />,
        );
        rerender(<ContentRenderer content={content} contentType="text/html" isStale onLinkClick={onLinkClick} />);
        const links = [...container.querySelectorAll<HTMLElement>("[data-url]")];
        expect(links.map(link => link.tabIndex)).toEqual([0, -1, 0, 0]);
        expect(links[1].getAttribute("aria-disabled")).toBe("true");

        fireEvent.click(screen.getByText("Key"));
        fireEvent.keyDown(links[0], { key: "Enter" });
        fireEvent.keyDown(links[2], { key: " " });
        fireEvent.keyDown(links[3], { key: "Enter" });
        expect(onLinkClick.mock.calls.map(call => call[0])).toEqual([
            "moo://inspect/oid:42",
            "moo://inspect/oid:42",
            "moo://help/movement",
            "https://example.com",
        ]);
        fireEvent.click(links[1]);
        fireEvent.keyDown(links[1], { key: "Enter" });
        expect(onLinkClick).toHaveBeenCalledTimes(4);
    });

    it("allows touch previews on historical object references", () => {
        vi.useFakeTimers();
        try {
            const onLinkHoldStart = vi.fn();
            const onLinkHoldEnd = vi.fn();
            render(
                <ContentRenderer
                    content={content}
                    contentType="text/html"
                    isStale
                    onLinkHoldStart={onLinkHoldStart}
                    onLinkHoldEnd={onLinkHoldEnd}
                />,
            );
            fireEvent.touchStart(screen.getByText("Key"), { touches: [{ clientX: 20, clientY: 40 }] });
            act(() => vi.advanceTimersByTime(300));
            expect(onLinkHoldStart).toHaveBeenCalledWith("moo://inspect/oid:42", { x: 20, y: 40 });
            fireEvent.touchEnd(screen.getByText("Key"));
            expect(onLinkHoldEnd).toHaveBeenCalledOnce();
        } finally {
            vi.useRealTimers();
        }
    });
});

describe("ContentRenderer bound exits", () => {
    it("keeps old exits usable and disables only the pending action for mouse and keyboard", async () => {
        let resolve!: () => void;
        const pending = new Promise<void>(done => {
            resolve = done;
        });
        const onLinkClick = vi.fn(() => pending);
        const { container } = render(
            <ContentRenderer
                content='<a href="moo://exit/oid:10/oid:20/id">East</a> <a href="moo://inspect/oid:42">Key</a>'
                contentType="text/html"
                isStale
                onLinkClick={onLinkClick}
            />,
        );
        const [exit, inspect] = [...container.querySelectorAll<HTMLElement>("[data-url]")];
        expect(exit.tabIndex).toBe(0);
        fireEvent.click(exit);
        expect(exit.getAttribute("aria-busy")).toBe("true");
        expect(exit.tabIndex).toBe(-1);
        expect(inspect.tabIndex).toBe(0);
        fireEvent.keyDown(exit, { key: "Enter" });
        expect(onLinkClick).toHaveBeenCalledTimes(1);
        await act(async () => {
            resolve();
            await pending;
        });
        expect(exit.getAttribute("aria-busy")).toBeNull();
        expect(exit.tabIndex).toBe(0);
        fireEvent.keyDown(exit, { key: "Enter" });
        await act(async () => {
            await pending;
        });
        expect(onLinkClick).toHaveBeenCalledTimes(2);
    });
});
