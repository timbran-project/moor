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

import { AnnotationTable, decodeAnnotation } from "@moor/web-sdk";

/** Ranges use textarea UTF-16 offsets. Only explicit selections create bindings. */
export interface CommandBinding {
    start: number;
    end: number;
    reference: string;
}
export interface CommandDraft {
    text: string;
    bindings: CommandBinding[];
}
export const plainDraft = (text: string): CommandDraft => ({ text, bindings: [] });

/** Edits outside a binding shift it; touching its label releases it into ordinary text. */
export function editDraft(draft: CommandDraft, text: string): CommandDraft {
    let start = 0;
    while (start < draft.text.length && start < text.length && draft.text[start] === text[start]) start++;
    let oldEnd = draft.text.length;
    let newEnd = text.length;
    while (oldEnd > start && newEnd > start && draft.text[oldEnd - 1] === text[newEnd - 1]) {
        oldEnd--;
        newEnd--;
    }
    return {
        text,
        bindings: draft.bindings.flatMap(binding => {
            if (binding.end <= start) return [binding];
            if (binding.start >= oldEnd) {
                return [{ ...binding, start: binding.start + newEnd - oldEnd, end: binding.end + newEnd - oldEnd }];
            }
            return [];
        }),
    };
}

export function replaceArgument(
    draft: CommandDraft,
    start: number,
    end: number,
    label: string,
    reference: string,
): CommandDraft {
    const text = draft.text.slice(0, start) + label + draft.text.slice(end);
    const delta = label.length - (end - start);
    const bindings = draft.bindings.flatMap(binding => {
        if (binding.end <= start) return [binding];
        if (binding.start >= end) return [{ ...binding, start: binding.start + delta, end: binding.end + delta }];
        return [];
    });
    bindings.push({ start, end: start + label.length, reference });
    return { text, bindings: bindings.sort((a, b) => a.start - b.start) };
}

export function sliceDraft(draft: CommandDraft, start: number, end: number): CommandDraft {
    return {
        text: draft.text.slice(start, end),
        bindings: draft.bindings.filter(binding => binding.start >= start && binding.end <= end)
            .map(binding => ({ ...binding, start: binding.start - start, end: binding.end - start })),
    };
}
export function prefixDraft(draft: CommandDraft, prefix: string): CommandDraft {
    return {
        text: prefix + draft.text,
        bindings: draft.bindings.map(binding => ({
            ...binding,
            start: binding.start + prefix.length,
            end: binding.end + prefix.length,
        })),
    };
}

/** Serialize labels to references while retaining a map back to editor boundaries. */
export function serializeDraft(draft: CommandDraft) {
    let command = "";
    let position = 0;
    const ranges: { display: CommandBinding; start: number; end: number }[] = [];
    for (const binding of draft.bindings) {
        command += draft.text.slice(position, binding.start);
        const start = command.length;
        command += binding.reference.replace(/^(oid|uuid):/, "#");
        ranges.push({ display: binding, start, end: command.length });
        position = binding.end;
    }
    command += draft.text.slice(position);
    const toDisplay = (offset: number) => {
        let shift = 0;
        for (const range of ranges) {
            if (offset < range.start) break;
            if (offset < range.end) return range.display.start;
            shift += (range.display.end - range.display.start) - (range.end - range.start);
        }
        return offset + shift;
    };
    const toWire = (offset: number) => {
        let shift = 0;
        for (const range of ranges) {
            if (offset < range.display.start) break;
            if (offset < range.display.end) return range.start;
            shift += (range.end - range.start) - (range.display.end - range.display.start);
        }
        return offset + shift;
    };
    return { command, toDisplay, toWire };
}

function escapeDjot(value: string) {
    return value.replace(/[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/g, "\\$&");
}
export function draftEcho(draft: CommandDraft): { content: string; annotations: AnnotationTable } {
    let content = "";
    let position = 0;
    const annotations: Record<string, { kind: "object"; ref: string }> = {};
    for (const [index, binding] of draft.bindings.entries()) {
        const id = `b${index}`;
        content += escapeDjot(draft.text.slice(position, binding.start));
        content += `[${escapeDjot(draft.text.slice(binding.start, binding.end))}]{annotation=${id}}`;
        annotations[id] = { kind: "object", ref: binding.reference };
        position = binding.end;
    }
    return { content: content + escapeDjot(draft.text.slice(position)), annotations };
}

export function decodeDraft(value: unknown): CommandDraft | null {
    if (!value || typeof value !== "object") return null;
    const draft = value as CommandDraft;
    if (
        typeof draft.text !== "string" || draft.text.length > 8192 || !Array.isArray(draft.bindings)
        || draft.bindings.length > 256
    ) return null;
    let end = 0;
    for (const binding of draft.bindings) {
        if (
            !binding || !Number.isInteger(binding.start) || !Number.isInteger(binding.end) || binding.start < end
            || binding.end <= binding.start || binding.end > draft.text.length
            || !decodeAnnotation({ kind: "object", ref: binding.reference })
        ) return null;
        end = binding.end;
    }
    return draft;
}
