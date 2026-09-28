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

import { describe, expect, it } from "vitest";
import { roomSnapshotToPresentation } from "./room-snapshot-presentation";

describe("room snapshot exits", () => {
    it("uses the server's bound exits rather than constructing direction commands", () => {
        const presentation = roomSnapshotToPresentation({
            room: 10,
            title: "Hall",
            exits: ["east"],
            exit_links: [{ label: "east", url: "moo://exit/oid:10/oid:20/identity" }],
        });
        expect(presentation?.content).toContain("href=\"moo://exit/oid:10/oid:20/identity\"");
        expect(presentation?.content).not.toContain("moo://cmd/");
    });

    it("does not turn unbound or invalid exits into executable commands", () => {
        const presentation = roomSnapshotToPresentation({
            exits: ["east"],
            exit_links: [{ label: "east", url: "moo://cmd/go%20east" }],
        });
        expect(presentation?.content).not.toContain("href=");
    });
});
