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

import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { NarrativeMessage } from "../components/Narrative";
import { useUnseenTitle } from "./useUnseenTitle";

const liveMessage = (): NarrativeMessage => ({
    id: `m-${Math.random()}`,
    content: "live",
    type: "narrative",
} as NarrativeMessage);

const historicalMessage = (): NarrativeMessage => ({
    ...liveMessage(),
    isHistorical: true,
} as NarrativeMessage);

describe("useUnseenTitle", () => {
    const originalTitle = document.title;

    afterEach(() => {
        document.title = originalTitle;
    });

    let originalHidden: boolean | undefined;
    let originalHasFocus: (() => boolean) | undefined;

    function hideDocument() {
        originalHidden = Object.getOwnPropertyDescriptor(Document.prototype, "hidden")
            ?.get.call(document) as boolean;
        originalHasFocus = document.hasFocus.bind(document);
        Object.defineProperty(document, "hidden", { configurable: true, value: true });
        document.hasFocus = () => false;
    }

    function restoreDocument() {
        if (originalHidden !== undefined) {
            delete (document as any).hidden;
            Object.defineProperty(document, "hidden", { configurable: true, value: originalHidden });
        }
        if (originalHasFocus) {
            document.hasFocus = originalHasFocus;
        }
    }

    it("does not count messages while the document is visible and focused", () => {
        const originalHasFocus = document.hasFocus.bind(document);
        document.hasFocus = () => true;
        try {
            const { result } = renderHook(() => useUnseenTitle("mooR"));

            act(() => {
                result.current.handleMessageAppended(liveMessage());
            });

            expect(result.current.unseenCount).toBe(0);
            expect(document.title).toBe("mooR");
        } finally {
            document.hasFocus = originalHasFocus;
        }
    });

    it("counts live messages while hidden and resets on focus", () => {
        hideDocument();
        try {
            const { result } = renderHook(() => useUnseenTitle("mooR"));

            act(() => {
                result.current.handleMessageAppended(liveMessage());
                result.current.handleMessageAppended(liveMessage());
            });

            expect(result.current.unseenCount).toBe(2);
            expect(document.title).toBe("(2) mooR");

            act(() => {
                result.current.resetUnseen();
            });

            expect(result.current.unseenCount).toBe(0);
            expect(document.title).toBe("mooR");
        } finally {
            restoreDocument();
        }
    });

    it("ignores historical messages", () => {
        hideDocument();
        try {
            const { result } = renderHook(() => useUnseenTitle("mooR"));

            act(() => {
                result.current.handleMessageAppended(historicalMessage());
            });

            expect(result.current.unseenCount).toBe(0);
        } finally {
            restoreDocument();
        }
    });

    it("caps the badge count", () => {
        hideDocument();
        try {
            const { result } = renderHook(() => useUnseenTitle("mooR"));

            act(() => {
                for (let i = 0; i < 150; i++) {
                    result.current.handleMessageAppended(liveMessage());
                }
            });

            expect(result.current.unseenCount).toBe(99);
        } finally {
            restoreDocument();
        }
    });

    it("notifies the caller of live activity for non-historical messages", () => {
        let liveEvents = 0;
        const { result } = renderHook(() =>
            useUnseenTitle("mooR", () => {
                liveEvents += 1;
            })
        );

        act(() => {
            result.current.handleMessageAppended(historicalMessage());
        });
        expect(liveEvents).toBe(0);

        act(() => {
            result.current.handleMessageAppended(liveMessage());
        });
        expect(liveEvents).toBe(1);
    });
});
