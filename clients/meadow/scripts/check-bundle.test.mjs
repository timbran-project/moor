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

import assert from "node:assert/strict";
import { test } from "node:test";
import { budgetFailures, startupFiles } from "./check-bundle.mjs";

test("startup includes transitive static imports once and excludes deferred chunks", () => {
    const manifest = {
        "index.html": { file: "main.js", isEntry: true, imports: ["shared", "react"], dynamicImports: ["editor"] },
        shared: { file: "shared.js", imports: ["react"] },
        react: { file: "react.js", imports: ["shared"] },
        editor: { file: "editor.js", imports: ["shared"] },
    };
    assert.deepEqual(startupFiles(manifest), ["main.js", "react.js", "shared.js"]);
    manifest["index.html"].imports.push("editor");
    assert.deepEqual(startupFiles(manifest), ["editor.js", "main.js", "react.js", "shared.js"]);
});

test("missing manifest dependencies and entries fail rather than undercount", () => {
    assert.throws(() => startupFiles({}), /No entry/);
    assert.throws(
        () => startupFiles({ main: { file: "main.js", isEntry: true, imports: ["missing"] } }),
        /Missing manifest/,
    );
});

test("budgets cover raw and compressed startup, all JavaScript, and aggregate workers", () => {
    const limits = {
        startupBytes: 10,
        startupGzipBytes: 5,
        totalJavaScriptBytes: 30,
        totalJavaScriptGzipBytes: 15,
        workerBytes: 8,
    };
    const report = {
        startup: { bytes: 10, gzipBytes: 5 },
        totalJavaScript: { bytes: 30, gzipBytes: 15 },
        workers: [{ bytes: 8 }],
    };
    assert.deepEqual(budgetFailures(report, limits), []);
    assert.throws(() => budgetFailures(report, {}), /Invalid bundle budget/);
    for (const name of Object.keys(limits)) {
        assert.equal(budgetFailures(report, { ...limits, [name]: limits[name] - 1 }).length, 1);
    }
    assert.equal(budgetFailures({ ...report, workers: [{ bytes: 5 }, { bytes: 4 }] }, limits).length, 1);
});
