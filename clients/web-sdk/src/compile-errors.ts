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

import type { CompileContext } from "@moor/schema/generated/moor-common/compile-context";
import type { CompileError } from "@moor/schema/generated/moor-common/compile-error";
import { CompileErrorUnion, unionToCompileErrorUnion } from "@moor/schema/generated/moor-common/compile-error-union";
import type { ParseError } from "@moor/schema/generated/moor-common/parse-error";

/** A compile error as text, with the position it applies to when the compiler gave one. */
export interface CompileErrorDescription {
    message: string;
    line?: number;
    column?: number;
}

type Detail = {
    context?: () => CompileContext | null;
    errorPosition?: () => CompileContext | null;
    message?: () => string | null;
    name?: () => string | null;
    label?: () => string | null;
    feature?: () => string | null;
    slot?: () => string | null;
    literal?: () => string | null;
    varName?: () => { value(): string | null } | null;
};

/** Describe any compile error, as the server's own messages do. */
export function describeCompileError(error: CompileError): CompileErrorDescription {
    const type = error.errorType();
    const detail = unionToCompileErrorUnion(type, obj => error.error(obj)) as Detail | null;
    if (!detail) return { message: "Compilation error" };
    const variable = detail.varName?.()?.value() ?? "?";
    const text = (field: "message" | "name" | "label" | "feature" | "slot" | "literal") => detail[field]?.() ?? "?";
    let message: string;
    switch (type) {
        case CompileErrorUnion.StringLexError:
            message = `Failure to parse string: ${text("message")}`;
            break;
        case CompileErrorUnion.ParseError:
            message = (detail as unknown as ParseError).message() ?? "Parse error";
            break;
        case CompileErrorUnion.UnknownBuiltinFunction:
            message = `Unknown built-in function: ${text("name")}`;
            break;
        case CompileErrorUnion.UnknownTypeConstant:
            message = `Unknown type constant: ${text("name")}`;
            break;
        case CompileErrorUnion.UnknownLoopLabel:
            message = `Could not find loop with id: ${text("label")}`;
            break;
        case CompileErrorUnion.DuplicateVariable:
            message = `Duplicate variable in scope: ${variable}`;
            break;
        case CompileErrorUnion.AssignToConst:
            message = `Cannot assign to const: ${variable}`;
            break;
        case CompileErrorUnion.DisabledFeature:
            message = `Disabled feature: ${text("feature")}`;
            break;
        case CompileErrorUnion.BadSlotName:
            message = `Bad slot name on flyweight: ${text("slot")}`;
            break;
        case CompileErrorUnion.InvalidAssignment:
            message = "Invalid l-value for assignment";
            break;
        case CompileErrorUnion.InvalidTypeLiteralAssignment:
            message = `Cannot assign to type constant literal \`${text("literal")}\``;
            break;
        case CompileErrorUnion.AssignmentToCapturedVariable:
            message = `Cannot assign to captured variable \`${variable}\`; lambdas capture by value`;
            break;
        default:
            message = `Compilation error (${CompileErrorUnion[type] ?? type})`;
    }
    const position = detail.errorPosition?.() ?? detail.context?.() ?? null;
    return position
        ? { message, line: Number(position.line()), column: Number(position.col()) }
        : { message };
}

/** A compile error on one line: "Line 2, column 47: Duplicate variable in scope: b". */
export function formatCompileError(error: CompileError): string {
    return formatCompileErrorDescription(describeCompileError(error));
}

export function formatCompileErrorDescription({ message, line, column }: CompileErrorDescription): string {
    return line === undefined ? message : `Line ${line}, column ${column}: ${message}`;
}

type JsonCompileContext = { line_col?: [number, number] };

function jsonPosition(value: unknown): { line: number; column: number } | null {
    const lineCol = (value as JsonCompileContext | null)?.line_col;
    return Array.isArray(lineCol) && lineCol.length === 2 ? { line: lineCol[0], column: lineCol[1] } : null;
}

/**
 * Describe a compile error as the web host serializes it in JSON: serde's external tagging of
 * the Rust `CompileError`, e.g. `{"DuplicateVariable": [{"line_col": [2, 47]}, "b"]}`.
 */
export function describeCompileErrorJson(error: unknown): CompileErrorDescription {
    if (!error || typeof error !== "object") return { message: "Compilation error" };
    const [type, detail] = Object.entries(error)[0] ?? [];
    const fields: unknown[] = Array.isArray(detail) ? detail : [detail];
    const text = (index: number) => typeof fields[index] === "string" ? fields[index] as string : "?";
    let message: string;
    let position = jsonPosition(fields[0]);
    switch (type) {
        case "StringLexError":
            message = `Failure to parse string: ${text(1)}`;
            break;
        case "ParseError": {
            const parse = detail as { error_position?: unknown; message?: unknown } | null;
            message = typeof parse?.message === "string" ? parse.message : "Parse error";
            position = jsonPosition(parse?.error_position);
            break;
        }
        case "UnknownBuiltinFunction":
            message = `Unknown built-in function: ${text(1)}`;
            break;
        case "UnknownTypeConstant":
            message = `Unknown type constant: ${text(1)}`;
            break;
        case "UnknownLoopLabel":
            message = `Could not find loop with id: ${text(1)}`;
            break;
        case "DuplicateVariable":
            message = `Duplicate variable in scope: ${text(1)}`;
            break;
        case "AssignToConst":
            message = `Cannot assign to const: ${text(1)}`;
            break;
        case "DisabledFeature":
            message = `Disabled feature: ${text(1)}`;
            break;
        case "BadSlotName":
            message = `Bad slot name on flyweight: ${text(1)}`;
            break;
        case "InvalidAssignmentTarget":
            message = "Invalid l-value for assignment";
            break;
        case "InvalidTypeLiteralAssignment":
            message = `Cannot assign to type constant literal \`${text(0)}\``;
            position = jsonPosition(fields[1]);
            break;
        case "AssignmentToCapturedVariable":
            message = `Cannot assign to captured variable \`${text(1)}\`; lambdas capture by value`;
            break;
        default:
            message = `Compilation error (${type ?? "unknown"})`;
    }
    return position ? { message, ...position } : { message };
}

/**
 * The compile error in a web host error body (HTTP 422, `"code": "compilation_error"`): code
 * that does not compile, so no task ran. Null for any other body.
 */
export function compilationFailureFromBody(body: unknown): CompileErrorDescription | null {
    if (!body || typeof body !== "object") return null;
    const { code, compile_error } = body as { code?: unknown; compile_error?: unknown };
    return code === "compilation_error" ? describeCompileErrorJson(compile_error) : null;
}
