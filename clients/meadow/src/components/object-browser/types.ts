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

import { MoorVar } from "../../lib/MoorVar";

/** An entry in the browser's object list. */
export interface ObjectData {
    obj: string; // Object ID as string
    name: string;
    parent: string;
    owner: string;
    flags: number;
    location: string;
    verbsCount: number;
    propertiesCount: number;
}

/** A property of the selected object (or inherited from an ancestor). */
export interface PropertyData {
    name: string;
    value: unknown; // JavaScript value from toJS()
    moorVar?: MoorVar; // Original MoorVar for proper formatting
    owner: string;
    definer: string;
    location: string;
    readable: boolean;
    writable: boolean;
    chown: boolean;
}

/** A verb of the selected object (or inherited from an ancestor). */
export interface VerbData {
    names: string[];
    owner: string;
    location: string;
    readable: boolean;
    writable: boolean;
    executable: boolean;
    debug: boolean;
    dobj: string; // ArgSpec string (none/any/this)
    prep: string; // PrepSpec string (none/any/with/at/etc.)
    iobj: string; // ArgSpec string (none/any/this)
    indexInLocation?: number; // Position of this verb within its location object
}

export interface CreateChildFormValues {
    parent: string;
    owner: string;
    objectType: string;
    initArgs: string;
    name: string;
    flags: number;
}

export interface AddPropertyFormValues {
    name: string;
    value: string;
    owner: string;
    perms: string;
}

export interface AddVerbFormValues {
    names: string;
    owner: string;
    perms: string;
    dobj: string;
    prep: string;
    iobj: string;
}

export interface ReloadObjectFormValues {
    objdefFile: File;
    constantsFile: File | null;
    confirmation: string;
}

export interface TestResult {
    verb: string;
    location: string;
    success: boolean;
    result?: string;
    error?: string;
}
