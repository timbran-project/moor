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

import { act, fireEvent, render, screen } from "@testing-library/react";
import { useLayoutEffect, useMemo, useState } from "react";
import { expect, it, vi } from "vitest";
import { installMockWebHostWebSocket } from "../../../web-sdk/src/testing/mock-web-host";
import type { NarrativeRef } from "../components/Narrative";
import { useWebSocketContext } from "../context/WebSocketContext";
import type { useWebSocket } from "../hooks/useWebSocket";
import { SessionCoordinator, useNarrativePipelineContext } from "./SessionCoordinator";

const session = vi.hoisted(() => ({
    player: {
        oid: "oid:7",
        historyOid: "oid:7",
        authToken: "test-token",
        historyAuthToken: "history-token",
        connected: false,
        flags: 0,
    },
    disconnect: vi.fn(),
    update: vi.fn(),
    showMessage: vi.fn(),
    present: vi.fn(),
    fail: false,
    receive: undefined as Parameters<typeof useWebSocket>[5],
    controls: undefined as ReturnType<typeof useWebSocket> | undefined,
}));
vi.mock("../context/AuthContext", () => ({
    useAuthContext: () => ({
        authState: { player: session.player },
        clearInitialAttach: session.update,
        disconnect: session.disconnect,
        rotatePlayerIdentity: session.update,
        setPlayerConnected: session.update,
        updateReconnectCredentials: session.update,
    }),
}));
vi.mock("../components/MessageBoard", () => ({ useSystemMessage: () => ({ showMessage: session.showMessage }) }));
vi.mock(
    "../context/PresentationContext",
    () => ({
        usePresentationContext: () => ({ addPresentation: session.present, removePresentation: session.present }),
    }),
);
vi.mock("../hooks/useWebSocket", async importOriginal => {
    const original = await importOriginal<typeof import("../hooks/useWebSocket")>();
    return {
        ...original,
        useWebSocket: (...args: Parameters<typeof original.useWebSocket>) => {
            session.receive = args[5];
            const result = original.useWebSocket(...args);
            session.controls = result;
            return result;
        },
    };
});

function Surface() {
    const { wsState } = useWebSocketContext();
    const { narrativeCallbackRef } = useNarrativePipelineContext();
    const [messages, setMessages] = useState<string[]>([]);
    const narrative = useMemo(() => ({
        addNarrativeContent: (content: string | string[]) => setMessages(previous => [...previous, String(content)]),
    } as unknown as NarrativeRef), []);
    useLayoutEffect(() => {
        narrativeCallbackRef(narrative);
        return () => narrativeCallbackRef(null);
    }, [narrative, narrativeCallbackRef]);
    if (session.fail) throw new Error("interface render failed");
    return (
        <>
            <p>{wsState.isConnected ? "Connected surface" : "Connecting surface"}</p>
            {messages.map((text, i) => <p key={i}>{text}</p>)}
        </>
    );
}

it("keeps the WebSocket open and replays new output after main-interface recovery", async () => {
    const host = installMockWebHostWebSocket();
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});
    const ignoreError = (event: ErrorEvent) => event.preventDefault();
    window.addEventListener("error", ignoreError);
    localStorage.setItem("saved-session", "keep-me");
    const rendered = render(
        <SessionCoordinator>
            <Surface />
        </SessionCoordinator>,
    );
    try {
        await act(async () => {
            await session.controls!.connect("connect");
        });
        act(() => host.takeConnection(0)!.serverOpen());
        expect(screen.getByText("Connected surface")).not.toBeNull();
        session.fail = true;
        rendered.rerender(
            <SessionCoordinator>
                <Surface />
            </SessionCoordinator>,
        );
        expect(screen.getByRole("button", { name: "Retry interface" })).not.toBeNull();
        expect(session.controls!.sendMessage("look")).toBe(true);
        act(() => session.receive!("Arrived during recovery", undefined, "text/plain"));
        session.fail = false;
        fireEvent.click(screen.getByRole("button", { name: "Retry interface" }));
        expect(screen.getByText("Connected surface")).not.toBeNull();
        expect(screen.getByText("Arrived during recovery")).not.toBeNull();
        expect(session.controls!.sendMessage("look again")).toBe(true);
        expect(host.connections).toHaveLength(1);
        expect(session.disconnect).not.toHaveBeenCalled();
        expect(localStorage.getItem("saved-session")).toBe("keep-me");
    } finally {
        session.fail = false;
        rendered.unmount();
        host.restore();
        window.removeEventListener("error", ignoreError);
        errorLog.mockRestore();
        localStorage.clear();
        sessionStorage.clear();
    }
});
