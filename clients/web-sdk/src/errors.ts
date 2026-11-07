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

import { CompilationError } from "@moor/schema/generated/moor-rpc/compilation-error";
import { Failure } from "@moor/schema/generated/moor-rpc/failure";
import { ReplyResult } from "@moor/schema/generated/moor-rpc/reply-result";
import { unionToReplyResultUnion } from "@moor/schema/generated/moor-rpc/reply-result-union";
import { SchedulerErrorUnion, unionToSchedulerErrorUnion } from "@moor/schema/generated/moor-rpc/scheduler-error-union";

import { formatCompileError } from "./compile-errors.js";

export function extractFailureError(replyResult: ReplyResult, context: string): never {
    const resultType = replyResult.resultType();
    const failure = unionToReplyResultUnion(
        resultType,
        (obj) => replyResult.result(obj),
    ) as Failure | null;

    if (!failure) {
        throw new Error(`${context} failed with unknown error`);
    }

    const rpcError = failure.error();
    if (!rpcError) {
        throw new Error(`${context} failed with unknown error`);
    }

    const rawMessage = rpcError.message() || "Unknown error";
    const schedulerError = rpcError.schedulerError();

    if (schedulerError) {
        const schedulerErrorType = schedulerError.errorType();
        const errorUnion = unionToSchedulerErrorUnion(
            schedulerErrorType,
            (obj) => schedulerError.error(obj),
        );

        if (schedulerErrorType === SchedulerErrorUnion.CompilationError && errorUnion) {
            const compilationError = errorUnion as CompilationError;
            const compileError = compilationError.error();
            if (compileError) {
                throw new Error(`${context} failed: ${formatCompileError(compileError)}`);
            }
        }
    }

    const backtraceMatch = rawMessage.match(/backtrace:\s*\[String\("([^"]+)"\)/);
    if (backtraceMatch && backtraceMatch[1]) {
        const backtraceLine = backtraceMatch[1];
        const errorMatch = backtraceLine.match(/:\s*([EW]_\w+\s*\([^)]+\))/);
        if (errorMatch && errorMatch[1]) {
            throw new Error(`${context} failed: ${errorMatch[1]}`);
        }
        throw new Error(`${context} failed: ${backtraceLine}`);
    }

    const errorTypeMatch = rawMessage.match(/error:\s*([EW]_\w+)/);
    if (errorTypeMatch && errorTypeMatch[1]) {
        throw new Error(`${context} failed: ${errorTypeMatch[1]}`);
    }

    throw new Error(`${context} failed: ${rawMessage}`);
}
