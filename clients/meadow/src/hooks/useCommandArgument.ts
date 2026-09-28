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

// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { buildStructuredArgs } from "@moor/web-sdk";
import { useEffect, useState } from "react";
import { CommandDraft, serializeDraft } from "../lib/command-draft";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { SuggestionSource } from "./useSuggestions";

interface CommandArgument {
    start: number;
    end: number;
    query: string;
    label: string;
    source: SuggestionSource;
}

/** Cowbell chooses argument boundaries and syntax; a reply belongs to this exact draft and cursor. */
export function useCommandArgument(
    token: string | null,
    provider: string | null,
    draft: CommandDraft,
    cursor: number,
    enabled: boolean,
) {
    const key = JSON.stringify([token, provider, draft, cursor, enabled]);
    const [response, setResponse] = useState<{ key: string; argument?: CommandArgument }>();
    useEffect(() => {
        if (!enabled || !token || !provider || !draft.text.includes(" ") || draft.text.includes("\n")) return;
        let current = true;
        const timer = setTimeout(async () => {
            const wire = serializeDraft(draft);
            const offset = wire.toWire(cursor);
            try {
                const { result } = await invokeVerbFlatBuffer(
                    token,
                    provider,
                    "command_input_context",
                    buildStructuredArgs([wire.command.slice(0, offset), wire.command.slice(offset)]),
                );
                const context = result as {
                    before?: string;
                    after?: string;
                    query: string;
                    label: string;
                    source: SuggestionSource;
                };
                if (
                    current && typeof context.before === "string" && typeof context.after === "string" && context.source
                ) {
                    setResponse({
                        key,
                        argument: {
                            start: wire.toDisplay(context.before.length),
                            end: wire.toDisplay(wire.command.length - context.after.length),
                            query: context.query,
                            label: context.label,
                            source: context.source,
                        },
                    });
                }
            } catch {
                if (current) setResponse({ key });
            }
        }, 120);
        return () => {
            current = false;
            clearTimeout(timer);
        };
    }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
    return response?.key === key ? response.argument : undefined;
}
