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

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const meadow = fileURLToPath(new URL("..", import.meta.url));
const readJson = path => JSON.parse(readFileSync(path, "utf8"));

/** Convert the npm version to Debian syntax while keeping the packaging revision separate. */
export function debianVersion(version, revision = "1") {
    const match = typeof version === "string"
        && /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([\da-zA-Z-]+(?:\.[\da-zA-Z-]+)*))?(?:\+([\da-zA-Z-]+(?:\.[\da-zA-Z-]+)*))?$/
            .exec(version);
    if (!match || match[0] !== version || match[4]?.split(".").some(identifier => /^0\d+$/.test(identifier))) {
        throw new Error(`Invalid Meadow semantic version: ${version}`);
    }
    if (/^[1-9]\d*$/.exec(revision)?.[0] !== revision) {
        throw new Error("DEBIAN_REVISION must be a positive integer");
    }
    const [, major, minor, patch, prerelease, metadata] = match;
    return `${major}.${minor}.${patch}${prerelease ? `~${prerelease}` : ""}${
        metadata ? `+${metadata}` : ""
    }-${revision}`;
}

/** Validate the required Cargo and npm lockfile copies against Meadow's package.json. */
export function checkVersions(directory = meadow) {
    const { version } = readJson(resolve(directory, "package.json"));
    debianVersion(version);
    const cargo = readFileSync(resolve(directory, "src-tauri/Cargo.toml"), "utf8");
    // Read the explicit package version, excluding dependency and workspace sections.
    const packageSection = cargo.split(/^\[package\][^\S\n]*(?:#[^\n]*)?$/m)[1]?.split(/^\[/m)[0];
    const cargoVersion = packageSection?.match(/^version\s*=\s*["']([^"']+)["']\s*(?:#.*)?$/m)?.[1];
    if (cargoVersion !== version) {
        throw new Error(`src-tauri/Cargo.toml package.version is ${cargoVersion}; expected ${version}`);
    }
    const config = readJson(resolve(directory, "src-tauri/tauri.conf.json"));
    if (config.version !== "../package.json") {
        throw new Error("src-tauri/tauri.conf.json version must reference ../package.json");
    }
    const lock = readJson(resolve(directory, "../../package-lock.json"));
    const lockedVersion = lock.packages?.["clients/meadow"]?.version;
    if (lockedVersion !== version) {
        throw new Error(
            `package-lock.json Meadow version is ${lockedVersion}; expected ${version}. Run npm install --package-lock-only.`,
        );
    }
    return version;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const command = process.argv[2] ?? "check";
        if (!["check", "debian"].includes(command) || process.argv.length > 3) {
            throw new Error("Usage: node scripts/version.mjs [check|debian]");
        }
        const version = checkVersions();
        console.log(
            command === "debian"
                ? debianVersion(version, process.env.DEBIAN_REVISION ?? "1")
                : `Meadow versions agree: ${version}`,
        );
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
