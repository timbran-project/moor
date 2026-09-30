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
//

import { Obj } from "@moor/schema/generated/moor-common/obj";
import { ObjId } from "@moor/schema/generated/moor-common/obj-id";
import { ObjUnion } from "@moor/schema/generated/moor-common/obj-union";
import { Uuid } from "@moor/schema/generated/moor-common/uuid";
import { ClientSuccess } from "@moor/schema/generated/moor-rpc/client-success";
import { DaemonToClientReply } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply";
import { DaemonToClientReplyUnion } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply-union";
import { HistoricalNarrativeEvent } from "@moor/schema/generated/moor-rpc/historical-narrative-event";
import { HistoryResponse } from "@moor/schema/generated/moor-rpc/history-response";
import { HistoryResponseReply } from "@moor/schema/generated/moor-rpc/history-response-reply";
import { ReplyResult } from "@moor/schema/generated/moor-rpc/reply-result";
import { ReplyResultUnion } from "@moor/schema/generated/moor-rpc/reply-result-union";
import { parseEncryptedHistoryEvents, parseEncryptedHistoryPage } from "@moor/web-sdk";
import { Builder } from "flatbuffers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchHistoryFlatBuffer } from "./rpc-fb-history";
import { moorApi } from "./rpc-fb-shared";

function historyResponse(eventCount: number, hasMore: boolean, cursorLength = 16) {
    const b = new Builder(1024);
    const cursor = Uuid.createUuid(b, Uuid.createDataVector(b, new Uint8Array(cursorLength).fill(1)));
    const player = Obj.createObj(b, ObjUnion.ObjId, ObjId.createObjId(b, 7));
    const events = Array.from({ length: eventCount }, () => {
        const blob = HistoricalNarrativeEvent.createEncryptedBlobVector(b, [1, 2, 3]);
        HistoricalNarrativeEvent.startHistoricalNarrativeEvent(b);
        HistoricalNarrativeEvent.addEventId(b, cursor);
        HistoricalNarrativeEvent.addPlayer(b, player);
        HistoricalNarrativeEvent.addEncryptedBlob(b, blob);
        return HistoricalNarrativeEvent.endHistoricalNarrativeEvent(b);
    });
    const vector = HistoryResponse.createEventsVector(b, events);
    HistoryResponse.startHistoryResponse(b);
    HistoryResponse.addEvents(b, vector);
    HistoryResponse.addHasMoreBefore(b, hasMore);
    if (eventCount) HistoryResponse.addEarliestEventId(b, cursor);
    const history = HistoryResponseReply.createHistoryResponseReply(b, HistoryResponse.endHistoryResponse(b));
    const reply = DaemonToClientReply.createDaemonToClientReply(
        b,
        DaemonToClientReplyUnion.HistoryResponseReply,
        history,
    );
    const success = ClientSuccess.createClientSuccess(b, reply);
    b.finish(ReplyResult.createReplyResult(b, ReplyResultUnion.ClientSuccess, success));
    return b.asUint8Array();
}

describe("history pagination metadata", () => {
    afterEach(() => vi.restoreAllMocks());

    it("retains the server cursor and terminal flag when every event fails decryption", async () => {
        const bytes = historyResponse(2, true);
        vi.spyOn(moorApi, "getFlatBuffer").mockResolvedValue(bytes);
        vi.spyOn(console, "error").mockImplementation(() => {});
        const result = await fetchHistoryFlatBuffer("token", "invalid-age-key", 50, undefined, "previous-cursor");
        expect(result).toEqual({
            events: [],
            eventCount: 2,
            hasMoreBefore: true,
            earliestEventId: "01".repeat(16),
        });
        expect(moorApi.getFlatBuffer).toHaveBeenCalledWith(
            "/v1/history?limit=50&until_event=previous-cursor",
            expect.any(Object),
        );
        expect(parseEncryptedHistoryEvents(bytes)).toHaveLength(2);
    });

    it("reads an empty terminal response", () => {
        expect(parseEncryptedHistoryPage(historyResponse(0, false))).toEqual({
            events: [],
            eventCount: 0,
            hasMoreBefore: false,
            earliestEventId: null,
        });
    });

    it("rejects malformed UUID lengths as pagination cursors", () => {
        expect(parseEncryptedHistoryPage(historyResponse(1, true, 3)).earliestEventId).toBeNull();
    });
});
