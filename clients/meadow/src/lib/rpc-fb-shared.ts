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

import {
    createMoorApiClient,
    createUnauthorizedAwareFetch,
    type NarrativeMessageHandler,
    type WsEventMetadata,
    type WsLinkPreview,
} from "@moor/web-sdk";

import { buildAuthHeaders, handleUnauthorized } from "./authHeaders";

export const moorFetch = createUnauthorizedAwareFetch(handleUnauthorized);
export const moorApi = createMoorApiClient({ fetcher: moorFetch });
export function authHeaders(authToken: string, extraHeaders?: Record<string, string>): Record<string, string> {
    return {
        ...buildAuthHeaders(authToken),
        ...(extraHeaders ?? {}),
    };
}

export interface ServerFeatureSet {
    persistentTasks: boolean;
    richNotify: boolean;
    lexicalScopes: boolean;
    typeDispatch: boolean;
    flyweightType: boolean;
    listComprehensions: boolean;
    boolType: boolean;
    useBooleanReturns: boolean;
    symbolType: boolean;
    useSymbolsInBuiltins: boolean;
    customErrors: boolean;
    useUuobjids: boolean;
    enableEventlog: boolean;
    anonymousObjects: boolean;
}

export type EventMetadata = WsEventMetadata;
export type LinkPreview = WsLinkPreview;
export type { NarrativeMessageHandler };
