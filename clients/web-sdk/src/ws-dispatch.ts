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

import { ClientEventUnion } from "@moor/schema/generated/moor-rpc/client-event-union";
import { CredentialsUpdatedEvent } from "@moor/schema/generated/moor-rpc/credentials-updated-event";
import { NarrativeEventMessage } from "@moor/schema/generated/moor-rpc/narrative-event-message";
import { PlayerSwitchedEvent } from "@moor/schema/generated/moor-rpc/player-switched-event";
import { RequestInputEvent } from "@moor/schema/generated/moor-rpc/request-input-event";
import { SystemMessageEvent } from "@moor/schema/generated/moor-rpc/system-message-event";
import { TaskOutcomeEvent } from "@moor/schema/generated/moor-rpc/task-outcome-event";

import { parseClientEvent } from "./client-event.js";

export interface WsDispatchHandlers {
    onNarrativeEventMessage?: (narrative: NarrativeEventMessage) => void;
    onSystemMessageEvent?: (sysMsg: SystemMessageEvent) => void;
    onRequestInputEvent?: (requestInput: RequestInputEvent) => void;
    onTaskOutcomeEvent?: (taskOutcome: TaskOutcomeEvent) => void;
    onCredentialsUpdatedEvent?: (credentials: CredentialsUpdatedEvent) => void;
    onPlayerSwitchedEvent?: (playerSwitched: PlayerSwitchedEvent) => void;
    onIgnoredEvent?: (eventType: ClientEventUnion) => void;
    onUnknownEvent?: (eventType: ClientEventUnion) => void;
    onMalformedEvent?: (eventType: ClientEventUnion, expected: string) => void;
}

export function dispatchClientEvent(bytes: Uint8Array, handlers: WsDispatchHandlers): void {
    const { eventType, eventUnion } = parseClientEvent(bytes);

    switch (eventType) {
        case ClientEventUnion.NarrativeEventMessage: {
            if (!(eventUnion instanceof NarrativeEventMessage)) {
                handlers.onMalformedEvent?.(eventType, "NarrativeEventMessage");
                return;
            }
            handlers.onNarrativeEventMessage?.(eventUnion);
            return;
        }
        case ClientEventUnion.SystemMessageEvent: {
            if (!(eventUnion instanceof SystemMessageEvent)) {
                handlers.onMalformedEvent?.(eventType, "SystemMessageEvent");
                return;
            }
            handlers.onSystemMessageEvent?.(eventUnion);
            return;
        }
        case ClientEventUnion.RequestInputEvent: {
            if (!(eventUnion instanceof RequestInputEvent)) {
                handlers.onMalformedEvent?.(eventType, "RequestInputEvent");
                return;
            }
            handlers.onRequestInputEvent?.(eventUnion);
            return;
        }
        case ClientEventUnion.TaskOutcomeEvent: {
            if (!(eventUnion instanceof TaskOutcomeEvent)) {
                handlers.onMalformedEvent?.(eventType, "TaskOutcomeEvent");
                return;
            }
            handlers.onTaskOutcomeEvent?.(eventUnion);
            return;
        }
        case ClientEventUnion.CredentialsUpdatedEvent: {
            if (!(eventUnion instanceof CredentialsUpdatedEvent)) {
                handlers.onMalformedEvent?.(eventType, "CredentialsUpdatedEvent");
                return;
            }
            handlers.onCredentialsUpdatedEvent?.(eventUnion);
            return;
        }
        case ClientEventUnion.PlayerSwitchedEvent: {
            if (!(eventUnion instanceof PlayerSwitchedEvent)) {
                handlers.onMalformedEvent?.(eventType, "PlayerSwitchedEvent");
                return;
            }
            handlers.onPlayerSwitchedEvent?.(eventUnion);
            return;
        }
        case ClientEventUnion.SetConnectionOptionEvent:
        case ClientEventUnion.DisconnectEvent:
            handlers.onIgnoredEvent?.(eventType);
            return;
        default:
            handlers.onUnknownEvent?.(eventType);
            return;
    }
}
