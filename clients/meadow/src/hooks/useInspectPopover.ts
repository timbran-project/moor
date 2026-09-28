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

import { useCallback, useEffect, useRef, useState } from "react";
import { InspectData } from "../components/InspectPopover";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";

interface InspectPopoverState {
    oref: string;
    requestId: number;
    returnFocusTo: HTMLElement | null;
    data: InspectData;
    position: { x: number; y: number };
    isPreview?: boolean;
}

interface UseInspectPopoverArgs {
    authToken: string | null;
    showMessage: (message: string, duration?: number) => void;
    refreshKey: number;
}

/** Fetches read-only inspection data; actions are ordinary connection commands. */
export const useInspectPopover = ({ authToken, showMessage, refreshKey }: UseInspectPopoverArgs) => {
    const [inspectPopover, setInspectPopover] = useState<InspectPopoverState | null>(null);
    const requestGeneration = useRef(0);
    const pendingPreview = useRef(false);

    const closeInspectPopover = useCallback(() => {
        requestGeneration.current += 1;
        pendingPreview.current = false;
        setInspectPopover(null);
    }, []);

    useEffect(() => {
        closeInspectPopover();
        return () => {
            requestGeneration.current += 1;
        };
    }, [authToken, closeInspectPopover]);

    const inspectObject = useCallback(async (
        oref: string,
        position?: { x: number; y: number },
        isPreview?: boolean,
    ) => {
        if (!authToken) {
            showMessage("Not connected", 2);
            return;
        }

        const returnFocusTo = document.activeElement instanceof HTMLElement ? document.activeElement : null;
        const generation = ++requestGeneration.current;
        pendingPreview.current = isPreview === true;
        setInspectPopover(null);
        try {
            const objectRef = decodeURIComponent(oref);
            const { result } = await invokeVerbFlatBuffer(authToken, objectRef, "inspection");
            if (generation !== requestGeneration.current) return;
            pendingPreview.current = false;
            if (result) {
                const data = result as InspectData;
                setInspectPopover({
                    oref: objectRef,
                    requestId: generation,
                    returnFocusTo,
                    data,
                    position: position ?? { x: window.innerWidth / 2, y: window.innerHeight / 2 },
                    ...(isPreview ? { isPreview } : {}),
                });
            } else if (!isPreview) {
                showMessage("No inspect data available", 2);
            }
        } catch (error) {
            if (generation !== requestGeneration.current) return;
            pendingPreview.current = false;
            console.error("Failed to inspect object:", error);
            if (!isPreview) {
                showMessage(`Inspect failed: ${error instanceof Error ? error.message : String(error)}`, 3);
            }
        }
    }, [authToken, showMessage]);

    // Handle end of hold-to-preview
    const dismissPreview = useCallback(() => {
        if (pendingPreview.current) {
            requestGeneration.current += 1;
            pendingPreview.current = false;
        }
        setInspectPopover((current) => {
            // Only dismiss if it's a preview popover
            if (current?.isPreview) return null;
            return current;
        });
    }, []);

    const refreshGeneration = useRef(0);
    const refreshInspection = useCallback(async () => {
        if (!authToken || !inspectPopover) return;
        const generation = requestGeneration.current;
        const refresh = ++refreshGeneration.current;
        try {
            const { result } = await invokeVerbFlatBuffer(authToken, inspectPopover.oref, "inspection");
            if (generation !== requestGeneration.current || refresh !== refreshGeneration.current) return;
            setInspectPopover(current =>
                current && ({
                    ...current,
                    data: result as InspectData || { ...current.data, state: ["Unavailable"], actions: [] },
                })
            );
        } catch {
            if (generation === requestGeneration.current && refresh === refreshGeneration.current) {
                showMessage("Could not refresh the inspection. Try opening it again.", 3);
            }
        }
    }, [authToken, inspectPopover, showMessage]);

    const lastRefreshKey = useRef(refreshKey);
    useEffect(() => {
        if (lastRefreshKey.current === refreshKey) return;
        // Coalesce completion and room-state events from the same command.
        const timer = window.setTimeout(() => {
            lastRefreshKey.current = refreshKey;
            void refreshInspection();
        }, 80);
        return () => window.clearTimeout(timer);
    }, [refreshKey, refreshInspection]);

    return {
        inspectPopover,
        closeInspectPopover,
        inspectObject,
        dismissPreview,
        refreshInspection,
    };
};

export type InspectController = Pick<ReturnType<typeof useInspectPopover>, "inspectObject">;
