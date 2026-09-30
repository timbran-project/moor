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

import { afterEach, expect, it, vi } from "vitest";
import { reportUiFailure } from "./ui-failure";

afterEach(() => vi.restoreAllMocks());
it("records a scope and known component names without exception text, URLs, or arbitrary names", () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const error = new TypeError("secret-password and private narrative");
    error.name = "secret-name";
    error.stack = "secret-stack";
    const diagnostic = reportUiFailure(
        "transcript",
        error,
        "\n    at ContentRenderer (https://host/?token=secret-token:10:2)\n    at secret-component\n    at OutputWindow",
    );
    expect(diagnostic).toMatchObject({
        code: "MEADOW_UI_FAILURE",
        scope: "transcript",
        kind: "type",
        components: ["ContentRenderer", "OutputWindow"],
    });
    expect(diagnostic.time).toMatch(/^\d{4}-/);
    expect(JSON.stringify(log.mock.calls)).not.toMatch(/secret|private narrative|https/);
});
it("does not read properties from a thrown value and bounds component details", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const inspect = vi.fn(() => {
        throw new Error("do not inspect");
    });
    const thrown = Object.defineProperties({}, {
        name: { get: inspect },
        message: { get: inspect },
        stack: { get: inspect },
    });
    const diagnostic = reportUiFailure("application", thrown, Array(100).fill("at MainSurface").join("\n"));
    expect(inspect).not.toHaveBeenCalled();
    expect(diagnostic.kind).toBe("unknown");
    expect(diagnostic.components).toHaveLength(8);
    expect(reportUiFailure("interface", new Proxy({}, { getPrototypeOf: inspect })).kind).toBe("unknown");
});

it("identifies optional surfaces using only known application labels", () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(reportUiFailure("optional-surface", new Error(), undefined, "object browser").surface).toBe(
        "object browser",
    );
    expect(reportUiFailure("optional-surface", new Error(), undefined, "secret-label").surface).toBeUndefined();
    expect(JSON.stringify(log.mock.calls)).not.toContain("secret-label");
});
