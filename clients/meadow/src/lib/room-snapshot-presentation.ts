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

    const snapshot = payload as Record<string, unknown>;
    const title = coerceText(snapshot.title) || "Room";
    const description = coerceText(snapshot.description);
    const exits = Array.isArray(snapshot.exits) ? snapshot.exits.map(coerceText).filter(Boolean) : [];
    const ambientPassages = Array.isArray(snapshot.ambient_passages) ? snapshot.ambient_passages : [];
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
                const href = `moo://inspect/${encodeURIComponent(objectCurie)}`;
                return `<a href="${href}">${escapeHtml(label)}</a>`;
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
                const href = `moo://inspect/${encodeURIComponent(objectCurie)}`;
                return `<a href="${href}">${escapeHtml(name)}</a>`;
            })
            .filter(Boolean)
        : [];

    const ambientExitLabels = ambientPassages
        .map((entry) => {
            if (Array.isArray(entry) && entry.length >= 3) {
                return coerceText(entry[2]);
            }
            return "";
        })
        .filter(Boolean);

    const allExitLabels = Array.from(new Set([...exits, ...ambientExitLabels]));
    const exitButtons = allExitLabels.map((exit) => {
        const command = `go ${exit}`;
        const href = `moo://cmd/${encodeURIComponent(command)}`;
        return `<a href="${href}">${escapeHtml(exit)}</a>`;
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
                const fallbackHref = `moo://cmd/${encodeURIComponent(fallbackCmd)}`;
                return `<a href="${fallbackHref}">${escapeHtml(fallbackLabel)}</a>`;
            }
            const href = `moo://cmd/${encodeURIComponent(command)}`;
            return `<a href="${href}">${escapeHtml(label)}</a>`;
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
    const playersSection = section("Players", actorButtons);
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
        attributes,
    };
}
