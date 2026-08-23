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

import { useEffect, useRef } from "react";

export interface PlayerSwitchHandlers {
    /** Authority-scoped UI must be dropped (editors, presentations, dock state). */
    onAuthorityReset: () => void;
    /** The session ended entirely: no player is attached any more. */
    onSessionEnded: () => void;
    /** The history owner changed, so history/encryption state must reset. */
    onHistoryIdentityChanged: () => void;
}

/**
 * Detects player identity transitions and notifies the owning coordinators.
 * A player switch resets authority-scoped UI without replacing the live
 * session or transcript; history state only resets when the switch selects a
 * new history owner.
 */
export const usePlayerSwitch = (
    playerOid: string | null,
    historyPlayerOid: string | null,
    handlers: PlayerSwitchHandlers,
) => {
    const previousPlayerIdentityRef = useRef<{
        playerOid: string | null;
        historyPlayerOid: string | null;
    }>({ playerOid: null, historyPlayerOid: null });

    useEffect(() => {
        const previous = previousPlayerIdentityRef.current;
        const playerChanged = previous.playerOid && previous.playerOid !== playerOid;

        if (playerChanged) {
            handlers.onAuthorityReset();

            if (!playerOid) {
                handlers.onSessionEnded();
            }

            if (previous.historyPlayerOid !== historyPlayerOid) {
                handlers.onHistoryIdentityChanged();
            }
        }

        previousPlayerIdentityRef.current = { playerOid, historyPlayerOid };
    }, [handlers, historyPlayerOid, playerOid]);
};
