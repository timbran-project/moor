// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { describe, expect, it } from "vitest";
import { roomSnapshotToPresentation } from "./room-snapshot-presentation";

describe("room snapshot annotations", () => {
    it("preserves Cowbell's exact command independently of the displayed direction", () => {
        const annotation = { kind: "command", command: "go e", exit: { source: "oid:10", destination: "oid:20", passage: "identity" } };
        const presentation = roomSnapshotToPresentation({
            room: 10, title: "Hall", exits: ["east"], exit_links: [{ label: "East door", annotation }],
        });
        expect(presentation?.content).toContain('data-moor-annotation="a1">East door');
        expect(presentation?.annotations?.a1).toEqual(annotation);
        expect(presentation?.content).not.toContain("moo://");
    });
    it("does not infer an executable command from a direction alone", () => {
        const presentation = roomSnapshotToPresentation({ exits: ["east"], exit_links: [{ label: "east" }] });
        expect(presentation?.content).not.toContain("data-moor-annotation");
    });
    it("retains distinct identities for identical object labels", () => {
        const presentation = roomSnapshotToPresentation({ things: [{ name: "key", object: { oid: 11 } }, { name: "key", object: { oid: 12 } }] });
        expect(Object.values(presentation?.annotations ?? {})).toEqual([{ kind: "object", ref: "oid:11" }, { kind: "object", ref: "oid:12" }]);
    });
});
