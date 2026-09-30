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
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { checkVersions, debianVersion } from "./version.mjs";

const source = fileURLToPath(new URL("..", import.meta.url));

function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), "meadow-version-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const meadow = join(root, "clients/meadow");
    for (
        const file of [
            "package.json",
            "src-tauri/Cargo.toml",
            "src-tauri/tauri.conf.json",
            "scripts/version.mjs",
            "deploy/debian-packages/build-web-client-deb.sh",
            "deploy/debian-packages/nginx-for-debian.conf",
        ]
    ) {
        mkdirSync(dirname(join(meadow, file)), { recursive: true });
        copyFileSync(join(source, file), join(meadow, file));
    }
    const { version } = JSON.parse(readFileSync(join(meadow, "package.json")));
    const lockPath = join(root, "package-lock.json");
    writeFileSync(lockPath, JSON.stringify({ packages: { "clients/meadow": { version } } }));
    return { root, meadow, version, lockPath };
}

function updateJson(path, update) {
    const data = JSON.parse(readFileSync(path));
    update(data);
    writeFileSync(path, JSON.stringify(data));
}

test("version checks accept matching sources", t => {
    const { meadow, version } = fixture(t);
    assert.equal(checkVersions(meadow), version);
});

for (const target of ["Cargo", "Tauri", "lockfile", "source"]) {
    test(`version checks reject drift in ${target}`, t => {
        const { meadow, lockPath } = fixture(t);
        if (target === "Cargo") {
            const path = join(meadow, "src-tauri/Cargo.toml");
            writeFileSync(path, readFileSync(path, "utf8").replace(/^version = ".*"$/m, "version = \"0.0.0\""));
        } else if (target === "Tauri") {
            updateJson(join(meadow, "src-tauri/tauri.conf.json"), config => config.version = "0.0.0");
        } else if (target === "lockfile") {
            updateJson(lockPath, lock => lock.packages["clients/meadow"].version = "0.0.0");
        } else {
            updateJson(join(meadow, "package.json"), pkg => pkg.version = "0.0.0");
        }
        assert.throws(() => checkVersions(meadow), /expected|must reference/);
        const result = spawnSync(process.execPath, [join(meadow, "scripts/version.mjs"), "check"], {
            encoding: "utf8",
        });
        assert.equal(result.status, 1);
        assert.match(result.stderr, /expected|must reference/);
    });
}

test("a missing Cargo package version cannot be satisfied by a dependency version", t => {
    const { meadow } = fixture(t);
    const path = join(meadow, "src-tauri/Cargo.toml");
    writeFileSync(path, "[package]\nname = \"meadow\"\n[dependencies.example]\nversion = \"2.0.0-dev\"\n");
    assert.throws(() => checkVersions(meadow), /package.version is undefined/);
});

test("Debian versions preserve prereleases, metadata and a separate revision", () => {
    assert.equal(debianVersion("2.0.0-dev"), "2.0.0~dev-1");
    assert.equal(debianVersion("2.0.0-rc.2+build.123", "2"), "2.0.0~rc.2+build.123-2");
    assert.equal(debianVersion("2.0.0-alpha-test"), "2.0.0~alpha-test-1");
    assert.equal(debianVersion("2.0.0+build-test"), "2.0.0+build-test-1");
    assert.equal(debianVersion("2.0.0"), "2.0.0-1");
    for (const version of [undefined, "", "v2.0.0", "2.0", "02.0.0", "2.0.0-01", "2.0.0-", "2.0.0+a_b", "2.0.0\n"]) {
        assert.throws(() => debianVersion(version), /semantic version/);
    }
    for (const revision of ["", "0", "01", "-1", "1\nVersion: 4", "1/2", "1\n"]) {
        assert.throws(() => debianVersion("2.0.0", revision), /positive integer/);
    }
});

const hasDpkg = spawnSync("dpkg-deb", ["--version"]).status === 0;
test("Debian prereleases sort before releases", { skip: !hasDpkg }, () => {
    for (const [before, after] of [["2.0.0-dev", "2.0.0"], ["2.0.0-rc.2", "2.0.0-rc.10"]]) {
        assert.equal(
            spawnSync("dpkg", ["--compare-versions", debianVersion(before), "lt", debianVersion(after)]).status,
            0,
        );
    }
});

test("the packaging script builds derived versions from outside Meadow", { skip: !hasDpkg }, t => {
    const { root, meadow } = fixture(t);
    const version = "3.2.1-rc.2+build.7";
    updateJson(join(meadow, "package.json"), pkg => pkg.version = version);
    writeFileSync(join(meadow, "src-tauri/Cargo.toml"), `[package]\nname = "meadow"\nversion = "${version}"\n`);
    updateJson(join(root, "package-lock.json"), lock => lock.packages["clients/meadow"].version = version);
    mkdirSync(join(meadow, "dist"));
    writeFileSync(join(meadow, "dist/index.html"), "<html>Meadow package fixture</html>");
    const result = spawnSync("bash", [join(meadow, "deploy/debian-packages/build-web-client-deb.sh")], {
        cwd: root,
        encoding: "utf8",
        env: { ...process.env, DEBIAN_REVISION: "2", GPG_KEY_ID: "" },
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const archive = join(root, "target/debian/moor-web-client_3.2.1~rc.2+build.7-2_all.deb");
    const field = spawnSync("dpkg-deb", ["--field", archive, "Version"], { encoding: "utf8" });
    assert.equal(field.status, 0, field.stderr);
    assert.equal(field.stdout.trim(), "3.2.1~rc.2+build.7-2");
    const contents = spawnSync("dpkg-deb", ["--contents", archive], { encoding: "utf8" });
    assert.equal(contents.status, 0, contents.stderr);
    assert.match(contents.stdout, /usr\/share\/moor\/web-client\/index.html/);
    assert.match(contents.stdout, /usr\/share\/doc\/moor-web-client\/nginx-for-debian.conf/);
});
