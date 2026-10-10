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

import { buildStructuredArgs, SemanticAnnotation, StructuredArgument } from "@moor/web-sdk";
import { invokeVerbFlatBuffer } from "./rpc-fb";

export type ChangeTarget = Extract<SemanticAnnotation, { kind: "change" }>;
export const changeLabels = {
    conflict: "Conflicts",
    upstream: "Upstream edits",
    local: "Local edits",
    converged: "Already match",
    unbased: "Without a baseline",
    unchanged: "Unchanged",
    local_only: "Local only",
    incoming_only: "Upstream only",
} as const;
export type Classification = keyof typeof changeLabels;
export type Choice = "incoming" | "local" | "edited" | "defer" | "unresolved";
export interface ChangeRow {
    id: string;
    label: string;
    objectKey: string;
    objectLabel: string;
    memberLabel: string;
    classification: Classification;
    eligible: boolean;
    blockers: string[];
    choices: Choice[];
    default: Choice;
    choice?: { choice: Choice; program?: string; validated?: boolean };
    base?: string;
    live: string;
    incoming: string;
    live_text?: string;
    incoming_text?: string;
    base_text?: string;
    read_only?: boolean;
    field?: string;
    live_present?: boolean;
    incoming_present?: boolean;
    inspection_error?: string;
}
export interface ReviewPage {
    generation: number;
    rows: ChangeRow[];
    cursor: number[];
    counts: Partial<Record<Classification, number>>;
    decision_counts: { selected: number; unresolved: number; blocked: number };
    operation: "update" | "adopt";
}
export interface ReviewStatus {
    generation: number;
    package: string;
    status: string;
    error?: { message?: string };
}
export interface InspectionPage {
    revision: string;
    rows: ChangeRow[];
    counts: Partial<Record<Classification, number>>;
    next: number;
}

function object(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid change review response.");
    return value as Record<string, unknown>;
}
function number(value: unknown): number {
    if (!Number.isSafeInteger(value) || (value as number) < 0) throw new Error("Invalid change review number.");
    return value as number;
}
function text(value: unknown): string {
    if (typeof value !== "string") throw new Error("Invalid change review text.");
    return value;
}
function choice(value: unknown): Choice {
    if (!["incoming", "local", "edited", "defer", "unresolved"].includes(value as string)) {
        throw new Error("Invalid review choice.");
    }
    return value as Choice;
}
export function decodeChangeRow(value: unknown, details = false): ChangeRow {
    const row = object(value);
    const classification = text(row.classification);
    if (!Object.hasOwn(changeLabels, classification) || !Array.isArray(row.choices) || !Array.isArray(row.blockers)) {
        throw new Error("Invalid change review row.");
    }
    const label = text(row.label);
    const field = typeof row.field === "string" ? row.field : "program";
    const separator = field === "program" ? ":" : ".";
    const member = field === "object" ? "" : typeof row.name === "string"
        ? field === "program" ? row.name.replace(/^\d+:/, "") : row.name
        : field === "program" && Array.isArray(row.names) && row.names.length
        ? text(row.names[0])
        : label.slice(label.lastIndexOf(separator) + 1);
    const objectLabel = member && label.endsWith(separator + member)
        ? label.slice(0, -(member.length + 1))
        : label;
    const saved = object(row.choice ?? {});
    return {
        read_only: row.read_only === true || row.read_only === 1,
        field,
        objectKey: row.object ? JSON.stringify(row.object) : objectLabel,
        objectLabel,
        memberLabel: member ? separator + member : objectLabel,
        live_present: row.live_present !== false && row.live_present !== 0,
        incoming_present: row.incoming_present !== false && row.incoming_present !== 0,
        inspection_error: typeof row.inspection_error === "string" ? row.inspection_error : undefined,
        id: text(row.id),
        label,
        classification: classification as Classification,
        eligible: row.eligible === true || row.eligible === 1,
        default: choice(row.default),
        choices: row.choices.map(choice),
        blockers: row.blockers.map(text),
        ...(saved.choice
            ? {
                choice: {
                    choice: choice(saved.choice),
                    validated: saved.validated === true,
                    ...(typeof saved.program === "string" ? { program: saved.program } : {}),
                },
            }
            : {}),
        base: typeof row.base === "string" ? row.base : undefined,
        live: text(row.live),
        incoming: text(row.incoming),
        ...(details ? { live_text: text(row.live_text), incoming_text: text(row.incoming_text) } : {}),
        ...(row.base_text_available === true && typeof row.base_text === "string" ? { base_text: row.base_text } : {}),
    };
}

/** A matching content hash gives us the accepted source without storing another copy. */
export function baselineText(row: ChangeRow): string | undefined {
    if (row.base_text !== undefined) return row.base_text;
    if (!row.base) return undefined;
    if (row.base === row.live) return row.live_text;
    if (row.base === row.incoming) return row.incoming_text;
    return undefined;
}

export class ChangeReviewClient {
    constructor(private token: string, private target: ChangeTarget) {}

    private async invoke(
        method: "status" | "review" | "details" | "inspection" | "resolve" | "apply",
        args: StructuredArgument[],
    ) {
        const { result } = await invokeVerbFlatBuffer(
            this.token,
            this.target.provider,
            method,
            buildStructuredArgs(args),
        );
        const response = object(result);
        if (response.schema !== 1 || response.review_id !== this.target.review) {
            throw new Error("Unexpected change review response.");
        }
        return response;
    }
    async status(): Promise<ReviewStatus> {
        const status = await this.invoke("status", [this.target.review]);
        return {
            generation: number(status.generation),
            package: text(status.package),
            status: text(status.status),
            ...(status.error && object(status.error).message
                ? { error: { message: text(object(status.error).message) } }
                : {}),
        };
    }
    async page(generation: number, cursor: number[] = [], classification = ""): Promise<ReviewPage> {
        const page = await this.invoke("review", [this.target.review, generation, cursor, classification]);
        if (page.generation !== generation || !Array.isArray(page.rows) || !Array.isArray(page.cursor)) {
            throw new Error("Review changed. Reload it before continuing.");
        }
        const cursorValues = page.cursor.map(number);
        if (
            cursorValues.length
            && (cursorValues.length !== 3 || cursorValues[0] !== this.target.review || cursorValues[1] !== generation)
        ) {
            throw new Error("Invalid review cursor.");
        }
        const rawCounts = object(page.counts);
        const counts = Object.fromEntries(Object.keys(changeLabels).map(key => [key, number(rawCounts[key] ?? 0)]));
        const decisions = object(page.decision_counts);
        return {
            generation,
            rows: page.rows.map(row => decodeChangeRow(row)),
            cursor: cursorValues,
            counts,
            decision_counts: {
                selected: number(decisions.selected),
                unresolved: number(decisions.unresolved),
                blocked: number(decisions.blocked),
            },
            operation: page.operation === "adopt" ? "adopt" : "update",
        };
    }
    async details(generation: number, row: string): Promise<ChangeRow> {
        const result = await this.invoke("details", [this.target.review, generation, row]);
        const detail = decodeChangeRow(result.row, true);
        if (result.generation !== generation || detail.id !== row) {
            throw new Error("Review changed. Reload it before continuing.");
        }
        return detail;
    }
    async inspection(generation: number, offset = 1, classification = "", revision = ""): Promise<InspectionPage> {
        const result = await this.invoke("inspection", [
            this.target.review,
            generation,
            offset,
            classification,
            "",
            revision,
        ]);
        if (result.generation !== generation || !Array.isArray(result.rows)) {
            throw new Error("Review changed. Reload it before continuing.");
        }
        const counts = object(result.counts);
        return {
            revision: text(result.revision),
            rows: result.rows.map(row => decodeChangeRow(row)),
            counts: Object.fromEntries(Object.entries(counts).map(([key, value]) => [key, number(value)])),
            next: number(result.next),
        };
    }
    async resolve(generation: number, row: string, selected: Choice, program = "") {
        const result = await this.invoke("resolve", [this.target.review, generation, row, selected, program]);
        const next = number(result.generation);
        if (next !== generation + 1 || !Array.isArray(result.validation)) {
            throw new Error("Unexpected choice response. Reload the review.");
        }
        const errors = result.validation.map(object).filter(item => item.id === row && item.valid === false)
            .map(item => `Line ${number(item.line ?? 1)}: ${text(item.message)}`);
        return { generation: next, errors };
    }
    async apply(generation: number): Promise<ReviewStatus> {
        await this.invoke("apply", [this.target.review, generation]);
        return this.status();
    }
}
