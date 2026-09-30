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

import { describe, expect, it } from "vitest";
import type { NarrativeMessage } from "../components/Narrative";
import { canGroupMessages, createTranscript } from "./transcript";

const message = (id: string, options: Partial<NarrativeMessage> = {}): NarrativeMessage => ({
    id,
    content: id,
    type: "narrative",
    isHistorical: true,
    ...options,
});
const inset = (id: string, options: Partial<NarrativeMessage> = {}) =>
    message(id, {
        presentationHint: "inset",
        groupId: "room",
        eventMetadata: { verb: "look", lookRoom: { oid: 1 } },
        ...options,
    });

describe("indexed transcript", () => {
    it("preserves existing groups and their positions across append and prepend", () => {
        const transcript = createTranscript();
        transcript.replace([message("b"), message("c")]);
        const original = transcript.group(0);
        transcript.append(message("d", { isHistorical: false }));
        transcript.prepend([message("a")]);
        expect(transcript.group(0)).toBe(original);
        expect(transcript.groupPosition("b")).toBe(0);
        expect(transcript.first).toBe(-1);
        expect(transcript.allMessages().map(m => m.id)).toEqual(["a", "b", "c", "d"]);
        expect(transcript.liveMessages().map(m => m.id)).toEqual(["d"]);
    });

    it("joins groups across page boundaries without changing the mounted head identity", () => {
        const transcript = createTranscript();
        transcript.replace([inset("middle"), message("after")]);
        transcript.prepend([message("before"), inset("oldest"), inset("older")]);
        expect(transcript.group(0)?.id).toBe("middle");
        expect(transcript.group(0)?.messages.map(m => m.id)).toEqual(["oldest", "older", "middle"]);
        expect(transcript.latestRoomLook("oid:1")).toBe("middle");
        expect(transcript.get("older")?.content).toBe("older");
    });

    it("keeps no-newline groups, speaker identity and collapse titles intact", () => {
        expect(canGroupMessages(message("a", { noNewline: true }), message("b"))).toBe(true);
        const speaker = (oid: number, collapseTitle = "Room") =>
            inset("a", { eventMetadata: { actor: { oid }, collapseTitle } });
        expect(canGroupMessages(speaker(1), speaker(1))).toBe(true);
        expect(canGroupMessages(speaker(1), speaker(2))).toBe(false);
        expect(canGroupMessages(speaker(1), speaker(1, "Help"))).toBe(false);
        expect(
            canGroupMessages(
                speaker(1),
                inset("b", { eventMetadata: { actor: { uuid: "1" }, collapseTitle: "Room" } }),
            ),
        ).toBe(false);
    });

    it("indexes the newest room look from a prepended page", () => {
        const transcript = createTranscript();
        transcript.append(message("tail"));
        transcript.prepend([inset("old"), inset("new")]);
        expect(transcript.latestRoomLook("oid:1")).toBe("new");
        transcript.append(inset("live", { isHistorical: false }));
        transcript.prepend([inset("earliest")]);
        expect(transcript.latestRoomLook("oid:1")).toBe("live");
    });

    it("updates hidden messages and rebuilds only when grouping or room identity changes", () => {
        const transcript = createTranscript();
        transcript.replace([message("a"), message("b"), message("c")]);
        const untouched = transcript.group(2);
        transcript.update("a", current => ({ ...current, content: "rewritten" }));
        expect(transcript.group(2)).toBe(untouched);
        expect(transcript.get("a")?.content).toBe("rewritten");
        transcript.update("a", current => ({ ...current, noNewline: true }));
        expect(transcript.end - transcript.first).toBe(2);
        expect(transcript.group(0)?.messages.map(m => m.id)).toEqual(["a", "b"]);
        transcript.update("a", current => ({ ...current, noNewline: false }));
        expect(transcript.end - transcript.first).toBe(3);
    });

    it("marks previous live looks stale without revisiting historical messages", () => {
        const transcript = createTranscript();
        transcript.replace([inset("history")]);
        transcript.append(inset("first", { isHistorical: false }));
        transcript.append(inset("second", { isHistorical: false }));
        expect([...transcript.stale]).toEqual(["first"]);
        expect(transcript.liveMessages().map(m => m.id)).toEqual(["first", "second"]);
    });

    it("bounds announcements without discarding retained history and ignores duplicate ids", () => {
        const transcript = createTranscript();
        for (let i = 0; i < 1000; i++) transcript.append(message(String(i), { isHistorical: false }));
        transcript.append(message("999", { isHistorical: false }));
        transcript.prepend([message("older"), message("older"), message("0")]);
        expect(transcript.size).toBe(1001);
        expect(transcript.liveRevision).toBe(1000);
        expect(transcript.announcementsAfter(0)).toHaveLength(200);
        expect(transcript.announcementsAfter(998).map(m => m.id)).toEqual(["998", "999"]);
        expect(transcript.liveMessages()).toHaveLength(1000);
        transcript.replace([]);
        expect(transcript.announcementsAfter(0)).toEqual([]);
        expect(transcript.size).toBe(0);
        expect(transcript.liveMessages()).toEqual([]);
    });
});
