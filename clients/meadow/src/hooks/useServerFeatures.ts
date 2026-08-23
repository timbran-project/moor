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

import { useEffect, useState } from "react";
import { fetchServerFeatures } from "../lib/rpc-fb";

export interface ServerFeatures {
    eventLogEnabled: boolean | null;
}

/**
 * Owns the server feature probe. `eventLogEnabled` stays null until the probe
 * completes so callers can distinguish "unknown" from "disabled".
 */
export const useServerFeatures = (): ServerFeatures => {
    const [eventLogEnabled, setEventLogEnabled] = useState<boolean | null>(null);

    useEffect(() => {
        let cancelled = false;
        fetchServerFeatures()
            .then((features) => {
                if (cancelled) {
                    return;
                }
                setEventLogEnabled(features.enableEventlog);
            })
            .catch((error) => {
                console.error("Failed to fetch server features:", error);
                if (!cancelled) {
                    setEventLogEnabled(true);
                }
            });

        return () => {
            cancelled = true;
        };
    }, []);

    return { eventLogEnabled };
};
