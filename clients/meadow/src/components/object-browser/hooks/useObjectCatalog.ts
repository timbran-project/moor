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

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePersistentState } from "../../../hooks/usePersistentState";
import { fetchServerFeatures, listObjectsFlatBuffer, performEvalFlatBuffer } from "../../../lib/rpc-fb";
import type { ServerFeatureSet } from "../../../lib/rpc-fb";
import { objToString, uuObjIdToString } from "../../../lib/var";
import { isRecord, isUuidObject, normalizeObjectRefForCompare } from "../browserUtils";
import { ObjectData } from "../types";

export interface UseObjectCatalogArgs {
    authToken: string;
    visible: boolean;
    playerObjectRef: string | null;
}

/**
 * Owns the browser's object catalog: fetching the object list, `$` name
 * aliases from #0, server feature flags for object creation, and
 * filter/ownership display state.
 */
export const useObjectCatalog = ({ authToken, visible, playerObjectRef }: UseObjectCatalogArgs) => {
    const [objects, setObjects] = useState<ObjectData[]>([]);
    const [isLoading, setIsLoading] = useState(false);
    const [filter, setFilter] = useState("");
    const [showMineOnly, setShowMineOnly] = usePersistentState(
        "moor-object-browser-show-mine-only",
        false,
    );
    const [serverFeatures, setServerFeatures] = useState<ServerFeatureSet | null>(null);
    const [dollarNames, setDollarNames] = useState<Map<string, string>>(new Map());

    /** Fetches the full object list, replacing local state. */
    const loadObjects = useCallback(async (): Promise<ObjectData[]> => {
        setIsLoading(true);
        let objectList: ObjectData[] = [];
        try {
            const reply = await listObjectsFlatBuffer(authToken);
            const objectsLength = reply.objectsLength();
            const result: ObjectData[] = [];

            // ObjUnion enum: 0=NONE, 1=ObjId, 2=UuObjId, 3=AnonymousObjId
            const ANONYMOUS_OBJ_TYPE = 3;

            for (let i = 0; i < objectsLength; i++) {
                const objInfo = reply.objects(i);
                if (!objInfo) continue;

                const obj = objInfo.obj();

                // Skip anonymous objects - they can't be referenced in eval calls
                if (obj && obj.objType() === ANONYMOUS_OBJ_TYPE) {
                    continue;
                }

                const name = objInfo.name();
                const parent = objInfo.parent();
                const owner = objInfo.owner();
                const location = objInfo.location();

                const objStr = objToString(obj);
                if (!objStr) continue; // Skip objects we can't get an ID for

                result.push({
                    obj: objStr,
                    name: name?.value() || "",
                    parent: objToString(parent) || "",
                    owner: objToString(owner) || "",
                    flags: objInfo.flags(),
                    location: objToString(location) || "",
                    verbsCount: objInfo.verbsCount(),
                    propertiesCount: objInfo.propertiesCount(),
                });
            }

            objectList = result;
            setObjects(result);
        } catch (error) {
            console.error("Failed to load objects:", error);
        } finally {
            setIsLoading(false);
        }
        return objectList;
    }, [authToken]);

    useEffect(() => {
        if (!visible) {
            return;
        }
        let cancelled = false;
        fetchServerFeatures()
            .then((features) => {
                if (!cancelled) {
                    setServerFeatures(features);
                }
            })
            .catch((error) => {
                console.error("Failed to fetch server features:", error);
            });
        return () => {
            cancelled = true;
        };
    }, [visible]);

    // Fetch $ name mappings from #0 properties
    useEffect(() => {
        if (!visible) {
            return;
        }
        let cancelled = false;
        const fetchDollarNames = async () => {
            try {
                // Evaluate MOO expression to get all property names and their values from #0
                const expr = "return {{x, #0.(x)} for x in (properties(#0))};";
                const result = await performEvalFlatBuffer(authToken, expr);

                if (cancelled) return;

                const nameMap = new Map<string, string>();

                // Handle different possible return formats
                if (Array.isArray(result)) {
                    // If it's an array of [key, value] pairs
                    for (const entry of result) {
                        if (Array.isArray(entry) && entry.length === 2) {
                            const [propName, objRef] = entry;
                            if (typeof propName === "string" && isRecord(objRef)) {
                                let objId: string | null = null;
                                if (typeof objRef.oid === "number") {
                                    objId = String(objRef.oid);
                                } else if (typeof objRef.uuid === "string") {
                                    // UUID comes as packed bigint string, need to convert to formatted string
                                    objId = uuObjIdToString(BigInt(objRef.uuid));
                                }
                                if (objId) {
                                    nameMap.set(objId, propName);
                                }
                            }
                        }
                    }
                } else if (isRecord(result)) {
                    // If it's an object/map with property names as keys
                    for (const [propName, objRef] of Object.entries(result)) {
                        let objId: string | null = null;
                        if (isRecord(objRef)) {
                            if (typeof objRef.oid === "number") {
                                objId = String(objRef.oid);
                            } else if (typeof objRef.uuid === "string") {
                                // UUID comes as packed bigint string, need to convert to formatted string
                                objId = uuObjIdToString(BigInt(objRef.uuid));
                            }
                        }
                        if (objId) {
                            nameMap.set(objId, propName);
                        }
                    }
                }

                setDollarNames(nameMap);
            } catch (error) {
                console.error("Failed to fetch $ names from #0:", error);
            }
        };

        fetchDollarNames();

        return () => {
            cancelled = true;
        };
    }, [visible, authToken]);

    const getDollarName = useCallback((objId: string): string | null => {
        return dollarNames.get(objId) || null;
    }, [dollarNames]);

    // Filter and group objects by type
    const filteredObjects = useMemo(() =>
        objects
            .filter(obj => {
                if (!showMineOnly) return true;
                if (!playerObjectRef) return false;
                return normalizeObjectRefForCompare(obj.owner) === playerObjectRef;
            })
            .filter(obj => {
                const filterLower = filter.toLowerCase();
                // Strip leading $ for matching against dollarNames
                const filterNormalized = filterLower.startsWith("$") ? filterLower.slice(1) : filterLower;
                const dollarName = dollarNames.get(obj.obj);
                return obj.name.toLowerCase().includes(filterLower)
                    || obj.obj.includes(filter)
                    || (dollarName && dollarName.toLowerCase().includes(filterNormalized));
            }), [dollarNames, filter, objects, playerObjectRef, showMineOnly]);

    // Separate numeric OIDs from UUIDs
    const numericObjects = useMemo(() =>
        filteredObjects
            .filter(obj => !isUuidObject(obj.obj))
            .sort((a, b) => {
                // Sort by object ID numerically
                const aNum = parseInt(a.obj);
                const bNum = parseInt(b.obj);
                return aNum - bNum;
            }), [filteredObjects]);

    const uuidObjects = useMemo(() =>
        filteredObjects
            .filter(obj => isUuidObject(obj.obj))
            .sort((a, b) => a.obj.localeCompare(b.obj)), [filteredObjects]);

    return {
        objects,
        isLoading,
        loadObjects,
        filter,
        setFilter,
        showMineOnly,
        setShowMineOnly,
        serverFeatures,
        getDollarName,
        numericObjects,
        uuidObjects,
    };
};
