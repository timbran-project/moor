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

import { Event } from "@moor/schema/generated/moor-common/event";
import { EventUnion } from "@moor/schema/generated/moor-common/event-union";
import { NarrativeEvent } from "@moor/schema/generated/moor-common/narrative-event";
import { PresentEvent } from "@moor/schema/generated/moor-common/present-event";
import { Presentation } from "@moor/schema/generated/moor-common/presentation";
import { PresentationAttribute } from "@moor/schema/generated/moor-common/presentation-attribute";
import { Uuid } from "@moor/schema/generated/moor-common/uuid";
import { Var } from "@moor/schema/generated/moor-var/var";
import { VarStr } from "@moor/schema/generated/moor-var/var-str";
import { VarUnion } from "@moor/schema/generated/moor-var/var-union";
import { parseNarrativeEvent } from "@moor/web-sdk";
import { Builder, ByteBuffer } from "flatbuffers";
import { expect, it, vi } from "vitest";

it("decodes a captured panel with its title, target, and HTML intact", () => {
    const builder = new Builder(512);
    const title = PresentationAttribute.createPresentationAttribute(
        builder,
        builder.createString("title"),
        builder.createString("Prototype Box"),
    );
    const attrs = Presentation.createAttributesVector(builder, [title]);
    const panel = Presentation.createPresentation(
        builder,
        builder.createString("exam-#64"),
        builder.createString("text/html"),
        builder.createString("<h3>Prototype Box</h3>"),
        builder.createString("tools"),
        attrs,
    );
    const event = Event.createEvent(builder, EventUnion.PresentEvent, PresentEvent.createPresentEvent(builder, panel));
    const id = Uuid.createUuid(builder, Uuid.createDataVector(builder, new Uint8Array(16)));
    const author = Var.createVar(
        builder,
        VarUnion.VarStr,
        VarStr.createVarStr(builder, builder.createString("author")),
    );
    NarrativeEvent.startNarrativeEvent(builder);
    NarrativeEvent.addEventId(builder, id);
    NarrativeEvent.addAuthor(builder, author);
    NarrativeEvent.addEvent(builder, event);
    builder.finish(NarrativeEvent.endNarrativeEvent(builder));
    expect(
        parseNarrativeEvent(
            NarrativeEvent.getRootAsNarrativeEvent(new ByteBuffer(builder.asUint8Array())),
            vi.fn(),
            vi.fn(),
        ),
    ).toEqual({
        eventType: "PresentEvent",
        event: {
            presentation: {
                id: "exam-#64",
                contentType: "text/html",
                content: "<h3>Prototype Box</h3>",
                target: "tools",
                attributes: [["title", "Prototype Box"]],
            },
        },
    });
});
