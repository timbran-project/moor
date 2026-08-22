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

import { describe, expect, it } from "vitest";
import { advanceHistoryExportCursor } from "./historyExportPagination";

describe("advanceHistoryExportCursor", () => {
    it("accepts an advancing cursor", () => {
        expect(advanceHistoryExportCursor("event-2", "event-1")).toBe("event-1");
    });

    it("rejects a missing cursor", () => {
        expect(() => advanceHistoryExportCursor("event-2", undefined)).toThrow(/cursor is missing/);
    });

    it("rejects a repeated cursor", () => {
        expect(() => advanceHistoryExportCursor("event-2", "event-2")).toThrow(/did not advance/);
    });
});
