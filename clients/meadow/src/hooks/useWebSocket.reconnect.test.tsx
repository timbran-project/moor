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

import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { installMockWebHostWebSocket } from "../../../web-sdk/src/testing/mock-web-host";
import { useWebSocket } from "./useWebSocket";

function installLocalStorageMock() {
    let store: Record<string, string> = {};
    const mock = {
        getItem: (key: string) => store[key] ?? null,
        setItem: (key: string, value: string) => {
            store[key] = value;
        },
        removeItem: (key: string) => {
            delete store[key];
        },
        clear: () => {
            store = {};
        },
    };

    Object.defineProperty(window, "localStorage", {
        value: mock,
        configurable: true,
    });
}

describe("useWebSocket reconnect behavior", () => {
    afterEach(() => {
        vi.useRealTimers();
        sessionStorage.clear();
        installLocalStorageMock();
        localStorage.clear();
    });

    it("reconnects after abnormal close and reuses stored client credentials", async () => {
        vi.useFakeTimers();
        const mockHost = installMockWebHostWebSocket();
        const onSystemMessage = vi.fn();
        const onPlayerConnectedChange = vi.fn();

        try {
            installLocalStorageMock();
            sessionStorage.setItem("client_id", "11111111-1111-1111-1111-111111111111");
            sessionStorage.setItem("client_token", "tok-1");
            localStorage.setItem("client_session_active", "true");

            const player = {
                oid: "oid:7",
                authToken: "auth-1",
                connected: false,
                flags: 0,
                isInitialAttach: false,
            };

            const { result } = renderHook(() =>
                useWebSocket(
                    player,
                    onSystemMessage,
                    onPlayerConnectedChange,
                )
            );

            await act(async () => {
                await result.current.connect("connect");
            });

            expect(mockHost.connections).toHaveLength(1);
            expect(mockHost.connections[0].url).toContain("/ws/attach/connect");
            expect(mockHost.connections[0].protocols).toContain("paseto.auth-1");
            expect(mockHost.connections[0].protocols).toContain("client_id.11111111-1111-1111-1111-111111111111");
            expect(mockHost.connections[0].protocols).toContain("client_token.tok-1");

            const firstConn = mockHost.takeConnection(0);
            expect(firstConn).not.toBeNull();

            act(() => {
                firstConn?.serverOpen();
            });
            expect(result.current.wsState.isConnected).toBe(true);

            act(() => {
                firstConn?.serverClose(1006, "sleep-drop");
            });

            expect(result.current.wsState.isConnected).toBe(false);

            await act(async () => {
                vi.advanceTimersByTime(3000);
                await Promise.resolve();
            });

            expect(mockHost.connections).toHaveLength(2);
            expect(mockHost.connections[1].protocols).toContain("client_id.11111111-1111-1111-1111-111111111111");
            expect(mockHost.connections[1].protocols).toContain("client_token.tok-1");

            const secondConn = mockHost.takeConnection(1);
            act(() => {
                secondConn?.serverOpen();
            });
            expect(result.current.wsState.isConnected).toBe(true);
        } finally {
            mockHost.restore();
        }
    });

    it("proactively reconnects on resume signals (focus/online) when socket may be stale", async () => {
        vi.useFakeTimers();
        const mockHost = installMockWebHostWebSocket();
        const onSystemMessage = vi.fn();
        const onPlayerConnectedChange = vi.fn();

        try {
            installLocalStorageMock();
            sessionStorage.setItem("client_id", "11111111-1111-1111-1111-111111111111");
            sessionStorage.setItem("client_token", "tok-1");
            localStorage.setItem("client_session_active", "true");

            const player = {
                oid: "oid:7",
                authToken: "auth-1",
                connected: false,
                flags: 0,
                isInitialAttach: false,
            };

            const { result } = renderHook(() =>
                useWebSocket(
                    player,
                    onSystemMessage,
                    onPlayerConnectedChange,
                )
            );

            await act(async () => {
                await result.current.connect("connect");
            });

            const firstConn = mockHost.takeConnection(0);
            act(() => {
                firstConn?.serverOpen();
            });
            expect(result.current.wsState.isConnected).toBe(true);

            // Simulate long suspend/resume where browser keeps stale socket open
            await act(async () => {
                vi.advanceTimersByTime(5 * 60 * 1000);
                window.dispatchEvent(new Event("focus"));
                window.dispatchEvent(new Event("online"));
                document.dispatchEvent(new Event("visibilitychange"));
                await Promise.resolve();
            });

            // Desired behavior: resume signals should trigger a fresh reconnect attempt.
            // Current behavior: no proactive reconnect occurs unless close is observed.
            expect(mockHost.connections).toHaveLength(2);
            const resumeReconnectProtocols = mockHost.connections[1].protocols;
            expect(resumeReconnectProtocols).toContain("client_id.11111111-1111-1111-1111-111111111111");
            expect(resumeReconnectProtocols).toContain("client_token.tok-1");
        } finally {
            mockHost.restore();
        }
    });

    it("includes reattach credentials even when client_session_active is false", async () => {
        const mockHost = installMockWebHostWebSocket();
        const onSystemMessage = vi.fn();
        const onPlayerConnectedChange = vi.fn();

        try {
            installLocalStorageMock();
            // Per-tab credentials exist, but global session flag is false.
            // Reattach hints should still be sent for this tab's session.
            sessionStorage.setItem("client_id", "11111111-1111-1111-1111-111111111111");
            sessionStorage.setItem("client_token", "tok-1");
            localStorage.setItem("client_session_active", "false");

            const player = {
                oid: "oid:7",
                authToken: "auth-1",
                connected: false,
                flags: 0,
                isInitialAttach: false,
            };

            const { result } = renderHook(() =>
                useWebSocket(
                    player,
                    onSystemMessage,
                    onPlayerConnectedChange,
                )
            );

            await act(async () => {
                await result.current.connect("connect");
            });

            expect(mockHost.connections).toHaveLength(1);
            const protocols = mockHost.connections[0].protocols;

            expect(protocols).toContain("client_id.11111111-1111-1111-1111-111111111111");
            expect(protocols).toContain("client_token.tok-1");
            expect(protocols).toContain("paseto.auth-1");
        } finally {
            mockHost.restore();
        }
    });
});
