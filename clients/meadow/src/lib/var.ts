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

import { stringToCurie, uuObjIdToString } from "@moor/web-sdk";

export {
    curieToObjectRef,
    matchRef,
    objToCurie,
    objToString,
    oidRef,
    ORefKind,
    stringToCurie,
    sysobjRef,
    uuidRef,
    uuObjIdToString,
} from "@moor/web-sdk";

export type { MatchRef as ObjMatch, ObjectRef, OidRef as Oid, SysObjRef as SysObj } from "@moor/web-sdk";

export function jsObjectRefToCurie(value: unknown): string | null {
    if (value === null || value === undefined) {
        return null;
    }

    if (typeof value === "number" && Number.isInteger(value)) {
        return `oid:${value}`;
    }

    if (typeof value === "string") {
        const raw = value.trim();
        if (!raw) {
            return null;
        }
        try {
            return stringToCurie(raw);
        } catch {
            return null;
        }
    }

    if (typeof value !== "object" || Array.isArray(value)) {
        return null;
    }

    const candidate = value as { oid?: unknown; uuid?: unknown };
    if (candidate.oid !== undefined && candidate.oid !== null) {
        return jsObjectRefToCurie(candidate.oid);
    }

    if (candidate.uuid !== undefined && candidate.uuid !== null) {
        if (typeof candidate.uuid === "bigint") {
            return `uuid:${uuObjIdToString(candidate.uuid)}`;
        }
        if (typeof candidate.uuid === "number" && Number.isFinite(candidate.uuid) && candidate.uuid >= 0) {
            return `uuid:${uuObjIdToString(BigInt(Math.trunc(candidate.uuid)))}`;
        }
        if (typeof candidate.uuid === "string") {
            const rawUuid = candidate.uuid.trim();
            if (!rawUuid) {
                return null;
            }
            if (/^\d+$/.test(rawUuid)) {
                try {
                    return `uuid:${uuObjIdToString(BigInt(rawUuid))}`;
                } catch {
                    return null;
                }
            }
            try {
                return stringToCurie(rawUuid);
            } catch {
                return null;
            }
        }
    }

    return null;
}

export function normalizedObjectCurie(value: unknown): string | null {
    const curie = jsObjectRefToCurie(value);
    return curie ? curie.toLowerCase() : null;
}

export function extractRoomLookKey(candidates: readonly unknown[]): string | null {
    for (const candidate of candidates) {
        const roomKey = normalizedObjectCurie(candidate);
        if (roomKey) {
            return roomKey;
        }
    }
    return null;
}

export class Error {
    code: string;
    message: string | null;
    constructor(code: string, message: string | null) {
        this.code = code;
        this.message = message;
    }
}
