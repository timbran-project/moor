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

// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

/** Local paths only: server metadata selects an icon name, never SVG markup. */
const paths: Record<string, string> = {
    command: "m4 5 6 7-6 7M13 19h7",
    person: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM4 21v-2a8 8 0 0 1 16 0v2",
    container: "m3 7 9-4 9 4v11l-9 4-9-4ZM3 7l9 4 9-4M12 11v11",
    examine: "M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Zm13 0a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
    take: "M12 3v12m-4-4 4 4 4-4M4 15v5h16v-5",
    drop: "M12 15V3M8 7l4-4 4 4M4 15v5h16v-5",
    give: "M3 12h16m-5-5 5 5-5 5M3 6v12",
    put: "M3 10v10h18V10M12 2v12m-4-4 4 4 4-4",
    talk: "M21 11a8 8 0 0 1-8 8H8l-5 3V7a4 4 0 0 1 4-4h6a8 8 0 0 1 8 8Z",
    open: "M4 21V3h12v18M16 3l5 3v12l-5 3M12 12h.01",
    close: "M5 21V3h14v18ZM15 12h.01",
    lock: "M6 10h12v11H6ZM8 10V6a4 4 0 0 1 8 0v4M12 14v3",
    unlock: "M6 10h12v11H6ZM8 10V6a4 4 0 0 1 8 0M12 14v3",
    exit: "M10 3H3v18h7M8 12h13m-5-5 5 5-5 5",
    help: "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0ZM9 8a3 3 0 0 1 6 0c0 2-3 2-3 5M12 17h.01",
    edit: "m4 16-1 5 5-1L21 7l-4-4ZM14 6l4 4",
    inventory: "M5 7h14l2 14H3ZM8 7V5a4 4 0 0 1 8 0v2",
    sit: "M6 3v11h12M6 14v7m12-7v7M6 10h12v4",
    stand: "M12 21V3m-5 5 5-5 5 5M5 21h14",
};

export function semanticIconMarkup(kind?: string): string {
    const path = kind && Object.prototype.hasOwnProperty.call(paths, kind) ? paths[kind] : undefined;
    return path
        ? `<svg class="semantic-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="${path}"/></svg>`
        : "";
}
