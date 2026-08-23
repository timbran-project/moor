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
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { NarrativeMessage, NarrativeRef } from "../components/Narrative";
import { useHistoryCoordinator } from "./useHistoryCoordinator";

const mocks = vi.hoisted(() => ({
    addPresentation: vi.fn(),
    connectWS: vi.fn(),
    fetchCurrentPresentations: vi.fn(),
    fetchInitialHistory: vi.fn(),
    fetchMoreHistory: vi.fn(),
    removePresentation: vi.fn(),
    resetHistoryRequestState: vi.fn(),
    setHistoryBoundaryNow: vi.fn(),
}));

vi.mock("../context/PresentationContext", () => ({
    usePresentationContext: () => ({
        addPresentation: mocks.addPresentation,
        removePresentation: mocks.removePresentation,
        fetchCurrentPresentations: mocks.fetchCurrentPresentations,
    }),
}));

vi.mock("../context/WebSocketContext", () => ({
    useWebSocketContext: () => ({
        wsState: {
            isConnected: false,
            connectionStatus: "disconnected",
        },
        connect: mocks.connectWS,
    }),
}));

vi.mock("../hooks/useHistory", () => ({
    useHistory: () => ({
        setHistoryBoundaryNow: mocks.setHistoryBoundaryNow,
        fetchInitialHistory: mocks.fetchInitialHistory,
        fetchMoreHistory: mocks.fetchMoreHistory,
        resetHistoryRequestState: mocks.resetHistoryRequestState,
        isLoadingHistory: false,
    }),
}));

interface Deferred<T> {
    promise: Promise<T>;
    resolve: (value: T) => void;
}

const deferred = <T,>(): Deferred<T> => {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>((resolvePromise) => {
        resolve = resolvePromise;
    });
    return { promise, resolve };
};

const message: NarrativeMessage = {
    id: "old-message",
    content: "old history",
    type: "narrative",
    timestamp: 1,
};

describe("useHistoryCoordinator generations", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    it("does not prepend a pagination result after the history identity changes", async () => {
        const page = deferred<{ messages: NarrativeMessage[]; presentationActions: [] }>();
        mocks.fetchMoreHistory.mockReturnValue(page.promise);
        const prependHistoricalMessages = vi.fn();
        const narrativeRef = {
            current: { prependHistoricalMessages } as unknown as NarrativeRef,
        };
        const showMessage = vi.fn();

        const { result, rerender } = renderHook(
            ({ authToken, historyAuthToken }) =>
                useHistoryCoordinator({
                    authToken,
                    historyAuthToken,
                    encryptionKeyForHistory: "age-key",
                    encryptionHasCheckedOnce: false,
                    encryptionStatusError: null,
                    eventLogEnabled: null,
                    loginMode: "connect",
                    narrativeRef,
                    showMessage,
                }),
            {
                initialProps: {
                    authToken: "auth-one" as string | null,
                    historyAuthToken: "history-one" as string | null,
                },
            },
        );

        let loadMore!: Promise<void>;
        act(() => {
            loadMore = result.current.handleLoadMoreHistory();
        });

        rerender({ authToken: "auth-two", historyAuthToken: "history-two" });
        page.resolve({ messages: [message], presentationActions: [] });

        await act(async () => {
            await loadMore;
        });

        expect(prependHistoricalMessages).not.toHaveBeenCalled();
        expect(mocks.resetHistoryRequestState).toHaveBeenLastCalledWith(true);
    });
});
