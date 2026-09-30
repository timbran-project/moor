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

import { NarrativeEvent } from "@moor/schema/generated/moor-common/narrative-event";
import { Var } from "@moor/schema/generated/moor-var/var";
import type { NarrativeContent, NarrativeNotifyContentType } from "./content-types.js";
import type { ParsedPresentation } from "./presentations.js";
import { parseNarrativeValue } from "./ws-narrative.js";

export type ParsedNarrativeEvent =
    | { eventType: "NotifyEvent"; event: { value: NarrativeContent; contentType: NarrativeNotifyContentType } }
    | { eventType: "PresentEvent"; event: { presentation: ParsedPresentation } }
    | { eventType: "UnpresentEvent"; event: { presentationId: string } }
    | {
        eventType: "TracebackEvent";
        event: { error: { code: string | null; message: string | null } | null; backtrace: string[] };
    }
    | { eventType: "DataEvent"; event: { namespace: string; kind: string; payload: unknown } };

/** Adapt a validated narrative payload to captured invocation output. */
export function parseNarrativeEvent(
    narrativeEvent: NarrativeEvent | null,
    decodeVarToJs: (value: Var) => unknown,
    decodeVarToString: (value: Var) => string | null,
): ParsedNarrativeEvent | null {
    const parsed = parseNarrativeValue(narrativeEvent, decodeVarToJs, decodeVarToString);
    if (!parsed) return null;
    switch (parsed.kind) {
        case "notify":
            return { eventType: "NotifyEvent", event: { value: parsed.content, contentType: parsed.contentType } };
        case "present":
            return {
                eventType: "PresentEvent",
                event: {
                    presentation: {
                        id: parsed.presentData.id,
                        target: parsed.presentData.target,
                        content: parsed.presentData.content,
                        contentType: parsed.presentData.content_type,
                        attributes: parsed.presentData.attributes.map(([key, value]) => [key, value]),
                    },
                },
            };
        case "unpresent":
            return { eventType: "UnpresentEvent", event: { presentationId: parsed.presentationId } };
        case "traceback":
            return { eventType: "TracebackEvent", event: { error: parsed.error, backtrace: parsed.backtrace } };
        case "data":
            return {
                eventType: "DataEvent",
                event: { namespace: parsed.namespace, kind: parsed.eventKind, payload: parsed.payload },
            };
    }
}
