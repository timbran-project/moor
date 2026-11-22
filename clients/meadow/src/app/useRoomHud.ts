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

import { useCallback, useMemo, useState } from "react";
import { usePresentationContext } from "../context/PresentationContext";
import { usePersistentState } from "../hooks/usePersistentState";
import { extractRoomLookKey } from "../lib/var";
import { Presentation } from "../types/presentation";

interface RoomDockLatch {
    roomKey: string | null;
    messageId: string | null;
    latched: boolean;
}

const NO_LATCH: RoomDockLatch = { roomKey: null, messageId: null, latched: false };

const serializeBool = (value: boolean) => value ? "true" : "false";
const deserializeBool = (raw: string): boolean | null => {
    if (raw === "true") return true;
    if (raw === "false") return false;
    return null;
};

/**
 * Owns room-look dock interpretation: deriving the current room key from top
 * dock presentations, suppressing the in-narrative duplicate until the HUD is
 * scrolled away or disabled, and computing the filtered top-dock list.
 */
export const useRoomHud = () => {
    const { getTopDockPresentations } = usePresentationContext();

    const [roomHudEnabled, setRoomHudEnabled] = usePersistentState<boolean>(
        "moor-room-hud-enabled",
        () => true,
        {
            serialize: serializeBool,
            deserialize: deserializeBool,
        },
    );

    // Whether the room dock is shown for a room, and which narrative message that was decided
    // against. The room is part of the state, so a decision made for one room never applies to
    // another and nothing has to reset it when the room changes. An effect that reset it ran
    // after the output window's first report for a new room and discarded it: with no room
    // description in the narrative, as on a first login or a reload without history, no later
    // report came, and the dock stayed hidden over an empty narrative.
    const [dockLatch, setDockLatch] = useState<RoomDockLatch>(NO_LATCH);

    const getRoomLookKeyFromPresentation = useCallback((presentation: Presentation): string | null => {
        const kind = (presentation.attrs.kind || "").toLowerCase();
        if (kind !== "room_look" && kind !== "room-look") {
            return null;
        }
        return extractRoomLookKey([
            presentation.attrs.room,
            presentation.attrs.object,
            presentation.attrs.target,
            presentation.attrs.dobj,
            presentation.attrs.this_obj,
            presentation.attrs.this,
        ]);
    }, []);

    const currentRoomLookKey = useMemo(() => {
        if (!roomHudEnabled) {
            return null;
        }
        const current = getTopDockPresentations();
        for (const presentation of current) {
            if (presentation.id === "room-look") {
                return getRoomLookKeyFromPresentation(presentation);
            }
        }
        return null;
    }, [getRoomLookKeyFromPresentation, getTopDockPresentations, roomHudEnabled]);

    const handleActiveRoomLookVisibilityChange = useCallback((
        roomKey: string | null,
        isVisible: boolean,
        lookMessageId?: string | null,
    ) => {
        if (!currentRoomLookKey || !roomKey || roomKey !== currentRoomLookKey) {
            return;
        }

        setDockLatch((previous) => {
            const forThisRoom = previous.roomKey === roomKey ? previous : { ...NO_LATCH, roomKey };
            // A new description of the room in the narrative starts over: it is the one to watch.
            if (lookMessageId && lookMessageId !== forThisRoom.messageId) {
                return { roomKey, messageId: lookMessageId, latched: false };
            }
            // Out of view, or not in the narrative at all: show the dock, and keep showing it.
            if (!isVisible && !forThisRoom.latched) {
                return { ...forThisRoom, latched: true };
            }
            return forThisRoom === previous ? previous : forThisRoom;
        });
    }, [currentRoomLookKey]);

    const isCurrentRoomLookDockLatched = dockLatch.roomKey === currentRoomLookKey && dockLatch.latched;

    const topDockPresentations = useMemo(() => {
        const current = getTopDockPresentations();
        if (!roomHudEnabled) {
            return current.filter((presentation) => getRoomLookKeyFromPresentation(presentation) === null);
        }
        const suppressRoomKey = !isCurrentRoomLookDockLatched ? currentRoomLookKey : null;
        if (!suppressRoomKey) {
            return current;
        }
        return current.filter((presentation) => {
            if (presentation.target !== "top") {
                return true;
            }
            const roomKey = getRoomLookKeyFromPresentation(presentation);
            if (!roomKey) {
                return true;
            }
            return roomKey !== suppressRoomKey;
        });
    }, [
        currentRoomLookKey,
        getRoomLookKeyFromPresentation,
        getTopDockPresentations,
        isCurrentRoomLookDockLatched,
        roomHudEnabled,
    ]);

    /** Clears latching state after an authority reset (player switch). */
    const resetLatching = useCallback(() => {
        setDockLatch(NO_LATCH);
    }, []);

    return {
        roomHudEnabled,
        setRoomHudEnabled,
        currentRoomLookKey,
        handleActiveRoomLookVisibilityChange,
        topDockPresentations,
        resetLatching,
    };
};
