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

import { Obj } from "@moor/schema/generated/moor-common/obj";
import { ObjId } from "@moor/schema/generated/moor-common/obj-id";
import { ObjUnion } from "@moor/schema/generated/moor-common/obj-union";
import { ClientSuccess } from "@moor/schema/generated/moor-rpc/client-success";
import { DaemonToClientReply } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply";
import { DaemonToClientReplyUnion } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply-union";
import { LoginResult } from "@moor/schema/generated/moor-rpc/login-result";
import { ReplyResult } from "@moor/schema/generated/moor-rpc/reply-result";
import { ReplyResultUnion } from "@moor/schema/generated/moor-rpc/reply-result-union";
import { act, renderHook } from "@testing-library/react";
import * as flatbuffers from "flatbuffers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAuth } from "./useAuth";

const keypairCalls: Array<{ password: string; identifier: string }> = [];

vi.mock("../lib/keyDerivation", () => ({
    generateKeypairFromPassword: async (password: string, identifier: string) => {
        keypairCalls.push({ password, identifier });
        return { identity: "AGE-SECRET-KEY-TEST", publicKey: "age1pub-registered" };
    },
}));

/// Build a FlatBuffer ReplyResult carrying a successful LoginResult for the given player
function buildLoginSuccessBytes(playerNumber: number): Uint8Array {
    const builder = new flatbuffers.Builder(1024);
    const objIdOffset = ObjId.createObjId(builder, playerNumber);
    const objOffset = Obj.createObj(builder, ObjUnion.ObjId, objIdOffset);
    LoginResult.startLoginResult(builder);
    LoginResult.addSuccess(builder, true);
    LoginResult.addPlayer(builder, objOffset);
    const loginOffset = LoginResult.endLoginResult(builder);
    DaemonToClientReply.startDaemonToClientReply(builder);
    DaemonToClientReply.addReplyType(builder, DaemonToClientReplyUnion.LoginResult);
    DaemonToClientReply.addReply(builder, loginOffset);
    const replyOffset = DaemonToClientReply.endDaemonToClientReply(builder);
    ClientSuccess.startClientSuccess(builder);
    ClientSuccess.addReply(builder, replyOffset);
    const clientSuccessOffset = ClientSuccess.endClientSuccess(builder);
    ReplyResult.startReplyResult(builder);
    ReplyResult.addResultType(builder, ReplyResultUnion.ClientSuccess);
    ReplyResult.addResult(builder, clientSuccessOffset);
    builder.finish(ReplyResult.endReplyResult(builder));
    return builder.asUint8Array();
}

function installLocalStorageMock() {
    let store: Record<string, string> = {};
    Object.defineProperty(window, "localStorage", {
        configurable: true,
        value: {
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
        },
    });
}

interface PutRecord {
    authToken: string | null;
    body: { public_key: string };
}

function installCreateFetch(options: { putSucceeds: boolean }, puts: PutRecord[]) {
    return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = typeof input === "string" ? input : input.toString();
        if (url === "/auth/create") {
            return new Response(new Uint8Array(buildLoginSuccessBytes(123)).buffer as ArrayBuffer, {
                status: 200,
                headers: { "X-Moor-Auth-Token": "auth-token-1" },
            });
        }
        if (url === "/v1/event-log/pubkey" && init?.method === "PUT") {
            puts.push({
                authToken: new Headers(init.headers).get("X-Moor-Auth-Token"),
                body: JSON.parse(String(init.body)),
            });
            return options.putSucceeds
                ? new Response(JSON.stringify({ public_key: "set" }), { status: 200 })
                : new Response("boom", { status: 500 });
        }
        throw new Error(`Unexpected fetch: ${url}`);
    });
}

describe("useAuth account creation encryption registration", () => {
    const systemMessages: string[] = [];
    const recordSystemMessage = (message: string) => {
        systemMessages.push(message);
    };

    afterEach(() => {
        systemMessages.length = 0;
        keypairCalls.length = 0;
        vi.restoreAllMocks();
        vi.unstubAllGlobals();
    });

    it("derives the key from the player OID and registers it after account creation", async () => {
        installLocalStorageMock();
        const puts: PutRecord[] = [];
        vi.stubGlobal("fetch", installCreateFetch({ putSucceeds: true }, puts));
        const { result } = renderHook(() => useAuth(recordSystemMessage));

        await act(async () => {
            await result.current.connect("create", "alice", "accountpw", "encpw");
        });

        // The KDF identifier must be the immutable player OID, never the username
        expect(keypairCalls).toEqual([{ password: "encpw", identifier: "oid:123" }]);
        expect(puts).toEqual([
            { authToken: "auth-token-1", body: { public_key: "age1pub-registered" } },
        ]);
        expect(localStorage.getItem("moor_event_log_identity_oid:123")).toBe(
            "AGE-SECRET-KEY-TEST",
        );
        expect(result.current.authState.player?.oid).toBe("oid:123");
        expect(result.current.authState.error).toBeNull();
    });

    it("falls back to the account password when no encryption password is given", async () => {
        installLocalStorageMock();
        const puts: PutRecord[] = [];
        vi.stubGlobal("fetch", installCreateFetch({ putSucceeds: true }, puts));
        const { result } = renderHook(() => useAuth(recordSystemMessage));

        await act(async () => {
            await result.current.connect("create", "alice", "accountpw");
        });

        expect(keypairCalls).toEqual([{ password: "accountpw", identifier: "oid:123" }]);
        expect(puts).toHaveLength(1);
        expect(result.current.authState.player?.oid).toBe("oid:123");
    });

    it("completes login without a stored identity when registration fails", async () => {
        installLocalStorageMock();
        const puts: PutRecord[] = [];
        vi.stubGlobal("fetch", installCreateFetch({ putSucceeds: false }, puts));
        const { result } = renderHook(() => useAuth(recordSystemMessage));

        await act(async () => {
            await result.current.connect("create", "alice", "accountpw", "encpw");
        });

        expect(puts).toHaveLength(1);
        expect(localStorage.getItem("moor_event_log_identity_oid:123")).toBeNull();
        expect(result.current.authState.player?.oid).toBe("oid:123");
        expect(systemMessages.at(-1)).toContain("Authenticated, but history encryption could not be set up");
    });
});
