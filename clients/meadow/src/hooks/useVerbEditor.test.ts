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
import { Symbol as FbSymbol } from "@moor/schema/generated/moor-common/symbol";
import { UuObjId } from "@moor/schema/generated/moor-common/uu-obj-id";
import { VerbInfo } from "@moor/schema/generated/moor-common/verb-info";
import { VerbValue } from "@moor/schema/generated/moor-rpc/verb-value";
import { parseUuObjIdString } from "@moor/web-sdk";
import { act, renderHook } from "@testing-library/react";
import { Builder, ByteBuffer } from "flatbuffers";
import { expect, it, vi } from "vitest";
import { getVerbCodeFlatBuffer } from "../lib/rpc-fb";
import { useVerbEditor } from "./useVerbEditor";

vi.mock("../lib/rpc-fb", () => ({ getVerbCodeFlatBuffer: vi.fn() }));

it.each(["0", "0001F3-A0E78B1030"])("preserves object and owner identifiers for %s", async id => {
    const builder = new Builder(256);
    const isUuid = id.includes("-");
    const objectValue = isUuid
        ? UuObjId.createUuObjId(builder, parseUuObjIdString(id))
        : ObjId.createObjId(builder, Number(id));
    const object = Obj.createObj(builder, isUuid ? ObjUnion.UuObjId : ObjUnion.ObjId, objectValue);
    const name = FbSymbol.createSymbol(builder, builder.createString("smoke"));
    const names = VerbInfo.createNamesVector(builder, [name]);
    const none = FbSymbol.createSymbol(builder, builder.createString("none"));
    const argspec = VerbInfo.createArgSpecVector(builder, [none, none, none]);
    const code = VerbValue.createCodeVector(builder, [builder.createString("return true;")]);
    VerbInfo.startVerbInfo(builder);
    VerbInfo.addLocation(builder, object);
    VerbInfo.addOwner(builder, object);
    VerbInfo.addNames(builder, names);
    VerbInfo.addArgSpec(builder, argspec);
    const info = VerbInfo.endVerbInfo(builder);
    builder.finish(VerbValue.createVerbValue(builder, info, code));
    vi.mocked(getVerbCodeFlatBuffer).mockResolvedValue(
        VerbValue.getRootAsVerbValue(new ByteBuffer(builder.asUint8Array())),
    );

    const { result } = renderHook(() => useVerbEditor());
    const curie = `${isUuid ? "uuid" : "oid"}:${id}`;
    await act(() => result.current.launchVerbEditor("smoke", curie, "smoke", "token"));
    expect(result.current.editorSession).toMatchObject({
        objectCurie: curie,
        title: `smoke on #${id}`,
        verbMetadata: { location: id, owner: id },
    });
});
