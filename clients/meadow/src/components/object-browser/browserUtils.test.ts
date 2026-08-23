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
import {
    clampFontSize,
    describeObject,
    escapeMooString,
    formatEvalObjectRef,
    formatObjectFlags,
    hasEvalError,
    isMethodVerb,
    isTestVerb,
    listToMooLiteral,
    normalizeObjectInput,
    normalizeObjectRef,
} from "./browserUtils";
import type { ObjectData, VerbData } from "./types";

describe("object-browser shared utilities", () => {
    it("normalizes free-form object input into MOO expressions", () => {
        expect(normalizeObjectInput("123")).toBe("#123");
        expect(normalizeObjectInput("-5")).toBe("#-5");
        expect(normalizeObjectInput("oid:42")).toBe("#42");
        expect(normalizeObjectInput("uuid:abc")).toBe("#abc");
        expect(normalizeObjectInput("$thing")).toBe("$thing");
        expect(normalizeObjectInput("player")).toBe("player");
        expect(normalizeObjectInput("  ")).toBe("");
        expect(normalizeObjectInput("not an obj ref!")).toBe("not an obj ref!");
    });

    it("parses object references into display and id parts", () => {
        expect(normalizeObjectRef("oid:7")).toEqual({ display: "#7", objectId: "7" });
        expect(normalizeObjectRef("-1")).toEqual({ display: "#-1", objectId: null });
        expect(normalizeObjectRef("")).toEqual({ display: "none", objectId: null });
    });

    it("formats object flags compactly", () => {
        // u=1<<0, p=1<<1, w=1<<2, r=1<<4, W=1<<5, f=1<<7
        expect(formatObjectFlags((1 << 0) | (1 << 4))).toBe("ur");
        expect(formatObjectFlags(0)).toBe("");
    });

    it("detects eval error results", () => {
        expect(hasEvalError({ error: { msg: "boom" } })).toBe(true);
        expect(hasEvalError({ oid: 5 })).toBe(false);
        expect(hasEvalError("plain")).toBe(false);
    });

    it("extracts object references from eval results", () => {
        expect(formatEvalObjectRef({ oid: 3 })).toBe("#3");
        expect(formatEvalObjectRef({ other: true })).toBeNull();
        expect(formatEvalObjectRef("text")).toBeNull();
    });

    it("escapes and serializes MOO string lists", () => {
        expect(escapeMooString("say \"hi\"")).toBe("say \\\"hi\\\"");
        expect(listToMooLiteral(["a", "b"])).toBe("{\"a\", \"b\"}");
    });

    it("clamps editor font sizes to the supported range", () => {
        expect(clampFontSize(5)).toBe(10);
        expect(clampFontSize(12)).toBe(12);
        expect(clampFontSize(99)).toBe(20);
    });

    it("classifies test verbs and method verbs", () => {
        expect(isTestVerb("test_foo")).toBe(true);
        expect(isTestVerb("foo")).toBe(false);

        const method = (over: Partial<VerbData> = {}): VerbData => ({
            names: ["m"],
            owner: "#1",
            location: "#2",
            readable: true,
            writable: true,
            executable: true,
            debug: true,
            dobj: "this",
            prep: "none",
            iobj: "this",
            ...over,
        });
        expect(isMethodVerb(method())).toBe(true);
        expect(isMethodVerb(method({ iobj: "any" }))).toBe(false);
    });

    it("describes objects with names and ids", () => {
        const obj = (over: Partial<ObjectData> = {}): ObjectData => ({
            obj: "5",
            name: "Box",
            parent: "",
            owner: "",
            flags: 0,
            location: "",
            verbsCount: 0,
            propertiesCount: 0,
            ...over,
        });
        expect(describeObject(obj())).toBe("#5 (\"Box\")");
        expect(describeObject(obj({ name: "" }))).toBe("#5");
    });
});
