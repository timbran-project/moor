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

import { createMoorApiClient, MoorApiError, parseObjectCurie, stringToCurie, uuObjIdToString } from "@moor/web-sdk";
import { describe, expect, it } from "vitest";

describe("createMoorApiClient", () => {
    it("returns FlatBuffer bytes for successful requests", async () => {
        const api = createMoorApiClient({
            fetcher: async () => new Response(new Uint8Array([1, 2, 3]), { status: 200 }),
        });

        const bytes = await api.getFlatBuffer("/v1/features");
        expect(Array.from(bytes)).toEqual([1, 2, 3]);
    });

    it("throws MoorApiError for non-OK responses", async () => {
        const api = createMoorApiClient({
            fetcher: async () => new Response("denied", { status: 403, statusText: "Forbidden" }),
        });

        await expect(api.getFlatBuffer("/v1/features")).rejects.toMatchObject({
            name: "MoorApiError",
            kind: "transport",
            status: 403,
            statusText: "Forbidden",
            context: "/v1/features",
        });
    });

    it("returns null on 404 with getFlatBufferOrNullOn404", async () => {
        const api = createMoorApiClient({
            fetcher: async () => new Response("missing", { status: 404, statusText: "Not Found" }),
        });

        const bytes = await api.getFlatBufferOrNullOn404("/v1/system_property/login/welcome_message");
        expect(bytes).toBeNull();
    });

    it("resolves relative paths against baseUrl", async () => {
        let seenUrl = "";
        const api = createMoorApiClient({
            baseUrl: "http://localhost:3000/api",
            fetcher: async (input) => {
                seenUrl = String(input);
                return new Response(new Uint8Array([0]), { status: 200 });
            },
        });

        await api.getFlatBuffer("v1/features");
        expect(seenUrl).toBe("http://localhost:3000/api/v1/features");
    });

    it("exposes MoorApiError instance shape", () => {
        const err = new MoorApiError("protocol", "bad reply", { context: "reply parsing" });
        expect(err.kind).toBe("protocol");
        expect(err.context).toBe("reply parsing");
    });
});

describe("CURIE helpers", () => {
    it("parses oid and uuid curies", () => {
        expect(parseObjectCurie("oid:123")).toEqual({ kind: "oid", oid: 123 });
        expect(parseObjectCurie("uuid:00ABCD-0123456789")).toEqual({ kind: "uuid", uuid: "00ABCD-0123456789" });
    });

    it("normalizes string object references to CURIE", () => {
        expect(stringToCurie("#123")).toBe("oid:123");
        expect(stringToCurie("00abcd-0123456789")).toBe("uuid:00ABCD-0123456789");
    });

    it("formats uuobjid packed value", () => {
        const packed = (1n << 46n) | (2n << 40n) | 0x123456789an;
        expect(uuObjIdToString(packed)).toMatch(/^[0-9A-F]{6}-[0-9A-F]{10}$/);
    });
});
