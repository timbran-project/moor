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

import { useCallback, useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import type { Transcript, TranscriptGroup } from "../lib/transcript";

export const TRANSCRIPT_WINDOW_GROUPS = 200;
const STEP = 100;

/** Keeps complete groups mounted and preserves a visible group's offset across page changes. */
export function useTranscriptWindow(transcript: Transcript, loadOlder?: () => void, loading = false) {
    const version = useSyncExternalStore(transcript.subscribe, transcript.getVersion);
    const outputRef = useRef<HTMLDivElement>(null);
    const [pinnedEnd, setPinnedEnd] = useState<string | null>(null);
    const [following, setFollowing] = useState(true);
    const follow = useRef(true);
    const anchor = useRef<{ id: string; messageId?: string; offset: number } | null>(null);
    const expectedScroll = useRef<number | null>(null);
    const requestedHistory = useRef<{ first: number; explicit: boolean } | null>(null);
    const destination = useRef<"start" | "end" | null>(null);
    const explicitNavigation = useRef(false);
    const endPosition = pinnedEnd === null ? undefined : transcript.groupPosition(pinnedEnd);
    const end = endPosition === undefined ? transcript.end : endPosition + 1;
    const start = Math.max(transcript.first, end - TRANSCRIPT_WINDOW_GROUPS);
    const visibleGroups: TranscriptGroup[] = [];
    for (let i = start; i < end; i++) {
        const group = transcript.group(i);
        if (group) visibleGroups.push(group);
    }
    const range = useRef({ start, end });
    range.current = { start, end };

    const protectedInteraction = useCallback(() => {
        const element = outputRef.current;
        if (!element) return false;
        const selection = document.getSelection();
        if (
            selection && !selection.isCollapsed
            && (element.contains(selection.anchorNode) || element.contains(selection.focusNode))
        ) return true;
        return element.contains(document.activeElement) && document.activeElement !== element;
    }, []);

    const captureAnchor = useCallback(() => {
        const element = outputRef.current;
        if (!element) return;
        const top = element.getBoundingClientRect().top;
        const rows = element.querySelectorAll<HTMLElement>("[data-transcript-group]");
        const row = Array.from(rows).find(row => row.getBoundingClientRect().bottom > top);
        // Prefer a message inside the group so a merged history page can grow above it.
        const message = row
            && Array.from(row.querySelectorAll<HTMLElement>("[data-transcript-message], [data-message-id]"))
                .find(node =>
                    !node.querySelector("[data-transcript-message], [data-message-id]") && !node.closest(".sr-only")
                    && node.getBoundingClientRect().bottom > top
                );
        anchor.current = row
            ? {
                id: row.dataset.transcriptGroup!,
                messageId: message?.dataset.transcriptMessage ?? message?.dataset.messageId,
                offset: (message || row).getBoundingClientRect().top - top,
            }
            : null;
    }, []);

    const pin = useCallback(() => {
        follow.current = false;
        setFollowing(false);
        setPinnedEnd(transcript.group(range.current.end - 1)?.id ?? null);
    }, [transcript]);

    const restore = useCallback(() => {
        const element = outputRef.current;
        if (!element || (!explicitNavigation.current && protectedInteraction())) return;
        explicitNavigation.current = false;
        if (destination.current === "start") {
            element.scrollTop = 0;
        } else if (follow.current || destination.current === "end") {
            element.scrollTop = element.scrollHeight;
        } else if (anchor.current) {
            const saved = anchor.current;
            const message = saved.messageId
                && Array.from(element.querySelectorAll<HTMLElement>("[data-transcript-message], [data-message-id]"))
                    .find(node =>
                        (node.dataset.transcriptMessage ?? node.dataset.messageId) === saved.messageId
                        && !node.querySelector("[data-transcript-message], [data-message-id]")
                        && !node.closest(".sr-only")
                    );
            const row = message || Array.from(element.querySelectorAll<HTMLElement>("[data-transcript-group]"))
                .find(row => row.dataset.transcriptGroup === saved.id);
            if (row) {
                element.scrollTop += row.getBoundingClientRect().top - element.getBoundingClientRect().top
                    - saved.offset;
            }
        }
        destination.current = null;
        expectedScroll.current = element.scrollTop;
        captureAnchor();
    }, [captureAnchor, protectedInteraction]);

    const move = useCallback((direction: -1 | 1, explicit = false) => {
        captureAnchor();
        explicitNavigation.current = explicit;
        if (explicit) destination.current = "start";
        pin();
        const current = range.current;
        if (direction < 0 && current.start === transcript.first) {
            if (loadOlder && !loading) {
                requestedHistory.current = { first: transcript.first, explicit };
                loadOlder();
            }
            return;
        }
        const nextEnd = direction < 0
            ? Math.max(
                transcript.first + Math.min(TRANSCRIPT_WINDOW_GROUPS, transcript.end - transcript.first),
                current.end - STEP,
            )
            : Math.min(transcript.end, current.end + STEP);
        setPinnedEnd(transcript.group(nextEnd - 1)?.id ?? null);
    }, [captureAnchor, pin, transcript, loadOlder, loading]);

    const jumpToNow = useCallback(() => {
        explicitNavigation.current = true;
        destination.current = "end";
        follow.current = true;
        setFollowing(true);
        setPinnedEnd(null);
        anchor.current = null;
        // An explicit navigation request may move the transcript even while its button has focus.
        const element = outputRef.current;
        if (element) element.scrollTop = element.scrollHeight;
    }, []);

    const handleScroll = useCallback(() => {
        const element = outputRef.current;
        if (!element) return;
        if (expectedScroll.current !== null && Math.abs(element.scrollTop - expectedScroll.current) < 1) {
            expectedScroll.current = null;
            return;
        }
        expectedScroll.current = null;
        captureAnchor();
        const nearBottom = element.scrollTop + element.clientHeight >= element.scrollHeight - 100;
        const interacting = protectedInteraction();
        if (nearBottom && range.current.end === transcript.end) {
            follow.current = true;
            setFollowing(true);
            if (!interacting) setPinnedEnd(null);
        } else {
            pin();
        }
        if (interacting) return;
        if (element.scrollTop <= 50) move(-1);
        else if (nearBottom && range.current.end < transcript.end) move(1);
    }, [captureAnchor, protectedInteraction, pin, transcript, move]);

    useEffect(() => {
        let disposed = false;
        const updateInteraction = () => {
            if (disposed) return;
            if (protectedInteraction()) {
                captureAnchor();
                // Keep interactive rows mounted without treating focus or selection as scrolling.
                setPinnedEnd(transcript.group(range.current.end - 1)?.id ?? null);
                return;
            }
            if (follow.current) {
                setPinnedEnd(null);
                restore();
            }
        };
        // The next focused element is available after focusout has finished dispatching.
        const releaseFocus = () => queueMicrotask(updateInteraction);
        document.addEventListener("selectionchange", updateInteraction);
        const element = outputRef.current;
        element?.addEventListener("focusin", updateInteraction);
        element?.addEventListener("focusout", releaseFocus);
        return () => {
            disposed = true;
            document.removeEventListener("selectionchange", updateInteraction);
            element?.removeEventListener("focusin", updateInteraction);
            element?.removeEventListener("focusout", releaseFocus);
        };
    }, [captureAnchor, protectedInteraction, restore, transcript]);

    useLayoutEffect(() => {
        if (transcript.size === 0) {
            follow.current = true;
            setFollowing(true);
            setPinnedEnd(null);
            anchor.current = null;
            requestedHistory.current = null;
        }
        const requested = requestedHistory.current;
        if (requested && transcript.first < requested.first) {
            requestedHistory.current = null;
            explicitNavigation.current = requested.explicit;
            if (requested.explicit) destination.current = "start";
            const nextEnd = Math.max(
                transcript.first + Math.min(TRANSCRIPT_WINDOW_GROUPS, transcript.end - transcript.first),
                end - STEP,
            );
            if (nextEnd !== end) {
                setPinnedEnd(transcript.group(nextEnd - 1)?.id ?? null);
                return;
            }
        }
        restore();
    }, [version, start, end, following, loading, restore, transcript]);

    useEffect(() => {
        const element = outputRef.current;
        if (!element) return;
        const observer = new ResizeObserver(restore);
        observer.observe(element);
        element.querySelectorAll("[data-transcript-group]").forEach(row => observer.observe(row));
        return () => observer.disconnect();
    }, [start, end, version, restore]);

    return {
        outputRef,
        version,
        visibleGroups,
        start,
        end,
        handleScroll,
        jumpToNow,
        older: () => move(-1, true),
        newer: () => move(1, true),
        hasOlder: start > transcript.first || !!loadOlder,
        hasNewer: end < transcript.end,
        isViewingHistory: !following || end < transcript.end,
    };
}
