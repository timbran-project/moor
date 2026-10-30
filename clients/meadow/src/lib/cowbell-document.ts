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

import { AnnotationTable, decodeAnnotations } from "@moor/web-sdk";
import { finishContentElement } from "./djot-renderer";

// The limits and rules of $document_schema, version 1.
const MAX_NESTING = 32;
const MAX_RECORDS = 8192;
const MAX_REFERENCES = 512;
const MAX_ENCODED_BYTES = 262144;
const ALIGNMENTS: Readonly<Record<string, string>> = { start: "left", center: "center", end: "right" };
const LANGUAGE = /^[A-Za-z0-9_.+-]*$/;

type Fields = Record<string, unknown>;

interface WalkState {
    records: number;
    references: Record<string, unknown>;
    nextAnchor: number;
}

export interface RenderedDocument {
    readonly html: string;
    readonly annotations: AnnotationTable;
}

function fail(path: string, rule: string): never {
    throw new Error(`${path}: ${rule}`);
}

function isRecord(value: unknown): value is Fields {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function record(value: unknown, path: string, allowed: readonly string[]): Fields {
    if (!isRecord(value)) fail(path, "expected record");
    for (const key of Object.keys(value)) {
        if (!allowed.includes(key)) fail(path, `unknown field ${key}`);
    }
    return value;
}

function text(fields: Fields, key: string, path: string): string {
    const value = fields[key];
    if (typeof value !== "string") fail(`${path}.${key}`, "expected string");
    return value;
}

function list(fields: Fields, key: string, path: string): unknown[] {
    const value = fields[key];
    if (!Array.isArray(value)) fail(`${path}.${key}`, "expected list");
    return value;
}

function enter(state: WalkState, depth: number, path: string): void {
    if (depth > MAX_NESTING) fail(path, "nesting exceeds limit");
    state.records += 1;
    if (state.records > MAX_RECORDS) fail(path, "too many records");
}

function element<K extends keyof HTMLElementTagNameMap>(tag: K, ...children: Node[]): HTMLElementTagNameMap[K] {
    const result = document.createElement(tag);
    result.append(...children);
    return result;
}

function safeUrl(url: string, path: string, schemes: RegExp): string {
    if (!schemes.test(url)) fail(path, "unsupported URL scheme");
    for (let i = 0; i < url.length; i++) {
        const code = url.charCodeAt(i);
        if (code <= 32 || code === 127) fail(path, "URL contains whitespace or controls");
    }
    return url;
}

/** Keep ANSI style sequences; show every other ESC as visible text, as the core renderer does. */
export function terminalStyles(source: string): string {
    if (!source.includes("\x1b")) return source;
    let styled = false;
    // eslint-disable-next-line no-control-regex -- ESC is what this filters.
    const result = source.replace(/\x1b(?:\[[0-9;]{0,33}m)?/g, sequence => {
        if (sequence === "\x1b") return "\\x1b";
        styled = sequence !== "\x1b[m" && sequence !== "\x1b[0m";
        return sequence;
    });
    return styled ? `${result}\x1b[0m` : result;
}

function inlines(
    values: unknown[],
    path: string,
    depth: number,
    interactive: boolean,
    state: WalkState,
): Node[] {
    const nodes: Node[] = [];
    values.forEach((value, i) => nodes.push(...inline(value, `${path}[${i}]`, depth, interactive, state)));
    return nodes;
}

function inline(value: unknown, path: string, depth: number, interactive: boolean, state: WalkState): Node[] {
    enter(state, depth, path);
    if (!isRecord(value)) fail(path, "expected node");
    const children = (nested: boolean) =>
        inlines(list(value, "children", path), `${path}.children`, depth + 1, nested, state);
    switch (value.kind) {
        case "text":
            record(value, path, ["kind", "text"]);
            if (/[\r\n]/.test(text(value, "text", path))) fail(`${path}.text`, "use break nodes for newlines");
            return [document.createTextNode(terminalStyles(text(value, "text", path)))];
        case "inline_code": {
            record(value, path, ["kind", "text"]);
            const code = element("code");
            code.textContent = text(value, "text", path);
            return [code];
        }
        case "soft_break":
            record(value, path, ["kind"]);
            return [document.createTextNode(" ")];
        case "hard_break":
            record(value, path, ["kind"]);
            return [element("br"), document.createTextNode("\n")];
        case "emphasis":
            record(value, path, ["kind", "children"]);
            return [element("em", ...children(interactive))];
        case "strong":
            record(value, path, ["kind", "children"]);
            return [element("strong", ...children(interactive))];
        case "strike":
            record(value, path, ["kind", "children"]);
            return [element("del", ...children(interactive))];
        case "link": {
            record(value, path, ["kind", "url", "title", "children"]);
            if (interactive) fail(path, "interactive labels cannot nest");
            const link = element("a", ...children(true));
            link.setAttribute("href", safeUrl(text(value, "url", path), `${path}.url`, /^(https?:\/\/|mailto:)/));
            if ("title" in value) link.title = text(value, "title", path);
            return [link];
        }
        case "reference": {
            record(value, path, ["kind", "descriptor", "children"]);
            if (interactive) fail(path, "interactive labels cannot nest");
            if (Object.keys(state.references).length >= MAX_REFERENCES) fail(path, "too many references");
            const anchor = `a${state.nextAnchor}`;
            state.nextAnchor += 1;
            state.references[anchor] = value.descriptor;
            const reference = element("span", ...children(true));
            reference.setAttribute("data-moor-annotation", anchor);
            return [reference];
        }
        case "image": {
            record(value, path, ["kind", "src", "alt", "title"]);
            const image = element("img");
            image.setAttribute("src", safeUrl(text(value, "src", path), `${path}.src`, /^https?:\/\//));
            image.alt = text(value, "alt", path);
            if ("title" in value) image.title = text(value, "title", path);
            return [image];
        }
        default:
            fail(path, "unknown inline node");
    }
}

function joined(parts: Node[]): Node[] {
    return parts.flatMap((part, i) => (i > 0 ? [document.createTextNode("\n"), part] : [part]));
}

function blocks(values: unknown[], path: string, depth: number, state: WalkState): Node[] {
    return joined(values.map((value, i) => block(value, `${path}[${i}]`, depth, state)));
}

function block(value: unknown, path: string, depth: number, state: WalkState): Node {
    enter(state, depth, path);
    if (!isRecord(value)) fail(path, "expected node");
    switch (value.kind) {
        case "paragraph":
            record(value, path, ["kind", "children"]);
            return element(
                "p",
                ...inlines(list(value, "children", path), `${path}.children`, depth + 1, false, state),
            );
        case "heading": {
            record(value, path, ["kind", "level", "children"]);
            const level = value.level;
            if (typeof level !== "number" || !Number.isInteger(level) || level < 1 || level > 6) {
                fail(`${path}.level`, "heading level must be 1 through 6");
            }
            return element(
                `h${level}` as "h1",
                ...inlines(list(value, "children", path), `${path}.children`, depth + 1, false, state),
            );
        }
        case "block_quote":
            record(value, path, ["kind", "children"]);
            return element(
                "blockquote",
                ...blocks(list(value, "children", path), `${path}.children`, depth + 1, state),
            );
        case "code_block":
            return codeBlock(record(value, path, ["kind", "text", "language", "first_line"]), path);
        case "thematic_break":
            record(value, path, ["kind"]);
            return element("hr");
        case "list":
            return listBlock(record(value, path, ["kind", "style", "start", "items"]), path, depth, state);
        case "definition_list":
            return definitionList(record(value, path, ["kind", "items"]), path, depth, state);
        case "table":
            return table(record(value, path, ["kind", "caption", "columns", "header", "rows"]), path, depth, state);
        default:
            fail(path, "unknown block node");
    }
}

function codeBlock(fields: Fields, path: string): Node {
    const source = text(fields, "text", path);
    const code = element("code");
    code.textContent = source;
    if ("language" in fields) {
        const language = text(fields, "language", path);
        if (!LANGUAGE.test(language)) fail(`${path}.language`, "invalid code language");
        if (language) code.className = `language-${language}`;
    }
    const listing = element("pre", code);
    if (!("first_line" in fields)) return listing;
    const first = fields.first_line;
    if (typeof first !== "number" || !Number.isSafeInteger(first) || first <= 0) {
        fail(`${path}.first_line`, "expected positive integer");
    }
    if (!source) return listing;
    const lines = source.split("\n");
    const count = source.endsWith("\n") ? lines.length - 1 : lines.length;
    const numbers = element("pre");
    numbers.textContent = Array.from({ length: count }, (_, i) => String(first + i)).join("\n");
    const gutter = element("td", numbers);
    gutter.setAttribute("aria-hidden", "true");
    gutter.setAttribute("style", "user-select:none");
    return element("table", element("tbody", element("tr", gutter, element("td", listing))));
}

/** Compact columns suit bullet lists whose every item is one paragraph of references. */
function isReferenceList(items: Fields[]): boolean {
    return items.length > 0 && items.every(item => {
        const contents = item.blocks as Fields[];
        if ("checked" in item || contents.length !== 1 || contents[0].kind !== "paragraph") return false;
        const children = contents[0].children as Fields[];
        return children.some(child => child.kind === "reference")
            && children.every(child =>
                child.kind === "reference" || (child.kind === "text" && !(child.text as string).trim())
            );
    });
}

function listBlock(fields: Fields, path: string, depth: number, state: WalkState): Node {
    const numbered = fields.style === "numbered";
    if (!numbered && fields.style !== "bullet") fail(`${path}.style`, "invalid enum value");
    const items = list(fields, "items", path).map((value, i) => {
        const itemPath = `${path}.items[${i}]`;
        enter(state, depth + 1, itemPath);
        const item = record(value, itemPath, ["blocks", "checked"]);
        const contents = blocks(list(item, "blocks", itemPath), `${itemPath}.blocks`, depth + 2, state);
        const row = element("li");
        if ("checked" in item) {
            if (typeof item.checked !== "boolean") fail(`${itemPath}.checked`, "expected boolean");
            const box = element("input");
            box.type = "checkbox";
            box.disabled = true;
            box.defaultChecked = item.checked;
            row.append(box, document.createTextNode(" "));
        }
        row.append(...contents);
        return { item, row };
    });
    if (numbered) {
        const start = "start" in fields ? fields.start : 1;
        if (typeof start !== "number" || !Number.isSafeInteger(start)) fail(`${path}.start`, "expected integer");
        const result = element("ol", ...joined(items.map(({ row }) => row)));
        result.setAttribute("start", String(start));
        return result;
    }
    if ("start" in fields) fail(`${path}.start`, "bullet lists have no start");
    const result = element("ul", ...joined(items.map(({ row }) => row)));
    if (isReferenceList(items.map(({ item }) => item))) result.className = "reference-columns";
    return result;
}

function definitionList(fields: Fields, path: string, depth: number, state: WalkState): Node {
    const parts = list(fields, "items", path).flatMap((value, i) => {
        const itemPath = `${path}.items[${i}]`;
        enter(state, depth + 1, itemPath);
        const item = record(value, itemPath, ["term", "definition"]);
        return [
            document.createTextNode(i > 0 ? "\n" : ""),
            element("dt", ...inlines(list(item, "term", itemPath), `${itemPath}.term`, depth + 2, false, state)),
            element("dd", ...blocks(list(item, "definition", itemPath), `${itemPath}.definition`, depth + 2, state)),
        ];
    });
    return element("dl", ...parts);
}

function table(fields: Fields, path: string, depth: number, state: WalkState): Node {
    const caption = inlines(list(fields, "caption", path), `${path}.caption`, depth + 1, false, state);
    const alignments = list(fields, "columns", path).map((value, i) => {
        const columnPath = `${path}.columns[${i}]`;
        enter(state, depth + 1, columnPath);
        const align = record(value, columnPath, ["align"]).align;
        if (typeof align !== "string" || !Object.hasOwn(ALIGNMENTS, align)) {
            fail(`${columnPath}.align`, "invalid enum value");
        }
        return ALIGNMENTS[align];
    });
    if (!alignments.length) fail(`${path}.columns`, "table needs at least one column");
    const parts: Node[] = caption.length ? [element("caption", ...caption)] : [];
    if ("header" in fields) {
        const header = list(fields, "header", path);
        if (header.length !== alignments.length) fail(`${path}.header`, "wrong column count");
        const cells = header.map((labels, i) => {
            const labelPath = `${path}.header[${i}]`;
            if (!Array.isArray(labels)) fail(labelPath, "expected inline list");
            const cell = element("th", ...inlines(labels, labelPath, depth + 1, false, state));
            cell.setAttribute("scope", "col");
            cell.setAttribute("align", alignments[i]);
            return cell;
        });
        parts.push(element("thead", element("tr", ...cells)));
    }
    const rows = list(fields, "rows", path).map((value, i) => {
        const rowPath = `${path}.rows[${i}]`;
        enter(state, depth + 1, rowPath);
        const row = record(value, rowPath, ["cells"]);
        const cells = list(row, "cells", rowPath);
        if (cells.length !== alignments.length) fail(`${rowPath}.cells`, "wrong column count");
        return element(
            "tr",
            ...cells.map((cellValue, j) => {
                const cellPath = `${rowPath}.cells[${j}]`;
                enter(state, depth + 2, cellPath);
                const cell = record(cellValue, cellPath, ["blocks"]);
                const result = element(
                    "td",
                    ...blocks(list(cell, "blocks", cellPath), `${cellPath}.blocks`, depth + 3, state),
                );
                result.setAttribute("align", alignments[j]);
                return result;
            }),
        );
    });
    parts.push(element("tbody", ...joined(rows)));
    return element("table", ...joined(parts));
}

/**
 * Render an encoded Cowbell document. Nodes become DOM elements and text nodes, so document text is
 * never parsed as markup. An invalid or unsupported document renders nothing: the caller shows the
 * complete rendered body instead.
 */
export function renderCowbellDocument(value: unknown, enableEmoji: boolean = false): RenderedDocument | null {
    try {
        const root = record(value, "document", ["version", "blocks"]);
        if (root.version !== 1) fail("document.version", "unsupported document version");
        if (new TextEncoder().encode(JSON.stringify(root)).length > MAX_ENCODED_BYTES) {
            fail("document", "encoded document exceeds limit");
        }
        const state: WalkState = { records: 0, references: {}, nextAnchor: 1 };
        const container = document.createElement("div");
        container.append(...blocks(list(root, "blocks", "document"), "document.blocks", 1, state));
        const annotations = decodeAnnotations(state.references);
        if (Object.keys(annotations).length !== Object.keys(state.references).length) {
            fail("document", "unsupported reference descriptor");
        }
        return { html: finishContentElement(container, enableEmoji, annotations), annotations };
    } catch (error) {
        console.warn("[Meadow] Using the rendered body instead of the document:", error);
        return null;
    }
}
