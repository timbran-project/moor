// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

/** Content types accepted by narrative notifications after wire-name normalization. */
export type NarrativeNotifyContentType = "text/plain" | "text/djot" | "text/html" | "text/x-uri";
export type NarrativeContentType = NarrativeNotifyContentType | "text/traceback";
export type NarrativeContent = string | string[];

/** Omitted types mean plain text; explicit unsupported types are rejected. */
export function parseNarrativeContentType(value: string | null | undefined): NarrativeNotifyContentType | null {
    switch (value) {
        case null:
        case undefined:
        case "text_plain":
        case "text/plain":
            return "text/plain";
        case "text_djot":
        case "text/djot":
            return "text/djot";
        case "text_html":
        case "text/html":
            return "text/html";
        case "text_x_uri":
        case "text/x-uri":
            return "text/x-uri";
        default:
            return null;
    }
}

export function isNarrativeContent(value: unknown): value is NarrativeContent {
    return typeof value === "string" || (Array.isArray(value) && value.every(line => typeof line === "string"));
}
