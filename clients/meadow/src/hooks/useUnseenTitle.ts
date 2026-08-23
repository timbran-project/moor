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

import { useCallback, useEffect, useState } from "react";
import { NarrativeMessage } from "../components/Narrative";

const MAX_UNSEEN_COUNT = 99;

/**
 * Owns the unread-message badge and the window title that reflects it.
 * The count increments only while the document is hidden or unfocused, and
 * resets on focus or when the caller reports a disconnect.
 */
export const useUnseenTitle = (systemTitle: string, onLiveMessage?: () => void) => {
    const [unseenCount, setUnseenCount] = useState(0);

    const handleMessageAppended = useCallback((message: NarrativeMessage) => {
        if (typeof document === "undefined") {
            return;
        }

        if (message.isHistorical) {
            return;
        }

        onLiveMessage?.();

        const documentHasFocus = typeof document.hasFocus === "function" ? document.hasFocus() : true;

        if (!document.hidden && documentHasFocus) {
            return;
        }

        setUnseenCount(prev => Math.min(prev + 1, MAX_UNSEEN_COUNT));
    }, [onLiveMessage]);

    const resetUnseen = useCallback(() => {
        setUnseenCount(0);
    }, []);

    useEffect(() => {
        if (typeof document === "undefined") {
            return;
        }

        const baseTitle = systemTitle || "mooR";
        const title = unseenCount > 0 ? `(${unseenCount}) ${baseTitle}` : baseTitle;
        document.title = title;
    }, [systemTitle, unseenCount]);

    useEffect(() => {
        if (typeof document === "undefined") {
            return;
        }

        const handleVisibilityChange = () => {
            if (!document.hidden) {
                setUnseenCount(0);
            }
        };

        document.addEventListener("visibilitychange", handleVisibilityChange);
        window.addEventListener("focus", resetUnseen);

        return () => {
            document.removeEventListener("visibilitychange", handleVisibilityChange);
            window.removeEventListener("focus", resetUnseen);
        };
    }, [resetUnseen]);

    return { unseenCount, handleMessageAppended, resetUnseen };
};
