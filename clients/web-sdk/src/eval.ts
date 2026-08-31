// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

import { Var } from "@moor/schema/generated/moor-var/var";

import { parseVerbCallSuccessFromBytes } from "./verb.js";

/**
 * Parse a web-host /v1/eval FlatBuffer reply and return its Var result payload.
 */
export function parseEvalResultVar(bytes: Uint8Array): Var {
    const { success } = parseVerbCallSuccessFromBytes(bytes, "Eval");
    const varResult = success.result();
    if (!varResult) {
        throw new Error("Missing result var");
    }

    return varResult;
}
