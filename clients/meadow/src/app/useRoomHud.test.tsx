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

import { act, render } from "@testing-library/react";
import { useEffect } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Presentation } from "../types/presentation";
import { useRoomHud } from "./useRoomHud";

const dock = vi.hoisted(() => ({ presentations: [] as unknown[] }));
vi.mock("../context/PresentationContext", () => ({
    usePresentationContext: () => ({ getTopDockPresentations: () => dock.presentations }),
}));

function roomDock(room: string): Presentation {
    return {
        id: "room-look",
        target: "top",
        title: "A room",
        content: "",
        contentType: "text/plain",
        attrs: { kind: "room_look", room },
    };
}

type Hud = ReturnType<typeof useRoomHud>;

/** What the narrative tells the HUD about the latest description of the current room. */
interface Report {
    messageId: string | null;
    visible: boolean;
}

/**
 * Stands in for the output window: a child that reports, in an effect, whether the narrative
 * shows a description of the current room. A child's effects run before its parent's, which is
 * the order the real components run in.
 */
function Narrative({ hud, report }: { hud: Hud; report: Report }) {
    const { currentRoomLookKey, handleActiveRoomLookVisibilityChange } = hud;
    useEffect(() => {
        // The output window reports once itself and again when its intersection observer first
        // fires. The first report of a new message only names it.
        handleActiveRoomLookVisibilityChange(currentRoomLookKey, report.visible, report.messageId);
        handleActiveRoomLookVisibilityChange(currentRoomLookKey, report.visible, report.messageId);
    }, [currentRoomLookKey, handleActiveRoomLookVisibilityChange, report.messageId, report.visible]);
    return null;
}

let latest: Hud;

function Surface({ report }: { report: Report }) {
    const hud = useRoomHud();
    latest = hud;
    return <Narrative hud={hud} report={report} />;
}

const showsRoomDock = () => latest.topDockPresentations.some(presentation => presentation.id === "room-look");

describe("useRoomHud", () => {
    beforeEach(() => {
        localStorage.clear();
        dock.presentations = [];
    });

    it("shows the room when the narrative has no description of it", () => {
        // A first login, or a reload without history: the room's state arrives, and the narrative
        // is empty.
        const nothing: Report = { messageId: null, visible: false };
        const view = render(<Surface report={nothing} />);
        expect(showsRoomDock()).toBe(false);

        act(() => {
            dock.presentations = [roomDock("oid:5")];
            view.rerender(<Surface report={nothing} />);
        });

        expect(showsRoomDock()).toBe(true);
    });

    it("stays out of the way while the narrative shows the room, and appears once it scrolls away", () => {
        dock.presentations = [roomDock("oid:5")];
        const view = render(<Surface report={{ messageId: "look-1", visible: true }} />);
        expect(showsRoomDock()).toBe(false);

        act(() => view.rerender(<Surface report={{ messageId: "look-1", visible: false }} />));
        expect(showsRoomDock()).toBe(true);

        // Scrolling back does not hide it again.
        act(() => view.rerender(<Surface report={{ messageId: "look-1", visible: true }} />));
        expect(showsRoomDock()).toBe(true);

        // A fresh description of the same room takes over from the dock.
        act(() => view.rerender(<Surface report={{ messageId: "look-2", visible: true }} />));
        expect(showsRoomDock()).toBe(false);
    });

    it("decides afresh for each room", () => {
        dock.presentations = [roomDock("oid:5")];
        const view = render(<Surface report={{ messageId: "look-1", visible: false }} />);
        expect(showsRoomDock()).toBe(true);

        // Moving to a room the narrative describes: the first room's decision does not carry over.
        act(() => {
            dock.presentations = [roomDock("oid:6")];
            view.rerender(<Surface report={{ messageId: "look-2", visible: true }} />);
        });
        expect(showsRoomDock()).toBe(false);

        // Moving to a room the narrative does not describe shows the dock at once.
        act(() => {
            dock.presentations = [roomDock("oid:7")];
            view.rerender(<Surface report={{ messageId: null, visible: false }} />);
        });
        expect(showsRoomDock()).toBe(true);
    });
});
