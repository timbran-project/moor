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

import { buildStructuredArgs } from "@moor/web-sdk";
import { useEffect, useState } from "react";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";

export interface CommandInputContext {
    template: string;
    active: string;
    bindings: Record<string, string>;
}

export interface SuggestionSource {
    provider: string;
    source: string;
    context?: CommandInputContext;
}

export interface Suggestion {
    id: string;
    label: string;
    value: string;
    detail: string;
}

const NO_SUGGESTIONS: Suggestion[] = [];

interface SuggestionResult {
    items: Suggestion[];
    more: boolean;
}

/** Fetch bounded, server-ranked choices; a response belongs only to its exact input and identity. */
export function useSuggestions(
    authToken: string | null,
    source: SuggestionSource | undefined,
    query: string,
    enabled: boolean,
    revision = 0,
) {
    const provider = source?.provider;
    const name = source?.source;
    const context = JSON.stringify(source?.context ?? {});
    const key = JSON.stringify([authToken, provider, name, context, query, revision]);
    const [response, setResponse] = useState<{ key: string; result?: SuggestionResult; error?: string }>();
    useEffect(() => {
        if (!enabled || !authToken || !provider || !name) return;
        let current = true;
        const timer = window.setTimeout(async () => {
            try {
                const { result } = await invokeVerbFlatBuffer(
                    authToken,
                    provider,
                    "suggestions",
                    buildStructuredArgs([name, query, JSON.parse(context)]),
                );
                if (current) setResponse({ key, result: result as SuggestionResult });
            } catch {
                if (current) setResponse({ key, error: "Suggestions unavailable. You can still enter a name." });
            }
        }, 120);
        return () => {
            current = false;
            window.clearTimeout(timer);
        };
    }, [authToken, provider, name, context, query, enabled, revision, key]);
    const current = enabled && response?.key === key ? response : undefined;
    return {
        items: current?.result?.items ?? NO_SUGGESTIONS,
        more: current?.result?.more ?? false,
        error: current?.error,
        loading: Boolean(enabled && authToken && provider && !current),
    };
}
