// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
import { describe, expect, it } from "vitest";
import {
    decodeDraft,
    draftEcho,
    editDraft,
    plainDraft,
    prefixDraft,
    replaceArgument,
    serializeDraft,
    sliceDraft,
} from "./command-draft";
import { renderDjot } from "./djot-renderer";

describe("bound command drafts", () => {
    it("retains distinct targets behind identical labels through serialization and recall", () => {
        const first = replaceArgument(plainDraft("give  to "), 5, 5, "Token", "oid:47");
        const draft = replaceArgument(first, first.text.length, first.text.length, "Token", "oid:45");
        expect(draft.text).toBe("give Token to Token");
        const recalled = decodeDraft(JSON.parse(JSON.stringify(draft)))!;
        expect(serializeDraft(recalled).command).toBe("give #47 to #45");
        const edited = editDraft(recalled, "give Coin to Token");
        expect(serializeDraft(edited).command).toBe("give Coin to #45");
        expect(edited.bindings).toHaveLength(1);
    });
    it("maps UTF-16 cursor ranges without deriving references from unbound prose", () => {
        const draft = replaceArgument(plainDraft("take "), 5, 5, "🧭 Compass", "oid:47");
        const wire = serializeDraft(draft);
        expect(wire.toWire(draft.text.length)).toBe(wire.command.length);
        expect(wire.toDisplay(wire.command.length)).toBe(draft.text.length);
        expect(wire.toWire(7)).toBe(5);
        expect(decodeDraft(plainDraft("take #47"))?.bindings).toEqual([]);
    });
    it("shifts untouched bindings and releases overlapping paste/deletion", () => {
        const draft = replaceArgument(plainDraft("take "), 5, 5, "Compass", "oid:47");
        const shifted = editDraft(draft, "get Compass");
        expect(serializeDraft(shifted).command).toBe("get #47");
        expect(editDraft(draft, "take ComPastepass").bindings).toEqual([]);
        expect(editDraft(draft, "take ").bindings).toEqual([]);
        expect(serializeDraft(prefixDraft(sliceDraft(draft, 5, draft.text.length), "get ")).command).toBe("get #47");
    });
    it("renders escaped echo labels as explicit event-local annotations", () => {
        const draft = replaceArgument(plainDraft("take "), 5, 5, "*[Key]{annotation=evil}", "oid:47");
        const echo = draftEcho(draft);
        const root = document.createElement("div");
        root.innerHTML = renderDjot(echo.content, { annotations: echo.annotations });
        expect(root.textContent?.trim()).toBe(draft.text);
        expect(root.querySelectorAll("[data-moor-annotation]")).toHaveLength(1);
        expect(root.querySelector("[data-moor-annotation]")?.getAttribute("data-moor-annotation")).toBe("b0");
    });
    it("rejects malformed or overlapping history bindings", () => {
        expect(decodeDraft({ text: "take x", bindings: [{ start: 5, end: 9, reference: "oid:47" }] })).toBeNull();
        expect(decodeDraft({ text: "take x", bindings: [{ start: 5, end: 6, reference: "bogus" }] })).toBeNull();
    });
});
