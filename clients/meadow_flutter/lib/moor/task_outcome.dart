// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/types/moor_err.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

/// Describes how a task ended, for display to the player.
///
/// The texts match the telnet host's.
String describeTaskOutcome(moor_rpc.TaskOutcome outcome) {
  switch (outcome.endingType) {
    case moor_rpc.TaskEndingTypeId.TaskCompleted:
      return 'Task completed';
    case moor_rpc.TaskEndingTypeId.TaskSuspended:
      return 'Task suspended';
    case moor_rpc.TaskEndingTypeId.TaskAborted:
      final aborted = outcome.ending as moor_rpc.TaskAborted?;
      return _describeAbort(aborted);
    default:
      return 'Task aborted';
  }
}

String _describeAbort(moor_rpc.TaskAborted? aborted) {
  final reason = aborted?.reason;
  switch (aborted?.reasonType) {
    case moor_rpc.AbortReasonTypeId.AbortedLimit:
      final limit = (reason as moor_rpc.AbortedLimit?)?.limit;
      return _describeLimit(limit?.reason);
    case moor_rpc.AbortReasonTypeId.AbortedDeadline:
      return 'Task ran out of seconds';
    case moor_rpc.AbortReasonTypeId.AbortedException:
      final exception = (reason as moor_rpc.AbortedException?)?.exception;
      return 'Task exception: ${_describeError(exception?.error)}';
    case moor_rpc.AbortReasonTypeId.AbortedVerbNotFound:
      final notFound = reason as moor_rpc.AbortedVerbNotFound?;
      final where = notFound?.where;
      final whereText = where == null
          ? '?'
          : MoorVar.fromFlatBuffer(where).toLiteral();
      return 'Verb not found: $whereText:${notFound?.what?.value ?? '?'}';
    case moor_rpc.AbortReasonTypeId.AbortedCommandFailed:
      final error = (reason as moor_rpc.AbortedCommandFailed?)?.error;
      return describeCommandError(error);
    case moor_rpc.AbortReasonTypeId.AbortedCancelled:
    case moor_rpc.AbortReasonTypeId.AbortedKilled:
    case moor_rpc.AbortReasonTypeId.AbortedRolledBack:
      return 'Task cancelled';
    default:
      return 'Task aborted';
  }
}

String _describeLimit(moor_rpc.AbortLimitReason? reason) {
  switch (reason) {
    case moor_rpc.AbortLimitReason.Ticks:
      return 'Task ran out of ticks';
    case moor_rpc.AbortLimitReason.Time:
      return 'Task ran out of seconds';
    case moor_rpc.AbortLimitReason.OutputEvents:
      return 'Task produced too many captured output events';
    case moor_rpc.AbortLimitReason.OutputBytes:
      return 'Task produced too much captured output';
    default:
      return 'Task aborted';
  }
}

/// Describes a command that matched nothing, for display to the player.
String describeCommandError(moor_rpc.CommandError? error) {
  switch (error?.errorType) {
    case moor_rpc.CommandErrorUnionTypeId.NoObjectMatch:
      return "I don't see that here.";
    case moor_rpc.CommandErrorUnionTypeId.PermissionDenied:
      return "You can't do that.";
    case moor_rpc.CommandErrorUnionTypeId.CouldNotParseCommand:
    case moor_rpc.CommandErrorUnionTypeId.NoCommandMatch:
      return "I couldn't understand that.";
    default:
      return 'Task aborted';
  }
}

String _describeError(moor_common.Error? error) {
  if (error == null) {
    return 'unknown error';
  }
  final custom = error.errType == moor_common.ErrorCode.ErrCustom
      ? error.customSymbol?.value
      : null;
  final code = custom ?? MoorErr(error.errType).toLiteral();
  final msg = error.msg;
  return msg == null || msg.isEmpty ? code : '$code ($msg)';
}
