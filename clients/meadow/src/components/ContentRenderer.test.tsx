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

import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { AnnotationContext } from "../context/AnnotationContext";
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

describe("ContentRenderer semantic references", () => {
    it("activates an event-local reference with mouse and keyboard after newer output", () => {
        const activate = vi.fn();
        const table = { a1: { kind: "object" as const, ref: "oid:42" } };
        render(
            <AnnotationContext.Provider value={activate}>
                <ContentRenderer
                    content="[Key]{annotation=a1}"
                    contentType="text/djot"
                    isStale
                    eventMetadata={{ annotations: table }}
                />
                <ContentRenderer
                    content="[Other key]{annotation=a1}"
                    contentType="text/djot"
                    eventMetadata={{ annotations: { a1: { kind: "object", ref: "oid:43" } } }}
                />
            </AnnotationContext.Provider>,
        );
        fireEvent.click(screen.getByText("Key"));
        fireEvent.keyDown(screen.getByText("Other key"), { key: "Enter" });
        expect(activate.mock.calls.map(call => call[0].annotation.ref)).toEqual(["oid:42", "oid:43"]);
    });
    it("does not activate on hover, render, or missing metadata", () => {
        const activate = vi.fn();
        render(
            <AnnotationContext.Provider value={activate}>
                <ContentRenderer content="[Key]{annotation=a1}" contentType="text/djot" />
            </AnnotationContext.Provider>,
        );
        fireEvent.mouseOver(screen.getByText("Key"));
        fireEvent.click(screen.getByText("Key"));
        expect(activate).not.toHaveBeenCalled();
    });
    it("leaves unannotated object-like text plain", () => {
        const { container } = render(<ContentRenderer content="#42 #000A54-9B1A1A9B2E" />);
        expect(container.querySelector("[role=button], [data-objid], [data-uuobjid]")).toBeNull();
        expect(container.textContent).toBe("#42 #000A54-9B1A1A9B2E");
    });
    it("preserves external links and ignores historical internal URLs", () => {
        const onLinkClick = vi.fn();
        const { container } = render(
            <ContentRenderer
                content='<a href="moo://exit/oid:10/oid:20/id">East</a> <a href="https://example.com">Website</a>'
                contentType="text/html"
                onLinkClick={onLinkClick}
            />,
        );
        fireEvent.click(screen.getByText("East"));
        expect(onLinkClick).not.toHaveBeenCalled();
        fireEvent.keyDown(screen.getByText("Website"), { key: " " });
        expect(onLinkClick).toHaveBeenCalledWith("https://example.com", expect.any(Object), expect.any(Object));
        expect(container.querySelectorAll("[data-url]")).toHaveLength(1);
    });
});

describe("ContentRenderer documents", () => {
    const annotation = { kind: "object", ref: "oid:2" } as const;
    const cowbellDocument = {
        version: 1,
        blocks: [{
            kind: "paragraph",
            children: [{ kind: "reference", descriptor: annotation, children: [{ kind: "text", text: "From tree" }] }],
        }],
    };
    const body = "<p><span data-moor-annotation=\"a1\">From body</span></p>";

    function renderWith(document: unknown, activate = vi.fn()) {
        render(
            <AnnotationContext.Provider value={activate}>
                <ContentRenderer
                    content={body}
                    contentType="text/html"
                    cowbellDocument={document}
                    eventMetadata={{ annotations: { a1: { kind: "object", ref: "oid:1" } } }}
                />
            </AnnotationContext.Provider>,
        );
        return activate;
    }

    it("renders the document with its own annotations in place of the body", () => {
        const activate = renderWith(cowbellDocument);
        expect(screen.queryByText("From body")).toBeNull();
        fireEvent.click(screen.getByText("From tree"));
        expect(activate).toHaveBeenCalledWith(expect.objectContaining({ annotation, label: "From tree" }));
    });

    it("renders the whole body with its annotations when the document is invalid", () => {
        const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
        const activate = renderWith({ version: 2, blocks: [] });
        expect(warn).toHaveBeenCalled();
        warn.mockRestore();
        fireEvent.click(screen.getByText("From body"));
        expect(activate).toHaveBeenCalledWith(
            expect.objectContaining({ annotation: { kind: "object", ref: "oid:1" }, label: "From body" }),
        );
    });

    it("renders the body when no document is supplied", () => {
        renderWith(undefined);
        expect(screen.getByText("From body")).toBeDefined();
    });
});
