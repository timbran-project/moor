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

/** URL links use the external navigation policy. Semantic actions carry typed event metadata. */
export const useNarrativeLinks = () => {
    const { openExternalLink } = useExternalNavigation();
    const handleLinkClick = useCallback((
        url: string,
        _position?: { x: number; y: number },
        metadata?: { actorName?: string; verb?: string },
    ) => {
        if (url.startsWith("http://") || url.startsWith("https://")) openExternalLink(url, metadata);
    }, [openExternalLink]);
    return { handleLinkClick };
};
