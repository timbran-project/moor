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
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { installMockWebHostWebSocket } from "../../../web-sdk/src/testing/mock-web-host";
import type { Player } from "./useAuth";
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

            const player: Player = {
                oid: "oid:7",
                authToken: "auth-1",
                historyOid: "oid:7",
                historyAuthToken: "auth-1",
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

            const player: Player = {
                oid: "oid:7",
                authToken: "auth-1",
                historyOid: "oid:7",
                historyAuthToken: "auth-1",
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

            const player: Player = {
                oid: "oid:7",
                authToken: "auth-1",
                historyOid: "oid:7",
                historyAuthToken: "auth-1",
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

    it("reports initial authentication failure without reconnecting", async () => {
        vi.useFakeTimers();
        const mockHost = installMockWebHostWebSocket();
        const onAuthFailure = vi.fn();

        try {
            installLocalStorageMock();
            const player: Player = {
                oid: "oid:7",
                authToken: "invalid-token",
                historyOid: "oid:7",
                historyAuthToken: "invalid-token",
                connected: false,
                flags: 0,
                isInitialAttach: true,
            };

            const { result } = renderHook(() =>
                useWebSocket(
                    player,
                    vi.fn(),
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    onAuthFailure,
                )
            );

            await act(async () => {
                await result.current.connect("connect");
            });

            act(() => {
                mockHost.takeConnection(0)?.serverClose(4401, "invalid token");
            });

            expect(onAuthFailure).toHaveBeenCalledOnce();
            await act(async () => {
                vi.advanceTimersByTime(3000);
            });
            expect(mockHost.connections).toHaveLength(1);
        } finally {
            mockHost.restore();
        }
    });

    it("reports completion after the first successful initial attach", async () => {
        const mockHost = installMockWebHostWebSocket();
        const onInitialAttachComplete = vi.fn();

        try {
            installLocalStorageMock();
            const player: Player = {
                oid: "oid:7",
                authToken: "auth-1",
                historyOid: "oid:7",
                historyAuthToken: "auth-1",
                connected: false,
                flags: 0,
                isInitialAttach: true,
            };

            const { result } = renderHook(() =>
                useWebSocket(
                    player,
                    vi.fn(),
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    undefined,
                    onInitialAttachComplete,
                )
            );

            await act(async () => {
                await result.current.connect("connect");
            });
            act(() => {
                mockHost.takeConnection(0)?.serverOpen();
            });

            expect(onInitialAttachComplete).toHaveBeenCalledOnce();
        } finally {
            mockHost.restore();
        }
    });
});

describe("WebSocket handshake recovery", () => {
    let mockHost: ReturnType<typeof installMockWebHostWebSocket>;
    const player: Player = {
        oid: "oid:7",
        authToken: "auth-1",
        historyOid: "oid:7",
        historyAuthToken: "auth-1",
        connected: false,
        flags: 0,
        isInitialAttach: true,
    };

    function renderConnection() {
        const onAuthFailure = vi.fn();
        const onSystemMessage = vi.fn();
        const hook = renderHook(() =>
            useWebSocket(
                player,
                onSystemMessage,
                undefined,
                undefined,
                undefined,
                undefined,
                undefined,
                undefined,
                undefined,
                onAuthFailure,
            )
        );
        return { ...hook, onAuthFailure };
    }

    beforeEach(() => {
        vi.useFakeTimers();
        installLocalStorageMock();
        mockHost = installMockWebHostWebSocket();
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 200 })));
    });

    afterEach(() => {
        mockHost.restore();
        vi.unstubAllGlobals();
        vi.useRealTimers();
        sessionStorage.clear();
    });

    it("times out a stalled handshake, preserves credentials and reconnects with a new attempt ID", async () => {
        const { result, onAuthFailure } = renderConnection();
        sessionStorage.setItem("client_id", "11111111-1111-1111-1111-111111111111");
        sessionStorage.setItem("client_token", "keep-token");
        await act(async () => {
            await result.current.connect("create");
        });
        const firstAttempt = new URL(mockHost.connections[0].url).searchParams.get("attempt");
        expect(firstAttempt).toMatch(/^[0-9a-f-]{36}$/);
        await act(async () => {
            await vi.advanceTimersByTimeAsync(14999);
        });
        expect(result.current.wsState.connectionStatus).toBe("connecting");
        await act(async () => {
            await vi.advanceTimersByTimeAsync(1);
        });
        expect(result.current.wsState.connectionStatus).toBe("error");
        expect(result.current.wsState.connectionError).toBe("Connection timed out after 15 seconds");
        expect(onAuthFailure).not.toHaveBeenCalled();
        expect(sessionStorage.getItem("client_token")).toBe("keep-token");
        await act(async () => {
            await vi.advanceTimersByTimeAsync(3000);
        });
        expect(mockHost.connections).toHaveLength(2);
        expect(mockHost.connections[1].url).toContain("/ws/attach/connect");
        expect(new URL(mockHost.connections[1].url).searchParams.get("attempt")).not.toBe(firstAttempt);
        act(() => {
            mockHost.takeConnection(1)?.serverOpen();
            mockHost.takeConnection(0)?.serverClose(4401, "late rejection");
        });
        await act(async () => {
            await vi.advanceTimersByTimeAsync(15000);
        });
        expect(result.current.wsState.isConnected).toBe(true);
        expect(result.current.wsState.connectionError).toBeUndefined();
        expect(onAuthFailure).not.toHaveBeenCalled();
        expect(mockHost.connections).toHaveLength(2);
    });

    it.each([200, 503])("retries a failed first handshake when validation returns %i", async status => {
        vi.mocked(fetch).mockResolvedValue(new Response(null, { status }));
        const { result, onAuthFailure } = renderConnection();
        await act(async () => {
            await result.current.connect("connect");
        });
        await act(async () => {
            mockHost.takeConnection()?.serverClose(1006);
        });
        expect(onAuthFailure).not.toHaveBeenCalled();
        expect(result.current.wsState.connectionStatus).toBe("error");
        await act(async () => {
            await vi.advanceTimersByTimeAsync(3000);
        });
        expect(mockHost.connections).toHaveLength(2);
    });

    it("returns to login only after HTTP validation confirms rejection", async () => {
        vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 401 }));
        const { result, onAuthFailure } = renderConnection();
        await act(async () => {
            await result.current.connect("connect");
        });
        await act(async () => {
            mockHost.takeConnection()?.serverClose(1006);
        });
        expect(onAuthFailure).toHaveBeenCalledOnce();
        await act(async () => {
            await vi.advanceTimersByTimeAsync(30000);
        });
        expect(mockHost.connections).toHaveLength(1);
    });

    it("bounds an unavailable validation request and retries without logging out", async () => {
        vi.mocked(fetch).mockImplementation((_input, init) =>
            new Promise((_resolve, reject) => {
                init?.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
            })
        );
        const { result, onAuthFailure } = renderConnection();
        await act(async () => {
            await result.current.connect("connect");
        });
        await act(async () => {
            mockHost.takeConnection()?.serverClose(1006);
        });
        await act(async () => {
            await vi.advanceTimersByTimeAsync(8000);
        });
        expect(mockHost.connections).toHaveLength(2);
        expect(onAuthFailure).not.toHaveBeenCalled();
    });

    it("ignores validation responses from a superseded attempt", async () => {
        let finish!: (response: Response) => void;
        vi.mocked(fetch).mockReturnValue(
            new Promise(resolve => {
                finish = resolve;
            }),
        );
        const { result, onAuthFailure } = renderConnection();
        await act(async () => {
            await result.current.connect("connect");
        });
        await act(async () => {
            mockHost.takeConnection()?.serverClose(1006);
        });
        await act(async () => {
            await result.current.connect("connect", true);
        });
        act(() => {
            mockHost.takeConnection(1)?.serverOpen();
        });
        await act(async () => {
            finish(new Response(null, { status: 401 }));
        });
        expect(onAuthFailure).not.toHaveBeenCalled();
        expect(result.current.wsState.isConnected).toBe(true);
    });

    it.each(["disconnect", "unmount"])("cancels pending handshake work on %s", async action => {
        const { result, unmount, onAuthFailure } = renderConnection();
        await act(async () => {
            await result.current.connect("connect");
        });
        act(() => {
            if (action === "unmount") unmount();
            else result.current.disconnect("LOGOUT");
        });
        await act(async () => {
            await vi.advanceTimersByTimeAsync(60000);
        });
        expect(mockHost.connections).toHaveLength(1);
        expect(onAuthFailure).not.toHaveBeenCalled();
        expect(fetch).not.toHaveBeenCalled();
    });
});
