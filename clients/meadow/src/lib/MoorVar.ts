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

import { Symbol as FbSymbol } from "@moor/schema/generated/moor-common/symbol";
import { Var as FbVar } from "@moor/schema/generated/moor-var/var";
import { VarBinary } from "@moor/schema/generated/moor-var/var-binary";
import { VarList } from "@moor/schema/generated/moor-var/var-list";
import { VarStr } from "@moor/schema/generated/moor-var/var-str";
import { VarSym } from "@moor/schema/generated/moor-var/var-sym";
import { VarUnion } from "@moor/schema/generated/moor-var/var-union";
import { MoorVar as SharedMoorVar } from "@moor/web-sdk";
import * as flatbuffers from "flatbuffers";

// Meadow-specific extension of the shared protocol-level MoorVar.
// Keeps app/workflow argument builders local while core var decoding lives in @moor/web-sdk.
export class MoorVar extends SharedMoorVar {
    constructor(fb: FbVar) {
        super(fb);
    }

    /**
     * Build a VarList containing [content_type_string, binary_data]
     * Used for file uploads
     */
    static buildFileVar(contentType: string, data: Uint8Array): Uint8Array {
        const builder = new flatbuffers.Builder(data.length + 256);

        const contentTypeStrOffset = builder.createString(contentType);
        const varStrOffset = VarStr.createVarStr(builder, contentTypeStrOffset);
        const contentTypeVarOffset = FbVar.createVar(builder, VarUnion.VarStr, varStrOffset);

        const binaryDataOffset = VarBinary.createDataVector(builder, data);
        const varBinaryOffset = VarBinary.createVarBinary(builder, binaryDataOffset);
        const binaryVarOffset = FbVar.createVar(builder, VarUnion.VarBinary, varBinaryOffset);

        const elementsVectorOffset = VarList.createElementsVector(builder, [contentTypeVarOffset, binaryVarOffset]);
        const varListOffset = VarList.createVarList(builder, elementsVectorOffset);
        const listVarOffset = FbVar.createVar(builder, VarUnion.VarList, varListOffset);

        builder.finish(listVarOffset);
        return builder.asUint8Array();
    }

    /**
     * Build args for text editor save: optional session ID followed by content
     * Content can be a string or list of strings
     */
    static buildTextEditorArgs(sessionId: string | undefined, content: string | string[]): Uint8Array {
        const contentSize = typeof content === "string" ? content.length : content.reduce((a, b) => a + b.length, 0);
        const estimatedSize = 512 + contentSize * 2;
        const builder = new flatbuffers.Builder(estimatedSize);

        let contentVarOffset: number;
        if (typeof content === "string") {
            const contentStrOffset = builder.createString(content);
            const contentVarStrOffset = VarStr.createVarStr(builder, contentStrOffset);
            contentVarOffset = FbVar.createVar(builder, VarUnion.VarStr, contentVarStrOffset);
        } else {
            const contentVarOffsets: number[] = [];
            for (const line of content) {
                const strOffset = builder.createString(line);
                const varStrOffset = VarStr.createVarStr(builder, strOffset);
                const varOffset = FbVar.createVar(builder, VarUnion.VarStr, varStrOffset);
                contentVarOffsets.push(varOffset);
            }
            const contentElementsOffset = VarList.createElementsVector(builder, contentVarOffsets);
            const contentListOffset = VarList.createVarList(builder, contentElementsOffset);
            contentVarOffset = FbVar.createVar(builder, VarUnion.VarList, contentListOffset);
        }

        const outerVarOffsets: number[] = [];
        if (sessionId) {
            const sessionStrOffset = builder.createString(sessionId);
            const sessionVarStrOffset = VarStr.createVarStr(builder, sessionStrOffset);
            const sessionVarOffset = FbVar.createVar(builder, VarUnion.VarStr, sessionVarStrOffset);
            outerVarOffsets.push(sessionVarOffset);
        }
        outerVarOffsets.push(contentVarOffset);

        const outerElementsOffset = VarList.createElementsVector(builder, outerVarOffsets);
        const outerListOffset = VarList.createVarList(builder, outerElementsOffset);
        const outerListVarOffset = FbVar.createVar(builder, VarUnion.VarList, outerListOffset);

        builder.finish(outerListVarOffset);
        return builder.asUint8Array();
    }

    /**
     * Build args for text editor close: optional session ID followed by 'close symbol
     */
    static buildTextEditorCloseArgs(sessionId: string | undefined): Uint8Array {
        const builder = new flatbuffers.Builder(256);

        const closeStrOffset = builder.createString("close");
        const symbolOffset = FbSymbol.createSymbol(builder, closeStrOffset);
        const closeSymOffset = VarSym.createVarSym(builder, symbolOffset);
        const closeVarOffset = FbVar.createVar(builder, VarUnion.VarSym, closeSymOffset);

        const outerVarOffsets: number[] = [];
        if (sessionId) {
            const sessionStrOffset = builder.createString(sessionId);
            const sessionVarStrOffset = VarStr.createVarStr(builder, sessionStrOffset);
            const sessionVarOffset = FbVar.createVar(builder, VarUnion.VarStr, sessionVarStrOffset);
            outerVarOffsets.push(sessionVarOffset);
        }
        outerVarOffsets.push(closeVarOffset);

        const outerElementsOffset = VarList.createElementsVector(builder, outerVarOffsets);
        const outerListOffset = VarList.createVarList(builder, outerElementsOffset);
        const outerListVarOffset = FbVar.createVar(builder, VarUnion.VarList, outerListOffset);

        builder.finish(outerListVarOffset);
        return builder.asUint8Array();
    }
}
