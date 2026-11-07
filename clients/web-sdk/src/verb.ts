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

import type { CompileError } from "@moor/schema/generated/moor-common/compile-error";
import type { Exception } from "@moor/schema/generated/moor-common/exception";
import { AbortReason } from "@moor/schema/generated/moor-rpc/abort-reason";
import { AbortedException } from "@moor/schema/generated/moor-rpc/aborted-exception";
import { InvocationResponse } from "@moor/schema/generated/moor-rpc/invocation-response";
import { Kept } from "@moor/schema/generated/moor-rpc/kept";
import { TaskAborted } from "@moor/schema/generated/moor-rpc/task-aborted";
import { TaskCompleted } from "@moor/schema/generated/moor-rpc/task-completed";
import { TaskEnding } from "@moor/schema/generated/moor-rpc/task-ending";
import { TaskOutcome } from "@moor/schema/generated/moor-rpc/task-outcome";
import { VerbCompilationError } from "@moor/schema/generated/moor-rpc/verb-compilation-error";
import {
    unionToVerbProgramErrorUnion,
    VerbProgramErrorUnion,
} from "@moor/schema/generated/moor-rpc/verb-program-error-union";
import { VerbProgramFailure } from "@moor/schema/generated/moor-rpc/verb-program-failure";
import { VerbProgramResponseReply } from "@moor/schema/generated/moor-rpc/verb-program-response-reply";
import {
    unionToVerbProgramResponseUnion,
    VerbProgramResponseUnion,
} from "@moor/schema/generated/moor-rpc/verb-program-response-union";
import { VerbProgramSuccess } from "@moor/schema/generated/moor-rpc/verb-program-success";
import * as flatbuffers from "flatbuffers";

function replyTypeName(value: unknown): string {
    return value?.constructor?.name ?? typeof value;
}

export function parseVerbCallOutcomeFromBytes(bytes: Uint8Array, context: string): TaskOutcome {
    return parseVerbCallOutcomeFromResponse(parseVerbCallResponseFromBytes(bytes), context);
}

export function parseVerbCallResponseFromBytes(bytes: Uint8Array): InvocationResponse {
    return InvocationResponse.getRootAsInvocationResponse(new flatbuffers.ByteBuffer(bytes));
}

export function parseVerbCallOutcomeFromReply(replyUnion: unknown, context: string): TaskOutcome {
    return parseVerbCallOutcomeFromResponse(parseVerbCallResponseFromReply(replyUnion, context), context);
}

export function parseVerbCallResponseFromReply(replyUnion: unknown, context: string): InvocationResponse {
    if (!(replyUnion instanceof InvocationResponse)) {
        throw new Error(`${context}: unexpected reply type ${replyTypeName(replyUnion)}`);
    }
    return replyUnion;
}

/** The reason an aborted task ended, or null when the task did not abort. */
export function taskOutcomeAbortReason(outcome: TaskOutcome): TaskAborted | null {
    if (outcome.endingType() !== TaskEnding.TaskAborted) {
        return null;
    }
    return outcome.ending(new TaskAborted()) as TaskAborted | null;
}

/** The uncaught exception that aborted the task, when one did. */
export function taskOutcomeException(outcome: TaskOutcome): Exception | null {
    const aborted = taskOutcomeAbortReason(outcome);
    if (aborted?.reasonType() !== AbortReason.AbortedException) {
        return null;
    }
    const reason = aborted.reason(new AbortedException()) as AbortedException | null;
    return reason?.exception() ?? null;
}

export interface ParsedVerbCallSuccess {
    response: InvocationResponse;
    success: TaskCompleted;
}

/** A verb call whose task did not complete. `kept` says whether its changes were committed. */
export class VerbCallFailure extends Error {
    constructor(
        message: string,
        readonly response: InvocationResponse,
        readonly outcome: TaskOutcome,
    ) {
        super(message);
        this.name = "VerbCallFailure";
    }

    get kept(): Kept {
        return this.outcome.kept();
    }

    /** The uncaught exception that aborted the task, when one did. */
    exception(): Exception | null {
        return taskOutcomeException(this.outcome);
    }
}

export function parseVerbCallSuccessFromBytes(
    bytes: Uint8Array,
    context: string,
): ParsedVerbCallSuccess {
    const response = parseVerbCallResponseFromBytes(bytes);
    return ensureVerbCallSuccess(response, parseVerbCallOutcomeFromResponse(response, context), context);
}

export function parseVerbCallSuccessFromReply(
    replyUnion: unknown,
    context: string,
): ParsedVerbCallSuccess {
    const response = parseVerbCallResponseFromReply(replyUnion, context);
    return ensureVerbCallSuccess(response, parseVerbCallOutcomeFromResponse(response, context), context);
}

function parseVerbCallOutcomeFromResponse(
    verbCallResponse: InvocationResponse,
    context: string,
): TaskOutcome {
    const outcome = verbCallResponse.outcome();
    if (!outcome) {
        throw new Error(`${context}: failed to parse verb call response`);
    }
    return outcome;
}

function ensureVerbCallSuccess(
    response: InvocationResponse,
    outcome: TaskOutcome,
    context: string,
): ParsedVerbCallSuccess {
    const endingType = outcome.endingType();
    if (endingType === TaskEnding.TaskCompleted) {
        const success = outcome.ending(new TaskCompleted()) as TaskCompleted | null;
        if (success) {
            return { response, success };
        }
    }
    const aborted = taskOutcomeAbortReason(outcome);
    const ending = aborted ? AbortReason[aborted.reasonType()] : TaskEnding[endingType];
    throw new VerbCallFailure(`${context}: ${ending ?? "unknown error"}`, response, outcome);
}

export function parseVerbProgramUnionFromReply(
    replyUnion: unknown,
    context: string,
): VerbProgramSuccess | VerbProgramFailure {
    if (!(replyUnion instanceof VerbProgramResponseReply)) {
        throw new Error(`${context}: unexpected reply type ${replyTypeName(replyUnion)}`);
    }

    const response = replyUnion.response();
    if (!response) {
        throw new Error(`${context}: missing verb program response`);
    }

    const responseType = response.responseType();
    const responseUnion = unionToVerbProgramResponseUnion(
        responseType,
        (obj) => response.response(obj),
    );
    if (!responseUnion) {
        throw new Error(`${context}: failed to parse verb program response union`);
    }
    if (!(responseUnion instanceof VerbProgramSuccess) && !(responseUnion instanceof VerbProgramFailure)) {
        throw new Error(`${context}: unexpected verb program response type ${responseType}`);
    }

    return responseUnion;
}

export type VerbProgramCompileOutcome =
    | { success: true }
    | {
        success: false;
        error: {
            type: VerbProgramErrorUnion | null;
            message: string;
            compileError?: CompileError;
        };
    };

export function parseVerbProgramCompileOutcome(
    replyUnion: unknown,
    context: string,
): VerbProgramCompileOutcome {
    const responseUnion = parseVerbProgramUnionFromReply(replyUnion, context);
    if (responseUnion instanceof VerbProgramSuccess) {
        return { success: true };
    }

    const programError = responseUnion.error();
    if (!programError) {
        return { success: false, error: { type: null, message: "Compilation failed" } };
    }

    const errorType = programError.errorType();
    switch (errorType) {
        case VerbProgramErrorUnion.VerbCompilationError: {
            const compError = unionToVerbProgramErrorUnion(
                errorType,
                (obj) => programError.error(obj),
            ) as VerbCompilationError | null;
            const compileError = compError?.error() ?? undefined;
            return {
                success: false,
                error: {
                    type: errorType,
                    message: compileError ? "Compilation error" : "Compilation failed",
                    compileError,
                },
            };
        }
        case VerbProgramErrorUnion.NoVerbToProgram:
            return { success: false, error: { type: errorType, message: "No verb to program" } };
        case VerbProgramErrorUnion.VerbPermissionDenied:
            return { success: false, error: { type: errorType, message: "Permission denied" } };
        case VerbProgramErrorUnion.VerbDatabaseError:
            return { success: false, error: { type: errorType, message: "Database error" } };
        default:
            return { success: false, error: { type: errorType, message: "Unknown compilation error" } };
    }
}
