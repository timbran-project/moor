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

import { readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

/** Count every statically imported chunk once, including shared dependencies. */
export function startupFiles(manifest) {
    const visited = new Set();
    const files = new Set();
    function visit(key) {
        if (visited.has(key)) return;
        const chunk = manifest[key];
        if (!chunk) throw new Error(`Missing manifest dependency: ${key}`);
        visited.add(key);
        if (chunk.file.endsWith(".js")) files.add(chunk.file);
        for (const dependency of chunk.imports ?? []) visit(dependency);
    }
    const entries = Object.keys(manifest).filter(key => manifest[key].isEntry);
    if (!entries.length) throw new Error("No entry chunks in the Vite manifest");
    entries.forEach(visit);
    return [...files].sort();
}

export function budgetFailures(report, limits) {
    const measures = {
        startupBytes: report.startup.bytes,
        startupGzipBytes: report.startup.gzipBytes,
        totalJavaScriptBytes: report.totalJavaScript.bytes,
        totalJavaScriptGzipBytes: report.totalJavaScript.gzipBytes,
        workerBytes: report.workers.reduce((sum, worker) => sum + worker.bytes, 0),
    };
    for (const name of Object.keys(measures)) {
        if (!Number.isFinite(limits[name]) || limits[name] <= 0) throw new Error(`Invalid bundle budget: ${name}`);
    }
    return Object.entries(measures).filter(([name, value]) => value > limits[name])
        .map(([name, value]) => `${name}: ${value} bytes exceeds budget ${limits[name]}`);
}

async function listFiles(directory, prefix = "") {
    const files = [];
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        const name = join(prefix, entry.name);
        if (entry.isDirectory()) files.push(...await listFiles(join(directory, entry.name), name));
        else files.push(name);
    }
    return files;
}

export async function reportBundle(dist, limits) {
    const manifest = JSON.parse(await readFile(join(dist, ".vite/manifest.json"), "utf8"));
    const files = await listFiles(dist);
    const assets = await Promise.all(
        files.filter(file => file.endsWith(".js")).map(async file => {
            const bytes = await readFile(join(dist, file));
            return { file, bytes: bytes.byteLength, gzipBytes: gzipSync(bytes).byteLength };
        }),
    );
    const sum = (items) => ({
        bytes: items.reduce((total, item) => total + item.bytes, 0),
        gzipBytes: items.reduce((total, item) => total + item.gzipBytes, 0),
    });
    const startup = startupFiles(manifest).map(file => {
        const asset = assets.find(asset => asset.file === file);
        if (!asset) throw new Error(`Missing built asset: ${file}`);
        return asset;
    });
    const report = {
        startup: { ...sum(startup), files: startup },
        totalJavaScript: sum(assets),
        workers: assets.filter(asset => /worker[^/]*\.js$/i.test(asset.file)),
        sourceMapFiles: files.filter(file => file.endsWith(".map")).length,
        limits,
    };
    await writeFile(join(dist, "bundle-report.json"), JSON.stringify(report, null, 2) + "\n");
    console.table([
        { asset: "Startup JavaScript (all static imports)", ...sum(startup) },
        { asset: "All JavaScript (including deferred code and workers)", ...sum(assets) },
        ...report.workers.map(({ file, ...sizes }) => ({ asset: file, ...sizes })),
    ]);
    console.log(`Source maps: ${report.sourceMapFiles}; report: ${join(dist, "bundle-report.json")}`);
    const failures = budgetFailures(report, limits);
    if (failures.length) throw new Error(`Bundle budget exceeded:\n${failures.join("\n")}`);
    return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const meadow = resolve(dirname(fileURLToPath(import.meta.url)), "..");
    const limits = JSON.parse(await readFile(join(meadow, "bundle-budget.json"), "utf8"));
    try {
        await reportBundle(join(meadow, "dist"), limits);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
