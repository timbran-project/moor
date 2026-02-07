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

import { decodeServerFeatures, decodeSysPropValue, parseEvalResultVar } from "@moor/web-sdk";

import { MoorVar } from "./MoorVar";
import { authHeaders, moorApi, ServerFeatureSet } from "./rpc-fb-shared";

export async function performEvalFlatBuffer(authToken: string, expr: string): Promise<unknown> {
    try {
        const headers = authHeaders(authToken);
        const bytes = await moorApi.getFlatBuffer("/v1/eval", {
            method: "POST",
            body: expr,
            headers,
        });
        const varResult = parseEvalResultVar(bytes);
        return new MoorVar(varResult).toJS();
    } catch (err) {
        console.error("Exception during FlatBuffer eval:", err);
        throw err;
    }
}

export async function performEvalMoorVar(authToken: string, expr: string): Promise<MoorVar> {
    try {
        const headers = authHeaders(authToken);
        const bytes = await moorApi.getFlatBuffer("/v1/eval", {
            method: "POST",
            body: expr,
            headers,
        });
        const varResult = parseEvalResultVar(bytes);
        return new MoorVar(varResult);
    } catch (err) {
        console.error("Exception during FlatBuffer eval:", err);
        throw err;
    }
}

export async function fetchServerFeatures(): Promise<ServerFeatureSet> {
    const bytes = await moorApi.getFlatBuffer("/v1/features");
    return decodeServerFeatures(bytes);
}

export async function getSystemPropertyFlatBuffer(
    objectPath: string[],
    propertyName: string,
): Promise<unknown | null> {
    try {
        const path = [...objectPath, propertyName].join("/");
        const bytes = await moorApi.getFlatBufferOrNullOn404(`/v1/system_property/${path}`, {
            method: "GET",
        });

        if (bytes === null) {
            return null;
        }
        return decodeSysPropValue(bytes, (value) => new MoorVar(value as any).toJS());
    } catch (err) {
        console.error("Exception during FlatBuffer system property fetch:", err);
        throw err;
    }
}
