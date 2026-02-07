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

export class Error {
    code: string;
    message: string | null;
    constructor(code: string, message: string | null) {
        this.code = code;
        this.message = message;
    }
}
