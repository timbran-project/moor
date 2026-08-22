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

import { Obj } from "@moor/schema/generated/moor-common/obj";
import { ObjId } from "@moor/schema/generated/moor-common/obj-id";
import { ObjUnion } from "@moor/schema/generated/moor-common/obj-union";
import { AuthToken } from "@moor/schema/generated/moor-rpc/auth-token";
import { ClientEvent } from "@moor/schema/generated/moor-rpc/client-event";
import { ClientEventUnion } from "@moor/schema/generated/moor-rpc/client-event-union";
import { PlayerSwitchedEvent } from "@moor/schema/generated/moor-rpc/player-switched-event";
import * as flatbuffers from "flatbuffers";
import { describe, expect, it } from "vitest";
import { handleClientEventFlatBuffer } from "./rpc-fb-ws";

function playerSwitchedEventBytes(player: number, token: string): Uint8Array {
    const builder = new flatbuffers.Builder(256);
    const tokenString = builder.createString(token);
    const authToken = AuthToken.createAuthToken(builder, tokenString);
    const objId = ObjId.createObjId(builder, player);
    const playerObj = Obj.createObj(builder, ObjUnion.ObjId, objId);

    PlayerSwitchedEvent.startPlayerSwitchedEvent(builder);
    PlayerSwitchedEvent.addNewPlayer(builder, playerObj);
    PlayerSwitchedEvent.addNewAuthToken(builder, authToken);
    const playerSwitched = PlayerSwitchedEvent.endPlayerSwitchedEvent(builder);
    const event = ClientEvent.createClientEvent(
        builder,
        ClientEventUnion.PlayerSwitchedEvent,
        playerSwitched,
    );
    builder.finish(event);
    return builder.asUint8Array();
}

describe("PlayerSwitchedEvent", () => {
    it("dispatches the new player identity and auth token", () => {
        let identity = null;

        handleClientEventFlatBuffer(playerSwitchedEventBytes(42, "new-auth-token"), {
            onPlayerSwitched: (update) => {
                identity = update;
            },
        });

        expect(identity).toEqual({
            playerOid: "oid:42",
            authToken: "new-auth-token",
        });
    });
});
