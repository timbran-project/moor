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
import { describe, expect, it, vi } from "vitest";
import type { NarrativeRef } from "../components/Narrative";
import { createEditorLaunchBridge } from "./editorLaunchBridge";
import { useNarrativePipeline } from "./useNarrativePipeline";

vi.mock("../context/PresentationContext", () => ({
    usePresentationContext: () => ({
        addPresentation: vi.fn(),
        removePresentation: vi.fn(),
    }),
}));

vi.mock("../lib/auth-session", () => ({
    readReconnectCredentials: vi.fn(() => null),
}));

describe("useNarrativePipeline buffering", () => {
    it("keeps its ref callback stable and flushes the current buffer once", () => {
        const bridge = createEditorLaunchBridge();
        const { result } = renderHook(() => useNarrativePipeline(bridge));
        const callback = result.current.narrativeCallbackRef;

        act(() => {
            result.current.handlers.handleNarrativeMessage("buffered message", undefined, "text/plain");
        });

        expect(result.current.narrativeCallbackRef).toBe(callback);

        const addNarrativeContent = vi.fn();
        const narrative = { addNarrativeContent } as unknown as NarrativeRef;
        act(() => callback(narrative));

        expect(addNarrativeContent).toHaveBeenCalledTimes(1);
        expect(addNarrativeContent).toHaveBeenCalledWith(
            "buffered message",
            "text/plain",
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        );

        act(() => {
            callback(null);
            callback(narrative);
        });
        expect(addNarrativeContent).toHaveBeenCalledTimes(1);
    });
});
