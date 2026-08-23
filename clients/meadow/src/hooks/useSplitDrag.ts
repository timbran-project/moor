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
import { usePersistentState } from "./usePersistentState";

const serializeNumber = (value: number) => value.toString();
const deserializeNumber = (raw: string): number | null => {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
};

const MIN_SPLIT_RATIO = 0.2;
const MAX_SPLIT_RATIO = 0.8;

/**
 * Owns the narrative/editor split ratio and its pointer-driven resizing.
 */
export const useSplitDrag = () => {
    const [splitRatio, setSplitRatio] = usePersistentState<number>(
        "moor-split-ratio",
        0.6,
        {
            serialize: serializeNumber,
            deserialize: deserializeNumber,
        },
    );
    const [isDraggingSplit, setIsDraggingSplit] = useState(false);

    const handleSplitMouseDown = useCallback((e: React.MouseEvent) => {
        if (e.button !== 0) return;
        setIsDraggingSplit(true);
        e.preventDefault();
        e.stopPropagation(); // Prevent other drag handlers from interfering
    }, []);

    const handleSplitTouchStart = useCallback((e: React.TouchEvent) => {
        setIsDraggingSplit(true);
        e.preventDefault();
        e.stopPropagation();
    }, []);

    // Add global mouse event listeners for split dragging
    useEffect(() => {
        if (!isDraggingSplit) return;

        const updateSplitRatio = (clientY: number) => {
            // Get the main app layout element to calculate relative position
            const mainElement = document.querySelector(".app_layout") as HTMLElement;
            if (!mainElement) return;

            const rect = mainElement.getBoundingClientRect();
            const relativeY = clientY - rect.top;
            const newRatio = relativeY / rect.height;
            const clampedRatio = Math.max(MIN_SPLIT_RATIO, Math.min(MAX_SPLIT_RATIO, newRatio));

            setSplitRatio(clampedRatio);
        };

        const handleMouseMove = (e: MouseEvent) => {
            updateSplitRatio(e.clientY);
        };

        const handleTouchMove = (e: TouchEvent) => {
            if (e.touches.length === 0) return; // Safety check
            e.preventDefault(); // Prevent scrolling
            e.stopPropagation(); // Prevent other handlers from processing this
            updateSplitRatio(e.touches[0].clientY);
        };

        const endDrag = () => {
            setIsDraggingSplit(false);
        };

        const touchMoveOptions: AddEventListenerOptions = { passive: false, capture: true };
        const touchEndOptions: EventListenerOptions = { capture: true };

        document.addEventListener("mousemove", handleMouseMove);
        document.addEventListener("mouseup", endDrag);
        document.addEventListener("touchmove", handleTouchMove, touchMoveOptions);
        document.addEventListener("touchend", endDrag, touchEndOptions);
        document.body.style.cursor = "row-resize";
        document.body.style.userSelect = "none";

        return () => {
            document.removeEventListener("mousemove", handleMouseMove);
            document.removeEventListener("mouseup", endDrag);
            document.removeEventListener("touchmove", handleTouchMove, touchMoveOptions);
            document.removeEventListener("touchend", endDrag, touchEndOptions);
            document.body.style.cursor = "";
            document.body.style.userSelect = "";
        };
    }, [isDraggingSplit, setSplitRatio]);

    return { splitRatio, isDraggingSplit, handleSplitMouseDown, handleSplitTouchStart };
};
