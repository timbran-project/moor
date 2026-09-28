// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { PointerEvent, useCallback, useLayoutEffect, useRef, useState } from "react";

/** Keep a movable card inside the visual viewport, including the mobile keyboard. */
export function useFloatingCard(position: { x: number; y: number }, enabled = true) {
    const cardRef = useRef<HTMLDivElement>(null);
    const drag = useRef<{ pointerId: number; offsetX: number; offsetY: number } | null>(null);
    const [isDragging, setIsDragging] = useState(false);
    const place = useCallback((x: number, y: number, preferAbove = false) => {
        const card = cardRef.current;
        if (!card) return;
        const viewport = window.visualViewport;
        const left = (viewport?.offsetLeft ?? 0) + 16;
        const top = (viewport?.offsetTop ?? 0) + 16;
        const width = viewport?.width ?? window.innerWidth;
        const height = viewport?.height ?? window.innerHeight;
        card.style.maxWidth = `${Math.max(0, Math.min(360, width - 32))}px`;
        card.style.maxHeight = `${Math.max(0, height - 32)}px`;
        const rect = card.getBoundingClientRect();
        if (preferAbove && y + rect.height > top + height - 32) y -= rect.height + 8;
        card.style.left = `${Math.max(left, Math.min(x, left + width - 32 - rect.width))}px`;
        card.style.top = `${Math.max(top, Math.min(y, top + height - 32 - rect.height))}px`;
    }, []);
    useLayoutEffect(() => {
        const card = cardRef.current;
        if (!card) return;
        let placed = false;
        const reposition = () => {
            const rect = card.getBoundingClientRect();
            place(placed ? rect.left : position.x, placed ? rect.top : position.y, !placed);
            placed = true;
        };
        reposition();
        const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(reposition);
        observer?.observe(card);
        window.addEventListener("resize", reposition);
        window.visualViewport?.addEventListener("resize", reposition);
        window.visualViewport?.addEventListener("scroll", reposition);
        return () => {
            observer?.disconnect();
            window.removeEventListener("resize", reposition);
            window.visualViewport?.removeEventListener("resize", reposition);
            window.visualViewport?.removeEventListener("scroll", reposition);
        };
    }, [position.x, position.y, place]);
    const endDrag = (event: PointerEvent<HTMLDivElement>) => {
        if (drag.current?.pointerId !== event.pointerId) return;
        drag.current = null;
        setIsDragging(false);
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
            event.currentTarget.releasePointerCapture(event.pointerId);
        }
    };
    return {
        cardRef,
        isDragging,
        dragHandlers: {
            onPointerDown: (event: PointerEvent<HTMLDivElement>) => {
                if (!enabled || event.button !== 0 || drag.current || (event.target as Element).closest("button")) {
                    return;
                }
                const card = cardRef.current;
                if (!card) return;
                const rect = card.getBoundingClientRect();
                event.currentTarget.setPointerCapture(event.pointerId);
                drag.current = {
                    pointerId: event.pointerId,
                    offsetX: event.clientX - rect.left,
                    offsetY: event.clientY - rect.top,
                };
                setIsDragging(true);
                event.preventDefault();
            },
            onPointerMove: (event: PointerEvent<HTMLDivElement>) => {
                const current = drag.current;
                if (current?.pointerId === event.pointerId) {
                    place(event.clientX - current.offsetX, event.clientY - current.offsetY);
                }
            },
            onPointerUp: endDrag,
            onPointerCancel: endDrag,
            onLostPointerCapture: endDrag,
        },
    };
}
