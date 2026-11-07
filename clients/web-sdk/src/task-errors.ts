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

import { AbortLimit } from "@moor/schema/generated/moor-rpc/abort-limit";
import { AbortLimitReason } from "@moor/schema/generated/moor-rpc/abort-limit-reason";
import { AbortReason } from "@moor/schema/generated/moor-rpc/abort-reason";
import { AbortedCommandFailed } from "@moor/schema/generated/moor-rpc/aborted-command-failed";
import { AbortedLimit } from "@moor/schema/generated/moor-rpc/aborted-limit";
import { CommandError } from "@moor/schema/generated/moor-rpc/command-error";
import { CommandErrorUnion } from "@moor/schema/generated/moor-rpc/command-error-union";
import { CommandExecutionError } from "@moor/schema/generated/moor-rpc/command-execution-error";
import { CompilationError } from "@moor/schema/generated/moor-rpc/compilation-error";
import { SchedulerError } from "@moor/schema/generated/moor-rpc/scheduler-error";
import { SchedulerErrorUnion } from "@moor/schema/generated/moor-rpc/scheduler-error-union";
import { TaskAborted } from "@moor/schema/generated/moor-rpc/task-aborted";
import { TaskEnding } from "@moor/schema/generated/moor-rpc/task-ending";
import { TaskOutcome } from "@moor/schema/generated/moor-rpc/task-outcome";
import { VerbCompilationError } from "@moor/schema/generated/moor-rpc/verb-compilation-error";
import { VerbProgramErrorUnion } from "@moor/schema/generated/moor-rpc/verb-program-error-union";
import { VerbProgramFailed } from "@moor/schema/generated/moor-rpc/verb-program-failed";

import { formatCompileError } from "./compile-errors.js";

export interface SchedulerErrorNarrative {
    message: string;
    description?: string[];
}

function commandErrorMessage(cmdError: CommandError): string | null {
    switch (cmdError.errorType()) {
        case CommandErrorUnion.CouldNotParseCommand:
            return "I don't understand that.";
        case CommandErrorUnion.NoObjectMatch:
            return "I don't see that here.";
        case CommandErrorUnion.NoCommandMatch:
            return "I don't know how to do that.";
        case CommandErrorUnion.PermissionDenied:
            return "You can't do that.";
        default:
            return null;
    }
}

function abortLimitMessage(limit: AbortLimit): string | null {
    switch (limit.reason()) {
        case AbortLimitReason.Ticks:
            return "Task ran out of ticks";
        case AbortLimitReason.Time:
            return "Task ran out of seconds";
        case AbortLimitReason.OutputBytes:
            return "Task produced too much captured output";
        case AbortLimitReason.OutputEvents:
            return "Task produced too many captured output events";
        default:
            return null;
    }
}

function abortReasonMessage(aborted: TaskAborted): string | null {
    switch (aborted.reasonType()) {
        case AbortReason.AbortedLimit: {
            const limit = (aborted.reason(new AbortedLimit()) as AbortedLimit | null)?.limit();
            return limit ? abortLimitMessage(limit) : null;
        }
        case AbortReason.AbortedCommandFailed: {
            const cmdError = (aborted.reason(new AbortedCommandFailed()) as AbortedCommandFailed | null)?.error();
            return cmdError ? commandErrorMessage(cmdError) : null;
        }
        case AbortReason.AbortedDeadline:
            return "Task ran out of seconds";
        case AbortReason.AbortedCancelled:
        case AbortReason.AbortedKilled:
        case AbortReason.AbortedRolledBack:
            return "Task cancelled";
        case AbortReason.AbortedConflictRetriesExhausted:
        case AbortReason.AbortedInternal:
            return "Task aborted";
        // The daemon sends the traceback of an uncaught exception as its own event.
        case AbortReason.AbortedException:
        case AbortReason.AbortedVerbNotFound:
        default:
            return null;
    }
}

/** What to tell the player about how their task ended; null when there is nothing to say. */
export function taskOutcomeToNarrative(outcome: TaskOutcome): SchedulerErrorNarrative | null {
    let message: string | null = null;
    switch (outcome.endingType()) {
        case TaskEnding.TaskAborted: {
            const aborted = outcome.ending(new TaskAborted()) as TaskAborted | null;
            message = aborted ? abortReasonMessage(aborted) : null;
            break;
        }
        case TaskEnding.TaskResultLost:
            message = "Task aborted";
            break;
    }
    return message ? { message } : null;
}

/** What to tell the player about a request the scheduler refused; no task ran. */
export function schedulerErrorToNarrative(schedulerError: SchedulerError): SchedulerErrorNarrative | null {
    const errorType = schedulerError.errorType();
    let message: string | null = null;
    let description: string[] | null = null;

    switch (errorType) {
        case SchedulerErrorUnion.CommandExecutionError: {
            const cmdExecError = schedulerError.error(new CommandExecutionError()) as CommandExecutionError | null;
            if (!cmdExecError) {
                break;
            }
            const cmdError = cmdExecError.error();
            if (cmdError) {
                message = commandErrorMessage(cmdError);
            }
            break;
        }

        case SchedulerErrorUnion.VerbProgramFailed: {
            const verbProgramFailed = schedulerError.error(new VerbProgramFailed()) as VerbProgramFailed | null;
            if (!verbProgramFailed) {
                break;
            }
            const verbError = verbProgramFailed.error();
            if (!verbError) {
                break;
            }

            switch (verbError.errorType()) {
                case VerbProgramErrorUnion.VerbCompilationError: {
                    const compError = verbError.error(new VerbCompilationError()) as VerbCompilationError | null;
                    if (compError) {
                        const ce = compError.error();
                        message = "Verb not programmed.";
                        if (ce) {
                            description = [formatCompileError(ce)];
                        }
                    }
                    break;
                }
                case VerbProgramErrorUnion.NoVerbToProgram:
                    message = "Verb not programmed.";
                    break;
                case VerbProgramErrorUnion.VerbPermissionDenied:
                    message = "Permission denied.";
                    break;
            }
            break;
        }

        case SchedulerErrorUnion.CompilationError: {
            const compilation = schedulerError.error(new CompilationError()) as CompilationError | null;
            const compileError = compilation?.error();
            message = "Compilation failed.";
            if (compileError) {
                description = [formatCompileError(compileError)];
            }
            break;
        }

        default:
            return null;
    }

    if (!message) {
        return null;
    }
    return {
        message,
        description: description ?? undefined,
    };
}
