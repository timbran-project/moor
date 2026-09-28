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

import { decodeAnnotation, MAX_ANNOTATIONS, SemanticAnnotation } from "@moor/web-sdk";
import { PresentationData } from "../types/presentation";
import { jsObjectRefToCurie } from "./var";

function coerceText(value: unknown): string {
    if (typeof value === "string") {
        return value.trim();
    }
    if (typeof value === "number" || typeof value === "boolean") {
        return String(value);
    }
    if (Array.isArray(value)) {
        return value.map(coerceText).filter(Boolean).join(" ").trim();
    }
    return "";
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

export function roomSnapshotToPresentation(payload: unknown): PresentationData | null {
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
        return null;
    }

    const annotations: Record<string, SemanticAnnotation> = Object.create(null);
    const region = (label: string, annotation: SemanticAnnotation) => {
        const count = Object.keys(annotations).length;
        if (count >= MAX_ANNOTATIONS || !decodeAnnotation(annotation)) return escapeHtml(label);
        const id = `a${count + 1}`;
        annotations[id] = annotation;
        return `<span data-moor-annotation="${id}">${escapeHtml(label)}</span>`;
    };
    const snapshot = payload as Record<string, unknown>;
    const title = coerceText(snapshot.title) || "Room";
    const description = coerceText(snapshot.description);
    const exitLinks = Array.isArray(snapshot.exit_links) ? snapshot.exit_links : [];
    const actions = Array.isArray(snapshot.actions) ? snapshot.actions : [];

    const actorButtons = Array.isArray(snapshot.actors)
        ? snapshot.actors
            .map((entry) => {
                if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                    return "";
                }
                const actor = entry as Record<string, unknown>;
                const name = coerceText(actor.name);
                const status = coerceText(actor.status);
                const objectCurie = jsObjectRefToCurie(actor.object);
                if (!name || !objectCurie) {
                    return "";
                }
                const label = status && status !== "awake" ? `${name} (${status})` : name;
                return region(label, { kind: "object", ref: objectCurie, objectKind: "person" });
            })
            .filter(Boolean)
        : [];

    const thingButtons = Array.isArray(snapshot.things)
        ? snapshot.things
            .map((entry) => {
                if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                    return "";
                }
                const thing = entry as Record<string, unknown>;
                const name = coerceText(thing.name);
                const objectCurie = jsObjectRefToCurie(thing.object);
                if (!name || !objectCurie) {
                    return "";
                }
                return region(name, {
                    kind: "object",
                    ref: objectCurie,
                    ...(thing.objectKind === "container" ? { objectKind: "container" as const } : {}),
                });
            })
            .filter(Boolean)
        : [];

    const exitButtons = exitLinks.flatMap(entry => {
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) return [];
        const exit = entry as Record<string, unknown>;
        const label = coerceText(exit.label);
        const annotation = decodeAnnotation(exit.annotation);
        if (!label || annotation?.kind !== "command" || !annotation.exit) return [];
        return [region(label, annotation)];
    });

    const actionButtons = actions
        .map((entry) => {
            if (!Array.isArray(entry) || entry.length < 2) {
                return "";
            }
            const command = coerceText(entry[1] === undefined ? "" : entry[1] as unknown);
            const label = coerceText(entry[2] === undefined ? "" : entry[2] as unknown);
            if (!command || !label) {
                const fallbackCmd = coerceText(entry[0]);
                const fallbackLabel = coerceText(entry[1]);
                if (!fallbackCmd || !fallbackLabel) {
                    return "";
                }
                return region(fallbackLabel, { kind: "command", command: fallbackCmd });
            }
            return region(label, { kind: "command", command });
        })
        .filter(Boolean);

    const section = (label: string, chips: string[]) => {
        if (chips.length === 0) {
            return "";
        }
        return `<div class="room_snapshot_row">
            <span class="room_snapshot_row_label">${escapeHtml(label)}</span>
            <div class="room_snapshot_chip_row">${chips.join("")}</div>
        </div>`;
    };

    const chipSections: string[] = [];
    const exitsSection = section("Exits", exitButtons);
    if (exitsSection) chipSections.push(exitsSection);
    const objectsSection = section("Things", [...actionButtons, ...thingButtons]);
    if (objectsSection) chipSections.push(objectsSection);
    const playersSection = section("People", actorButtons);
    if (playersSection) chipSections.push(playersSection);

    const htmlParts: string[] = [];
    if (description) {
        htmlParts.push(`<p>${escapeHtml(description)}</p>`);
    }
    if (chipSections.length > 0) {
        htmlParts.push(`<div class="room_snapshot_chips">${chipSections.join("")}</div>`);
    }

    const roomCurie = jsObjectRefToCurie(snapshot.room);
    const attributes: Array<[string, string]> = [
        ["title", title],
        ["kind", "room_look"],
    ];
    if (roomCurie) {
        attributes.push(["room", roomCurie]);
    }

    return {
        id: "room-look",
        target: "top",
        content_type: "text/html",
        content: htmlParts.join(""),
        annotations,
        attributes,
    };
}
