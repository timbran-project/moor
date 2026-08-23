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

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePersistentState } from "../../../hooks/usePersistentState";
import { MoorVar } from "../../../lib/MoorVar";
import {
    getPropertiesFlatBuffer,
    getPropertyFlatBuffer,
    getVerbCodeFlatBuffer,
    getVerbsFlatBuffer,
} from "../../../lib/rpc-fb";
import { objToString, stringToCurie } from "../../../lib/var";
import {
    deserializeEditorType,
    deserializePropertyName,
    deserializeStoredString,
    deserializeVerbIndex,
    isMethodVerb,
    isTestVerb,
    persistNonNull,
} from "../browserUtils";
import { ObjectData, PropertyData, VerbData } from "../types";

export interface UseObjectMembersArgs {
    authToken: string;
    selectedObject: ObjectData | null;
}

/**
 * Owns the selected object's properties and verbs: fetching member lists,
 * property values and verb code on selection, inherited-member grouping and
 * filtering, override/duplicate labeling, and editor-selection restoration
 * across browser remounts.
 */
export const useObjectMembers = ({ authToken, selectedObject }: UseObjectMembersArgs) => {
    const [properties, setProperties] = useState<PropertyData[]>([]);
    const [verbs, setVerbs] = useState<VerbData[]>([]);

    // Editor state
    const [selectedProperty, setSelectedProperty] = useState<PropertyData | null>(null);
    const [selectedVerb, setSelectedVerb] = useState<VerbData | null>(null);
    const [verbCode, setVerbCode] = useState<string>("");
    const [editorVisible, setEditorVisible] = useState(false);

    // Track what type of editor was open (for restoration)
    const [lastEditorType, setLastEditorType] = usePersistentState<"property" | "verb" | null>(
        "moor-object-browser-editor-type",
        null,
        {
            shouldPersist: persistNonNull,
            deserialize: deserializeEditorType,
        },
    );
    const [lastPropertyName, setLastPropertyName] = usePersistentState<string | null>(
        "moor-object-browser-property-name",
        null,
        {
            shouldPersist: persistNonNull,
            deserialize: deserializePropertyName,
        },
    );
    const [lastVerbIndex, setLastVerbIndex] = usePersistentState<number | null>(
        "moor-object-browser-verb-index",
        null,
        {
            shouldPersist: persistNonNull,
            deserialize: deserializeVerbIndex,
        },
    );
    const [lastVerbLocation, setLastVerbLocation] = usePersistentState<string | null>(
        "moor-object-browser-verb-location",
        null,
        {
            shouldPersist: persistNonNull,
            deserialize: deserializeStoredString,
        },
    );

    const [propertyFilter, setPropertyFilter] = useState("");
    const [verbFilter, setVerbFilter] = useState("");

    const [showInheritedProperties, setShowInheritedProperties] = usePersistentState(
        "moor-object-browser-show-inherited-properties",
        true,
    );
    const [showInheritedVerbs, setShowInheritedVerbs] = usePersistentState(
        "moor-object-browser-show-inherited-verbs",
        true,
    );
    const [showTests, setShowTests] = usePersistentState(
        "moor-object-browser-show-tests",
        true,
    );
    const [showCommands, setShowCommands] = usePersistentState(
        "moor-object-browser-show-commands",
        true,
    );
    const [showMethods, setShowMethods] = usePersistentState(
        "moor-object-browser-show-methods",
        true,
    );

    /** Clears the embedded editor selection. */
    const clearSelection = useCallback(() => {
        setSelectedProperty(null);
        setSelectedVerb(null);
        setEditorVisible(false);
    }, []);

    /**
     * Fetches properties and verbs for an object, replacing local state.
     * Returns the loaded property list for callers that restore selections.
     */
    const loadPropertiesAndVerbs = useCallback(async (obj: ObjectData): Promise<PropertyData[]> => {
        try {
            const objectCurie = stringToCurie(obj.obj);
            const propsReply = await getPropertiesFlatBuffer(authToken, objectCurie, true);
            const propsLength = propsReply.propertiesLength();
            const propList: PropertyData[] = [];

            for (let i = 0; i < propsLength; i++) {
                const propInfo = propsReply.properties(i);
                if (!propInfo) continue;

                const nameSymbol = propInfo.name();
                const definer = propInfo.definer();
                const location = propInfo.location();
                const owner = propInfo.owner();

                propList.push({
                    name: nameSymbol?.value() || "",
                    value: null,
                    owner: objToString(owner) || "",
                    definer: objToString(definer) || "",
                    location: objToString(location) || "",
                    readable: propInfo.r(),
                    writable: propInfo.w(),
                    chown: propInfo.chown(),
                });
            }

            setProperties(propList);

            const verbsReply = await getVerbsFlatBuffer(authToken, objectCurie, true);
            const verbsLength = verbsReply.verbsLength();
            const verbList: VerbData[] = [];
            const locationIndices = new Map<string, number>();

            for (let i = 0; i < verbsLength; i++) {
                const verbInfo = verbsReply.verbs(i);
                if (!verbInfo) continue;

                const namesLength = verbInfo.namesLength();
                const names: string[] = [];
                for (let j = 0; j < namesLength; j++) {
                    const nameSymbol = verbInfo.names(j);
                    const name = nameSymbol?.value();
                    if (name) {
                        names.push(name);
                    }
                }

                const location = verbInfo.location();
                const owner = verbInfo.owner();
                const locationStr = objToString(location) || "";

                // Track index within each location
                if (!locationIndices.has(locationStr)) {
                    locationIndices.set(locationStr, 0);
                }
                const indexInLocation = locationIndices.get(locationStr)!;
                locationIndices.set(locationStr, indexInLocation + 1);

                // arg_spec is a vector of 3 symbols: [dobj, prep, iobj]
                const argSpecLength = verbInfo.argSpecLength();
                const dobj = argSpecLength > 0 ? verbInfo.argSpec(0)?.value() || "none" : "none";
                const prep = argSpecLength > 1 ? verbInfo.argSpec(1)?.value() || "none" : "none";
                const iobj = argSpecLength > 2 ? verbInfo.argSpec(2)?.value() || "none" : "none";

                verbList.push({
                    names,
                    owner: objToString(owner) || "",
                    location: locationStr,
                    readable: verbInfo.r(),
                    writable: verbInfo.w(),
                    executable: verbInfo.x(),
                    debug: verbInfo.d(),
                    dobj,
                    prep,
                    iobj,
                    indexInLocation,
                });
            }

            setVerbs(verbList);
            return propList;
        } catch (error) {
            console.error("Failed to load properties/verbs:", error);
            return []; // Return empty array on error
        }
    }, [authToken]);

    const handlePropertySelect = useCallback(async (prop: PropertyData) => {
        setSelectedProperty(prop);
        setSelectedVerb(null);
        setEditorVisible(true);

        // Fetch through the selected object so inherited properties show the closest override.
        if (!selectedObject) return;

        try {
            const objectCurie = stringToCurie(selectedObject.obj);
            const propValue = await getPropertyFlatBuffer(authToken, objectCurie, prop.name);
            const propInfo = propValue.propInfo();
            const owner = propInfo?.owner();
            const definer = propInfo?.definer();
            const location = propInfo?.location();
            const varValue = propValue.value();
            if (varValue) {
                const moorVar = new MoorVar(varValue);
                const jsValue = moorVar.toJS();
                // Update the property with both JS value and MoorVar
                setSelectedProperty({
                    ...prop,
                    value: jsValue,
                    moorVar,
                    owner: objToString(owner) || prop.owner,
                    definer: objToString(definer) || prop.definer,
                    location: objToString(location) || prop.location,
                    readable: propInfo?.r() ?? prop.readable,
                    writable: propInfo?.w() ?? prop.writable,
                    chown: propInfo?.chown() ?? prop.chown,
                });
            }
        } catch (error) {
            console.error("Failed to load property value:", error);
        }
    }, [authToken, selectedObject]);

    const handleVerbSelect = useCallback(async (verb: VerbData) => {
        setSelectedVerb(verb);
        setSelectedProperty(null);
        setEditorVisible(true);

        // Fetch verb code from the object where the verb is defined (verb.location)
        try {
            const objectCurie = stringToCurie(verb.location);
            const verbValue = await getVerbCodeFlatBuffer(authToken, objectCurie, verb.names[0]);
            const codeLength = verbValue.codeLength();
            const lines: string[] = [];
            for (let i = 0; i < codeLength; i++) {
                const line = verbValue.code(i);
                if (line) lines.push(line);
            }
            setVerbCode(lines.join("\n"));
        } catch (error) {
            console.error("Failed to load verb code:", error);
            setVerbCode("// Failed to load verb code");
        }
    }, [authToken]);

    // Sync selectedVerb when verbs array updates (e.g., after metadata save)
    useEffect(() => {
        if (selectedVerb) {
            const updatedVerb = verbs.find(v =>
                v.location === selectedVerb.location && v.indexInLocation === selectedVerb.indexInLocation
            );
            if (updatedVerb) {
                setSelectedVerb(updatedVerb);
            }
        }
    }, [verbs]); // eslint-disable-line react-hooks/exhaustive-deps

    // Restore verb selection when verbs are loaded (after component remount)
    useEffect(() => {
        if (
            lastEditorType === "verb" && lastVerbIndex !== null && lastVerbLocation !== null && verbs.length > 0
            && !selectedVerb && selectedObject
        ) {
            const verb = verbs.find(v => v.location === lastVerbLocation && v.indexInLocation === lastVerbIndex);
            if (verb) {
                handleVerbSelect(verb);
                // Clear the restoration flags so we don't keep re-selecting
                setLastEditorType(null);
                setLastVerbIndex(null);
                setLastVerbLocation(null);
            }
        }
    }, [
        verbs,
        lastEditorType,
        lastVerbIndex,
        lastVerbLocation,
        selectedVerb,
        selectedObject,
        handleVerbSelect,
        setLastEditorType,
        setLastVerbIndex,
        setLastVerbLocation,
    ]);

    useEffect(() => {
        if (selectedProperty && editorVisible) {
            setLastEditorType("property");
            setLastPropertyName(selectedProperty.name);
        }
    }, [editorVisible, selectedProperty, setLastEditorType, setLastPropertyName]);

    useEffect(() => {
        if (selectedVerb && editorVisible && selectedVerb.indexInLocation !== undefined) {
            setLastEditorType("verb");
            setLastVerbIndex(selectedVerb.indexInLocation);
            setLastVerbLocation(selectedVerb.location);
        }
    }, [editorVisible, selectedVerb, setLastEditorType, setLastVerbIndex, setLastVerbLocation]);

    // Track previous editorVisible to detect transitions
    const prevEditorVisibleRef = useRef<boolean | undefined>(undefined);
    useEffect(() => {
        const prevVisible = prevEditorVisibleRef.current;
        prevEditorVisibleRef.current = editorVisible;

        // Only clear restoration state when editor closes (true -> false transition)
        // Don't clear on initial mount when editorVisible is false
        if (prevVisible === true && !editorVisible) {
            setLastEditorType(null);
            setLastPropertyName(null);
            setLastVerbIndex(null);
            setLastVerbLocation(null);
        }
    }, [editorVisible, setLastEditorType, setLastPropertyName, setLastVerbIndex, setLastVerbLocation]);

    // Group properties by location.
    const groupedProperties = useMemo(() => {
        const filterLower = propertyFilter.toLowerCase();
        const filteredProps = properties.filter(prop => prop.name.toLowerCase().includes(filterLower));

        // Track the order locations appear in the original array (API order = ancestor order)
        const locationOrder = new Map<string, number>();
        for (const prop of properties) {
            if (!locationOrder.has(prop.location)) {
                locationOrder.set(prop.location, locationOrder.size);
            }
        }

        const groups = new Map<string, PropertyData[]>();
        for (const prop of filteredProps) {
            const location = prop.location;
            if (!groups.has(location)) {
                groups.set(location, []);
            }
            groups.get(location)!.push(prop);
        }
        let entries = Array.from(groups.entries()).sort((a, b) => {
            // Current object always first
            if (selectedObject && a[0] === selectedObject.obj) return -1;
            if (selectedObject && b[0] === selectedObject.obj) return 1;
            // Otherwise preserve API order (nearest ancestor first)
            const orderA = locationOrder.get(a[0]) ?? Infinity;
            const orderB = locationOrder.get(b[0]) ?? Infinity;
            return orderA - orderB;
        });
        if (!showInheritedProperties && selectedObject) {
            const currentId = selectedObject.obj;
            entries = entries.filter(([location]) => location === currentId);
        }
        return entries;
    }, [properties, selectedObject, propertyFilter, showInheritedProperties]);

    // Group verbs by location
    const groupedVerbs = useMemo(() => {
        const filterLower = verbFilter.toLowerCase();
        let filteredVerbs = verbs.filter(verb => verb.names.some(name => name.toLowerCase().includes(filterLower)));

        if (!showTests) {
            filteredVerbs = filteredVerbs.filter(verb => !verb.names.some(name => isTestVerb(name)));
        }
        if (!showCommands) {
            filteredVerbs = filteredVerbs.filter(verb => isMethodVerb(verb));
        }
        if (!showMethods) {
            filteredVerbs = filteredVerbs.filter(verb => !isMethodVerb(verb));
        }

        // Track the order locations appear in the original array (API order = ancestor order)
        const locationOrder = new Map<string, number>();
        for (const verb of verbs) {
            if (!locationOrder.has(verb.location)) {
                locationOrder.set(verb.location, locationOrder.size);
            }
        }

        const groups = new Map<string, VerbData[]>();
        for (const verb of filteredVerbs) {
            const location = verb.location;
            if (!groups.has(location)) {
                groups.set(location, []);
            }
            groups.get(location)!.push(verb);
        }

        let entries = Array.from(groups.entries()).sort((a, b) => {
            // Current object always first
            if (selectedObject && a[0] === selectedObject.obj) return -1;
            if (selectedObject && b[0] === selectedObject.obj) return 1;
            // Otherwise preserve API order (nearest ancestor first)
            const orderA = locationOrder.get(a[0]) ?? Infinity;
            const orderB = locationOrder.get(b[0]) ?? Infinity;
            return orderA - orderB;
        });
        if (!showInheritedVerbs && selectedObject) {
            const currentId = selectedObject.obj;
            entries = entries.filter(([location]) => location === currentId);
        }
        return entries;
    }, [verbs, selectedObject, verbFilter, showInheritedVerbs, showTests, showCommands, showMethods]);

    // Track which verbs are overridden or have duplicate names
    const verbLabels = useMemo(() => {
        const overridden = new Set<string>(); // Set of "location:index" keys for overridden verbs
        const duplicateNames = new Set<string>(); // Set of "location:index" keys for duplicate names
        const seenNamesGlobal = new Set<string>(); // Verb names seen across all locations

        for (const [location, verbList] of groupedVerbs) {
            const seenNamesInLocation = new Map<string, number>(); // Track name counts per location

            for (const verb of verbList) {
                const verbName = verb.names[0];
                const key = `${location}:${verb.indexInLocation}`;

                // Check if this is a duplicate name within the same location
                if (seenNamesInLocation.has(verbName)) {
                    duplicateNames.add(key);
                } else {
                    seenNamesInLocation.set(verbName, 1);
                }

                // Check if this verb name was seen in a more-specific location (overridden)
                if (seenNamesGlobal.has(verbName)) {
                    overridden.add(key);
                } else {
                    seenNamesGlobal.add(verbName);
                }
            }
        }

        return { overridden, duplicateNames };
    }, [groupedVerbs]);

    return {
        properties,
        verbs,
        loadPropertiesAndVerbs,
        selectedProperty,
        setSelectedProperty,
        selectedVerb,
        setSelectedVerb,
        verbCode,
        editorVisible,
        setEditorVisible,
        clearSelection,
        handlePropertySelect,
        handleVerbSelect,
        propertyFilter,
        setPropertyFilter,
        verbFilter,
        setVerbFilter,
        showInheritedProperties,
        setShowInheritedProperties,
        showInheritedVerbs,
        setShowInheritedVerbs,
        showTests,
        setShowTests,
        showCommands,
        setShowCommands,
        showMethods,
        setShowMethods,
        groupedProperties,
        groupedVerbs,
        verbLabels,
        restoration: {
            lastEditorType,
            lastPropertyName,
            clearRestorationForProperty: () => {
                setLastEditorType(null);
                setLastPropertyName(null);
            },
            clearAllRestoration: () => {
                setLastEditorType(null);
                setLastVerbIndex(null);
                setLastVerbLocation(null);
            },
        },
    };
};
