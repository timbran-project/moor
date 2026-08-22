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

import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const compiler = process.env.MOOR_FLATC || "flatc";

try {
    execFileSync(compiler, ["--version"], { stdio: "ignore" });
} catch {
    console.error("flatc is required to generate TypeScript schema bindings.");
    console.error("Install flatc or set MOOR_FLATC to the compiler's absolute path.");
    process.exit(1);
}

const schemaDirectory = dirname(fileURLToPath(import.meta.url));
const outputDirectory = join(schemaDirectory, "generated");
rmSync(outputDirectory, { recursive: true, force: true });
mkdirSync(outputDirectory);

try {
    execFileSync(
        compiler,
        ["--ts", "--gen-all", "-o", outputDirectory, "all_schemas.fbs"],
        { cwd: schemaDirectory, stdio: "inherit" },
    );
} catch {
    console.error("flatc did not generate the TypeScript schema bindings.");
    process.exit(1);
}
