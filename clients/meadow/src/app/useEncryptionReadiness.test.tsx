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

import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AuthProvider, useAuthContext } from "../context/AuthContext";
import { EncryptionProvider, useEncryptionContext } from "../context/EncryptionContext";
import { useOAuth2Session } from "../hooks/useOAuth2Session";
import { useEncryptionReadiness } from "./useEncryptionReadiness";

const crypto = vi.hoisted(() => ({
    derive: vi.fn(async (): Promise<Uint8Array> => new Uint8Array(32)),
}));
vi.mock("../lib/keyDerivation", () => ({ deriveKeyBytes: crypto.derive }));
vi.mock("../lib/age-decrypt", () => ({
    identityFromDerivedBytes: () => "AGE-SECRET-KEY-test",
    publicKeyFromIdentity: async () => "age1test",
}));

const showMessage = vi.fn();
const reloadHistory = vi.fn();
const password = "oauth-encryption-secret";

function EncryptionScope({ children }: { children: ReactNode }) {
    const { authState } = useAuthContext();
    return (
        <EncryptionProvider
            authToken={authState.player?.historyAuthToken ?? null}
            playerOid={authState.player?.historyOid ?? null}
        >
            {children}
        </EncryptionProvider>
    );
}
function Providers({ children }: { children: ReactNode }) {
    return (
        <AuthProvider showMessage={showMessage}>
            <EncryptionScope>{children}</EncryptionScope>
        </AuthProvider>
    );
}
function renderSession(enabled: boolean | null = true) {
    return renderHook(({ enabled }) => {
        const auth = useAuthContext();
        return {
            auth,
            encryption: useEncryptionContext(),
            oauth: useOAuth2Session(auth.establishSession, showMessage),
            readiness: useEncryptionReadiness(enabled, reloadHistory),
        };
    }, { wrapper: Providers, initialProps: { enabled } });
}
async function login(hook: ReturnType<typeof renderSession>) {
    await act(async () => {
        await hook.result.current.oauth.handleOAuth2AccountChoice({
            mode: "oauth2_create",
            oauth2_code: "code",
            player_name: "player",
            encrypt_password: password,
        });
    });
    await waitFor(() => expect(hook.result.current.encryption.encryptionState.hasCheckedOnce).toBe(true));
}
function installFetch(options: {
    registered?: string;
    statusFailure?: boolean;
    put?: () => Promise<Response>;
} = {}) {
    return vi.stubGlobal(
        "fetch",
        vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
            const url = String(input);
            if (url === "/auth/oauth2/account") {
                return new Response(JSON.stringify({ success: true, auth_token: "auth-seven", player: "oid:7" }));
            }
            if (url === "/v1/event-log/pubkey") {
                if (init?.method === "PUT") return options.put ? options.put() : new Response(null, { status: 200 });
                if (options.statusFailure) return new Response(null, { status: 500 });
                return new Response(JSON.stringify({ public_key: options.registered ?? null }));
            }
            if (url === "/auth/validate") return new Response(null, { status: 200 });
            throw new Error(`Unexpected request: ${url}`);
        }),
    );
}

describe("OAuth encryption handoff across auth and readiness owners", () => {
    beforeEach(() => {
        localStorage.clear();
        sessionStorage.clear();
        window.history.replaceState({}, "", "/");
        vi.clearAllMocks();
        crypto.derive.mockResolvedValue(new Uint8Array(32));
        installFetch();
    });
    afterEach(() => {
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("sets up encryption once without persisting or transmitting the password, then reloads history", async () => {
        const localWrites = vi.spyOn(localStorage, "setItem");
        const sessionWrites = vi.spyOn(sessionStorage, "setItem");
        const hook = renderSession();
        await login(hook);
        await waitFor(() => expect(reloadHistory).toHaveBeenCalledTimes(1));
        expect(crypto.derive).toHaveBeenCalledExactlyOnceWith(password, "oid:7");
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
        expect(JSON.stringify([...localWrites.mock.calls, ...sessionWrites.mock.calls])).not.toContain(password);
        expect(JSON.stringify(vi.mocked(fetch).mock.calls)).not.toContain(password);
        expect(localStorage.getItem("moor_event_log_identity_oid:7")).toBe("AGE-SECRET-KEY-test");
        expect(hook.result.current.readiness.showEncryptionSetup).toBe(false);
        hook.rerender({ enabled: true });
        expect(crypto.derive).toHaveBeenCalledTimes(1);
    });

    it("waits for feature discovery before consuming the password", async () => {
        const hook = renderSession(null);
        await login(hook);
        expect(crypto.derive).not.toHaveBeenCalled();
        hook.rerender({ enabled: true });
        await waitFor(() => expect(reloadHistory).toHaveBeenCalledTimes(1));
    });

    it("discards the password when event logging is disabled", async () => {
        const hook = renderSession(false);
        await login(hook);
        expect(crypto.derive).not.toHaveBeenCalled();
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
        expect(hook.result.current.readiness.showEncryptionSetup).toBe(false);
    });

    it("discards an unnecessary password for an already configured account", async () => {
        installFetch({ registered: "age1existing" });
        const hook = renderSession();
        await login(hook);
        expect(hook.result.current.readiness.showPasswordPrompt).toBe(true);
        expect(crypto.derive).not.toHaveBeenCalled();
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it("discards the password when the status lookup fails", async () => {
        installFetch({ statusFailure: true });
        const hook = renderSession();
        await login(hook);
        expect(crypto.derive).not.toHaveBeenCalled();
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it("shows manual setup after a returned failure without retaining or retrying the password", async () => {
        installFetch({ put: async () => new Response("private-server-payload", { status: 500 }) });
        const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});
        const hook = renderSession();
        await login(hook);
        await waitFor(() => expect(hook.result.current.readiness.showEncryptionSetup).toBe(true));
        expect(crypto.derive).toHaveBeenCalledTimes(1);
        expect(reloadHistory).not.toHaveBeenCalled();
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
        expect(localStorage.getItem("moor_event_log_identity_oid:7")).toBeNull();
        expect(errorLog).toHaveBeenCalledWith("Pubkey setup failed:", 500);
        hook.rerender({ enabled: true });
        expect(crypto.derive).toHaveBeenCalledTimes(1);
    });

    it("does not log a crypto exception's private contents", async () => {
        crypto.derive.mockRejectedValueOnce(new Error(password));
        const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});
        const hook = renderSession();
        await login(hook);
        await waitFor(() => expect(hook.result.current.readiness.showEncryptionSetup).toBe(true));
        expect(errorLog).toHaveBeenCalledWith("Encryption setup failed");
        expect(errorLog).toHaveBeenCalledTimes(1);
        expect(reloadHistory).not.toHaveBeenCalled();
    });

    it("does not transfer a pending password to a different authenticated identity", async () => {
        const hook = renderSession(null);
        await login(hook);
        act(() =>
            hook.result.current.auth.establishSession({
                authToken: "auth-eight",
                playerOid: "oid:8",
                historyAuthToken: "auth-eight",
                historyPlayerOid: "oid:8",
                playerFlags: 0,
                reconnectCredentials: null,
            })
        );
        hook.rerender({ enabled: true });
        await waitFor(() => expect(hook.result.current.readiness.showEncryptionSetup).toBe(true));
        expect(crypto.derive).not.toHaveBeenCalled();
        expect(hook.result.current.auth.takePendingEncryptionPassword("auth-seven", "oid:7")).toBeNull();
    });

    it.each([200, 500])("ignores automatic setup completion after logout (HTTP %i)", async status => {
        let resolve!: (response: Response) => void;
        const pending = new Promise<Response>(done => {
            resolve = done;
        });
        installFetch({ put: () => pending });
        const hook = renderSession();
        await login(hook);
        await waitFor(() => expect(crypto.derive).toHaveBeenCalledTimes(1));
        act(() => hook.result.current.auth.setPlayerConnected(true));
        expect(hook.result.current.readiness.showEncryptionSetup).toBe(false);
        expect(crypto.derive).toHaveBeenCalledTimes(1);
        const put = vi.mocked(fetch).mock.calls.find(([, init]) => init?.method === "PUT");
        expect(put).toBeDefined();
        act(() => hook.result.current.auth.disconnect());
        expect(put?.[1]?.signal?.aborted).toBe(true);
        await act(async () => {
            resolve(new Response(null, { status }));
        });
        expect(hook.result.current.auth.authState.player).toBeNull();
        expect(localStorage.getItem("moor_event_log_identity_oid:7")).toBeNull();
        expect(hook.result.current.readiness.showEncryptionSetup).toBe(false);
        expect(reloadHistory).not.toHaveBeenCalled();
    });
    it("stops after derivation if the identity changed while the KDF was running", async () => {
        let resolve!: (bytes: Uint8Array) => void;
        crypto.derive.mockReturnValueOnce(
            new Promise<Uint8Array>(done => {
                resolve = done;
            }),
        );
        const hook = renderSession();
        await login(hook);
        await waitFor(() => expect(crypto.derive).toHaveBeenCalledTimes(1));
        act(() =>
            hook.result.current.auth.establishSession({
                authToken: "auth-eight",
                playerOid: "oid:8",
                historyAuthToken: "auth-eight",
                historyPlayerOid: "oid:8",
                playerFlags: 0,
                reconnectCredentials: null,
            })
        );
        await waitFor(() => expect(hook.result.current.encryption.encryptionState.hasCheckedOnce).toBe(true));
        await act(async () => {
            resolve(new Uint8Array(32));
        });
        expect(vi.mocked(fetch).mock.calls.some(([, init]) => init?.method === "PUT")).toBe(false);
        expect(localStorage.getItem("moor_event_log_identity_oid:7")).toBeNull();
        expect(hook.result.current.auth.authState.player?.oid).toBe("oid:8");
        expect(hook.result.current.encryption.encryptionState.hasCheckedOnce).toBe(true);
        expect(reloadHistory).not.toHaveBeenCalled();
    });
});
