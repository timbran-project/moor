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

import { stringToCurie, uuObjIdToString } from "../../lib/var";
import { ObjectData, VerbData } from "./types";

export const isTestVerb = (name: string): boolean => name.startsWith("test_");

export const isMethodVerb = (verb: VerbData): boolean =>
    verb.dobj === "this" && verb.prep === "none" && verb.iobj === "this";

export const normalizeObjectRefForCompare = (raw: string | null | undefined): string | null => {
    if (!raw) return null;
    try {
        return stringToCurie(raw).toLowerCase();
    } catch {
        return null;
    }
};

/** Decode object flags to a readable compact string. */
export function formatObjectFlags(flags: number): string {
    const parts: string[] = [];
    if (flags & (1 << 0)) parts.push("u"); // User (player)
    if (flags & (1 << 1)) parts.push("p"); // Programmer
    if (flags & (1 << 2)) parts.push("w"); // Wizard
    if (flags & (1 << 4)) parts.push("r"); // Readable
    if (flags & (1 << 5)) parts.push("W"); // Writable (capital W to distinguish from wizard)
    if (flags & (1 << 7)) parts.push("f"); // Fertile
    return parts.length > 0 ? parts.join("") : "";
}

export const MIN_FONT_SIZE = 10;
export const MAX_FONT_SIZE = 20;

export const persistNonNull = <T>(value: T | null): boolean => value !== null;

export const clampFontSize = (value: number): number => {
    return Math.min(MAX_FONT_SIZE, Math.max(MIN_FONT_SIZE, value));
};

export const deserializeFontSize = (raw: string): number | null => {
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) {
        return null;
    }
    return clampFontSize(parsed);
};

export const deserializeStoredString = (raw: string): string | null => {
    if (raw.length === 0) {
        return "";
    }
    try {
        return JSON.parse(raw);
    } catch {
        return raw;
    }
};

export const deserializeEditorType = (raw: string): "property" | "verb" | null => {
    const value = deserializeStoredString(raw);
    return value === "property" || value === "verb" ? value : null;
};

export const deserializePropertyName = (raw: string): string | null => {
    return deserializeStoredString(raw);
};

export const deserializeVerbIndex = (raw: string): number | null => {
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) {
        return null;
    }
    return parsed;
};

export const escapeMooString = (value: string): string => {
    return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
};

export const listToMooLiteral = (items: string[]): string => {
    const parts = items.map(item => `"${escapeMooString(item)}"`);
    return `{${parts.join(", ")}}`;
};

export const isRecord = (value: unknown): value is Record<string, unknown> => {
    return typeof value === "object" && value !== null;
};

export const hasEvalError = (value: unknown): value is { error?: { msg?: string } } => {
    return isRecord(value) && "error" in value;
};

export const formatEvalObjectRef = (value: unknown): string | null => {
    if (!isRecord(value)) {
        return null;
    }
    const oid = value["oid"];
    if (typeof oid === "number") {
        return `#${oid}`;
    }
    const uuid = value["uuid"];
    if (typeof uuid === "string") {
        return `#${uuObjIdToString(BigInt(uuid))}`;
    }
    return null;
};

export const readFileAsText = (file: File): Promise<string> => {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result ?? ""));
        reader.onerror = () => reject(reader.error || new Error("Failed to read file"));
        reader.readAsText(file);
    });
};

/**
 * Normalizes free-form object input into a MOO object expression where
 * possible ("#123", "$object", "player", ...), passing through anything else.
 */
export const normalizeObjectInput = (raw: string): string => {
    if (!raw) return "";
    const trimmed = raw.trim();
    if (!trimmed) return "";
    if (
        trimmed.startsWith("#") || trimmed.startsWith("$") || trimmed.startsWith("player")
        || trimmed.startsWith("caller")
    ) {
        return trimmed;
    }
    if (trimmed.startsWith("oid:")) {
        return `#${trimmed.substring(4)}`;
    }
    if (trimmed.startsWith("uuid:")) {
        return `#${trimmed.substring(5)}`;
    }
    if (/^-?\d+$/.test(trimmed)) {
        return `#${trimmed}`;
    }
    if (/^[0-9A-Za-z-]+$/.test(trimmed)) {
        return `#${trimmed}`;
    }
    return trimmed;
};

/** Human-readable label for an object: `#id ("name")` or just `#id`. */
export const describeObject = (obj: ObjectData): string => {
    const id = normalizeObjectInput(obj.obj) || "#?";
    return obj.name ? `${id} ("${obj.name}")` : id;
};

export interface NormalizedObjectRef {
    display: string;
    objectId: string | null;
}

/** Parses an object reference into a display form plus a bare object id. */
export const normalizeObjectRef = (raw: string): NormalizedObjectRef => {
    const value = raw?.trim();
    if (!value) {
        return { display: "none", objectId: null };
    }
    if (value === "nothing" || value === "-1") {
        return { display: "#-1", objectId: null };
    }
    if (value.startsWith("oid:")) {
        const id = value.substring(4);
        return { display: `#${id}`, objectId: id };
    }
    if (value.startsWith("uuid:")) {
        const id = value.substring(5);
        return { display: `#${id}`, objectId: id };
    }
    if (/^-?\d+$/.test(value)) {
        return { display: `#${value}`, objectId: value };
    }
    return { display: value, objectId: null };
};

// Helper to check if object ID is UUID-based (contains "-" like "FFFFFF-FFFFFFFFFF")
export const isUuidObject = (objId: string): boolean => {
    return objId.includes("-");
};
