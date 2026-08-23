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

import { useCallback } from "react";
import { useExternalNavigation } from "../context/ExternalNavigationContext";
import { InspectController } from "./useInspectPopover";

interface UseNarrativeLinksArgs {
    authToken: string | null;
    sendMessage: (message: string) => boolean;
    showMessage: (message: string, duration?: number) => void;
    inspect: InspectController;
}

/**
 * Routes narrative link clicks by URL scheme:
 * - `moo://cmd/` sends the command as if typed
 * - `moo://inspect/` opens the object inspection popover
 * - `moo://help/` is not yet implemented
 * - http(s) links go through the external-navigation trust policy
 */
export const useNarrativeLinks = ({ sendMessage, showMessage, inspect }: UseNarrativeLinksArgs) => {
    const { openExternalLink } = useExternalNavigation();

    const handleLinkClick = useCallback(async (
        url: string,
        position?: { x: number; y: number },
        metadata?: { actorName?: string; verb?: string },
    ) => {
        if (url.startsWith("moo://cmd/")) {
            // Command link: send as if typed
            const command = decodeURIComponent(url.slice(10));
            sendMessage(command);
        } else if (url.startsWith("moo://inspect/")) {
            // Inspect link: call web_inspect verb and show popover
            const oref = url.slice(14);
            await inspect.inspectObject(oref, position);
        } else if (url.startsWith("moo://help/")) {
            // Help link: show help in panel (TODO)
            const topic = decodeURIComponent(url.slice(11));
            console.log("Help link clicked:", topic);
            showMessage("Help links not yet implemented", 2);
        } else if (url.startsWith("http://") || url.startsWith("https://")) {
            openExternalLink(url, metadata);
        } else {
            console.warn("Unknown link scheme:", url);
        }
    }, [inspect, openExternalLink, sendMessage, showMessage]);

    return { handleLinkClick };
};
