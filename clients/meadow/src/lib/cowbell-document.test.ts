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

// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { renderCowbellDocument, terminalStyles } from "./cowbell-document";

const textNode = (text: string) => ({ kind: "text", text });
const paragraph = (...children: unknown[]) => ({ kind: "paragraph", children });
const reference = (ref: string, label: string, objectKind?: string) => ({
    kind: "reference",
    descriptor: { kind: "object", ref, ...(objectKind ? { objectKind } : {}) },
    children: [textNode(label)],
});
const doc = (...blocks: unknown[]) => ({ version: 1, blocks });

function dom(...blocks: unknown[]): HTMLElement {
    const rendered = renderCowbellDocument(doc(...blocks));
    expect(rendered).not.toBeNull();
    const container = document.createElement("div");
    container.innerHTML = rendered!.html;
    return container;
}

describe("renderCowbellDocument", () => {
    beforeEach(() => {
        vi.spyOn(console, "warn").mockImplementation(() => {});
    });
    afterEach(() => {
        vi.restoreAllMocks();
    });

    it("renders block and inline structure", () => {
        const container = dom(
            { kind: "heading", level: 4, children: [textNode("Things")] },
            paragraph(
                { kind: "strong", children: [textNode("brass")] },
                { kind: "emphasis", children: [textNode("bell")] },
                { kind: "strike", children: [textNode("old")] },
                { kind: "hard_break" },
                { kind: "inline_code", text: "ring" },
            ),
            { kind: "block_quote", children: [paragraph(textNode("quoted"))] },
            { kind: "thematic_break" },
            { kind: "definition_list", items: [{ term: [textNode("key")], definition: [paragraph(textNode("v"))] }] },
        );
        expect(container.querySelector("h4")?.textContent).toBe("Things");
        expect(container.querySelector("p strong")?.textContent).toBe("brass");
        expect(container.querySelector("p em")?.textContent).toBe("bell");
        expect(container.querySelector("p del")?.textContent).toBe("old");
        expect(container.querySelector("p br")).toBeTruthy();
        expect(container.querySelector("p code")?.textContent).toBe("ring");
        expect(container.querySelector("blockquote p")?.textContent).toBe("quoted");
        expect(container.querySelector("hr")).toBeTruthy();
        expect(container.querySelector("dt")?.textContent).toBe("key");
        expect(container.querySelector("dd p")?.textContent).toBe("v");
    });

    it("treats document text as text, never as markup", () => {
        const container = dom(paragraph(textNode("<img src=x onerror=alert(1)> & <b>bold</b>")));
        expect(container.querySelector("img, b")).toBeNull();
        expect(container.textContent).toBe("<img src=x onerror=alert(1)> & <b>bold</b>");
    });

    it("allocates annotations by reading order and marks reference lists", () => {
        const rendered = renderCowbellDocument(doc(
            paragraph(reference("oid:1", "Pat")),
            {
                kind: "list",
                style: "bullet",
                items: [{ blocks: [paragraph(reference("oid:2", "Sam", "person"))] }],
            },
        ));
        expect(Object.keys(rendered!.annotations)).toEqual(["a1", "a2"]);
        expect(rendered!.annotations.a2).toMatchObject({ kind: "object", ref: "oid:2" });
        const container = document.createElement("div");
        container.innerHTML = rendered!.html;
        expect(container.querySelector("[data-moor-annotation=a1]")?.textContent).toBe("Pat");
        const columns = container.querySelector("ul.reference-columns");
        expect(columns?.querySelector("[data-moor-annotation=a2].semantic-person svg")).toBeTruthy();
    });

    it("leaves mixed lists out of reference columns", () => {
        const container = dom({
            kind: "list",
            style: "bullet",
            items: [{ blocks: [paragraph(reference("oid:1", "Pat"), textNode(" is here"))] }],
        });
        expect(container.querySelector("ul")?.className).toBe("");
    });

    it("keeps list numbering, task state, and table structure", () => {
        const container = dom(
            {
                kind: "list",
                style: "numbered",
                start: 3,
                items: [{ blocks: [paragraph(textNode("c"))], checked: true }, { blocks: [] }],
            },
            {
                kind: "table",
                caption: [textNode("Scores")],
                columns: [{ align: "start" }, { align: "end" }],
                header: [[textNode("Who")], [textNode("Points")]],
                rows: [{ cells: [{ blocks: [paragraph(textNode("Pat"))] }, { blocks: [paragraph(textNode("9"))] }] }],
            },
        );
        expect(container.querySelector("ol")?.getAttribute("start")).toBe("3");
        expect(container.querySelector<HTMLInputElement>("li input")?.disabled).toBe(true);
        expect(container.querySelector("li input")?.hasAttribute("checked")).toBe(true);
        expect(container.querySelector("table.narrative-table caption")?.textContent).toBe("Scores");
        expect(container.querySelector("th[scope=col][align=right]")?.textContent).toBe("Points");
        expect(container.querySelector("td[align=right]")?.textContent).toBe("9");
    });

    it("renders code with a language class and a line number gutter", () => {
        const container = dom({ kind: "code_block", text: "a\nb\n", language: "none", first_line: 7 });
        const [gutter, listing] = Array.from(container.querySelectorAll("td"));
        expect(gutter.getAttribute("aria-hidden")).toBe("true");
        expect(gutter.textContent).toBe("7\n8");
        expect(listing.querySelector("pre code.language-none")?.textContent).toBe("a\nb\n");
    });

    it("converts links and images under the existing URL policy", () => {
        const container = dom(paragraph(
            { kind: "link", url: "https://example.com/a", children: [textNode("site")] },
            { kind: "link", url: "mailto:pat@example.com", children: [textNode("mail")] },
            { kind: "image", src: "https://example.com/i.png", alt: "pic", title: "t" },
        ));
        expect(container.querySelector("a")).toBeNull();
        expect(container.querySelector("[data-url]")?.getAttribute("data-url")).toBe("https://example.com/a");
        expect(container.querySelectorAll("[data-url]")).toHaveLength(1);
        expect(container.textContent).toContain("mail");
        expect(container.querySelector("img")?.getAttribute("alt")).toBe("pic");
    });

    it("keeps ANSI styles and shows other escapes, as the core renderer does", () => {
        expect(terminalStyles("\x1b[31mred")).toBe("\x1b[31mred\x1b[0m");
        expect(terminalStyles("\x1b[31mred\x1b[0m")).toBe("\x1b[31mred\x1b[0m");
        expect(terminalStyles("\x1b[2Jgone")).toBe("\\x1b[2Jgone");
        expect(terminalStyles("\x1b]0;title")).toBe("\\x1b]0;title");
        const container = dom(paragraph(textNode("\x1b[31mred")));
        expect(container.querySelector("span[style*=color]")?.textContent).toBe("red");
    });

    it.each([
        ["a non-record", "<p>body</p>"],
        ["an unsupported version", { version: 2, blocks: [] }],
        ["missing blocks", { version: 1 }],
        ["an unknown root field", { version: 1, blocks: [], extra: 1 }],
        ["an unknown block", doc({ kind: "marquee", children: [] })],
        ["an unknown inline", doc(paragraph({ kind: "marquee" }))],
        ["an inline where a block belongs", doc(textNode("x"))],
        ["a block where an inline belongs", doc(paragraph(paragraph()))],
        ["an unknown node field", doc({ kind: "thematic_break", onclick: "x" })],
        ["a bad heading level", doc({ kind: "heading", level: 7, children: [] })],
        ["a newline in text", doc(paragraph(textNode("a\nb")))],
        ["a script URL", doc(paragraph({ kind: "link", url: "javascript:alert(1)", children: [] }))],
        ["whitespace in a URL", doc(paragraph({ kind: "link", url: "https://a b", children: [] }))],
        ["a mailto image", doc(paragraph({ kind: "image", src: "mailto:a@b", alt: "" }))],
        ["a bad code language", doc({ kind: "code_block", text: "", language: "a b" })],
        [
            "nested interaction",
            doc(paragraph({ kind: "link", url: "https://a", children: [reference("oid:1", "x")] })),
        ],
        ["an unsupported descriptor", doc(paragraph({ kind: "reference", descriptor: { kind: "?" }, children: [] }))],
        ["a bullet list start", doc({ kind: "list", style: "bullet", start: 1, items: [] })],
        ["a table without columns", doc({ kind: "table", caption: [], columns: [], rows: [] })],
        [
            "a short table row",
            doc({ kind: "table", caption: [], columns: [{ align: "start" }], rows: [{ cells: [] }] }),
        ],
    ])("rejects %s", (_label, value) => {
        expect(renderCowbellDocument(value)).toBeNull();
        expect(console.warn).toHaveBeenCalled();
    });

    it("rejects documents beyond the schema's limits", () => {
        let deep: unknown = { kind: "thematic_break" };
        for (let i = 0; i < 33; i++) deep = { kind: "block_quote", children: [deep] };
        expect(renderCowbellDocument(doc(deep))).toBeNull();
        const many = Array.from({ length: 8193 }, () => ({ kind: "thematic_break" }));
        expect(renderCowbellDocument(doc(...many))).toBeNull();
        const references = Array.from({ length: 513 }, (_, i) => reference(`oid:${i}`, "x"));
        expect(renderCowbellDocument(doc(paragraph(...references)))).toBeNull();
        expect(renderCowbellDocument(doc(paragraph(textNode("x".repeat(262145)))))).toBeNull();
    });
});
