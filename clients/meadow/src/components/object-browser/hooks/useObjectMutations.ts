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

import { useCallback, useState } from "react";
import { performEvalFlatBuffer } from "../../../lib/rpc-fb";
import {
    describeObject,
    formatEvalObjectRef,
    hasEvalError,
    isRecord,
    isTestVerb,
    listToMooLiteral,
    normalizeObjectInput,
    readFileAsText,
} from "../browserUtils";
import {
    AddPropertyFormValues,
    AddVerbFormValues,
    CreateChildFormValues,
    ObjectData,
    PropertyData,
    ReloadObjectFormValues,
    TestResult,
    VerbData,
} from "../types";

export interface UseObjectMutationsArgs {
    authToken: string;
    selectedObject: ObjectData | null;
    /** Current catalog, used to detect freshly created objects. */
    objects: ObjectData[];
    /** Verbs of the selected object, used for test-run operations. */
    verbs: VerbData[];
    /** Loads the full object list; used after mutations to refresh the catalog. */
    loadObjects: () => Promise<ObjectData[]>;
    /** Reloads properties/verbs for an object after structural changes. */
    loadPropertiesAndVerbs: (obj: ObjectData) => Promise<PropertyData[]>;
    /** Selects an object in the browser (post-create/recycle navigation). */
    handleObjectSelect: (obj: ObjectData) => void;
    /** Replaces or clears the persistent browser selection. */
    setSelectedObject: (obj: ObjectData | null) => void;
    /** Clears property/verb selection when the subject disappears. */
    clearSelection: () => void;
    /** Maps a create-dialog object-type selection to its MOO type value. */
    resolveObjectTypeValue: (selection: string) => string;
}

/**
 * Owns the object-browser mutation state machines: create/recycle/rename/
 * flags/add/delete property & verb/reload/dump/test-run operations, including
 * their dialog visibility, submission-in-flight flags, error messages, and
 * transient action feedback.
 */
export const useObjectMutations = ({
    authToken,
    selectedObject,
    objects,
    verbs,
    loadObjects,
    loadPropertiesAndVerbs,
    handleObjectSelect,
    setSelectedObject,
    clearSelection,
    resolveObjectTypeValue,
}: UseObjectMutationsArgs) => {
    const [showCreateDialog, setShowCreateDialog] = useState(false);
    const [showRecycleDialog, setShowRecycleDialog] = useState(false);
    const [showAddPropertyDialog, setShowAddPropertyDialog] = useState(false);
    const [showDeletePropertyDialog, setShowDeletePropertyDialog] = useState(false);
    const [showAddVerbDialog, setShowAddVerbDialog] = useState(false);
    const [showDeleteVerbDialog, setShowDeleteVerbDialog] = useState(false);
    const [showEditFlagsDialog, setShowEditFlagsDialog] = useState(false);
    const [showReloadDialog, setShowReloadDialog] = useState(false);
    const [showTestResultsDialog, setShowTestResultsDialog] = useState(false);

    const [testResults, setTestResults] = useState<TestResult[]>([]);
    const [isRunningTests, setIsRunningTests] = useState(false);

    const [isSubmittingCreate, setIsSubmittingCreate] = useState(false);
    const [isSubmittingRecycle, setIsSubmittingRecycle] = useState(false);
    const [isSubmittingAddProperty, setIsSubmittingAddProperty] = useState(false);
    const [isSubmittingDeleteProperty, setIsSubmittingDeleteProperty] = useState(false);
    const [isSubmittingAddVerb, setIsSubmittingAddVerb] = useState(false);
    const [isSubmittingDeleteVerb, setIsSubmittingDeleteVerb] = useState(false);
    const [isSubmittingEditFlags, setIsSubmittingEditFlags] = useState(false);
    const [isSubmittingReload, setIsSubmittingReload] = useState(false);

    const [createDialogError, setCreateDialogError] = useState<string | null>(null);
    const [recycleDialogError, setRecycleDialogError] = useState<string | null>(null);
    const [addPropertyDialogError, setAddPropertyDialogError] = useState<string | null>(null);
    const [deletePropertyDialogError, setDeletePropertyDialogError] = useState<string | null>(null);
    const [addVerbDialogError, setAddVerbDialogError] = useState<string | null>(null);
    const [deleteVerbDialogError, setDeleteVerbDialogError] = useState<string | null>(null);
    const [editFlagsDialogError, setEditFlagsDialogError] = useState<string | null>(null);
    const [reloadDialogError, setReloadDialogError] = useState<string | null>(null);

    const [actionMessage, setActionMessage] = useState<string | null>(null);
    const [editingName, setEditingName] = useState<string>("");
    const [isSavingName, setIsSavingName] = useState(false);
    const [propertyToDelete, setPropertyToDelete] = useState<PropertyData | null>(null);
    const [verbToDelete, setVerbToDelete] = useState<VerbData | null>(null);

    const handleNameSave = useCallback(async () => {
        if (!selectedObject) return;

        setIsSavingName(true);
        try {
            const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
            if (!objectExpr || objectExpr === "#-1") {
                throw new Error("Invalid object reference");
            }

            // Escape the name string for MOO
            const escapedName = editingName.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
            const expr = `${objectExpr}.name = "${escapedName}"; return ${objectExpr}.name;`;

            await performEvalFlatBuffer(authToken, expr);

            // Update local state
            setSelectedObject({ ...selectedObject, name: editingName });

            // Reload the objects list to reflect the change
            const updated = await loadObjects();
            const updatedObj = updated.find(obj => obj.obj === selectedObject.obj);
            if (updatedObj) {
                setSelectedObject(updatedObj);
                setEditingName(updatedObj.name);
            }

            setActionMessage("Name updated successfully");
            setTimeout(() => setActionMessage(null), 3000);
        } catch (error) {
            console.error("Failed to save name:", error);
            setActionMessage("Failed to update name: " + (error instanceof Error ? error.message : String(error)));
            setTimeout(() => setActionMessage(null), 5000);
        } finally {
            setIsSavingName(false);
        }
    }, [authToken, editingName, loadObjects, selectedObject, setSelectedObject]);

    const handleEditFlagsSubmit = useCallback(async (flags: number) => {
        if (!selectedObject) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr) {
            setEditFlagsDialogError("Unable to determine object reference.");
            return;
        }

        // Extract new flag values
        const newUser = (flags & (1 << 0)) !== 0 ? 1 : 0;
        const newProgrammer = (flags & (1 << 1)) !== 0 ? 1 : 0;
        const newWizard = (flags & (1 << 2)) !== 0 ? 1 : 0;
        const newReadable = (flags & (1 << 4)) !== 0 ? 1 : 0;
        const newWritable = (flags & (1 << 5)) !== 0 ? 1 : 0;
        const newFertile = (flags & (1 << 7)) !== 0 ? 1 : 0;

        // Extract current flag values
        const currentUser = (selectedObject.flags & (1 << 0)) !== 0 ? 1 : 0;
        const currentProgrammer = (selectedObject.flags & (1 << 1)) !== 0 ? 1 : 0;
        const currentWizard = (selectedObject.flags & (1 << 2)) !== 0 ? 1 : 0;
        const currentReadable = (selectedObject.flags & (1 << 4)) !== 0 ? 1 : 0;
        const currentWritable = (selectedObject.flags & (1 << 5)) !== 0 ? 1 : 0;
        const currentFertile = (selectedObject.flags & (1 << 7)) !== 0 ? 1 : 0;

        // Build expression only for changed flags
        const assignments: string[] = [];
        if (newProgrammer !== currentProgrammer) {
            assignments.push(`${objectExpr}.programmer = ${newProgrammer}`);
        }
        if (newWizard !== currentWizard) {
            assignments.push(`${objectExpr}.wizard = ${newWizard}`);
        }
        if (newReadable !== currentReadable) {
            assignments.push(`${objectExpr}.r = ${newReadable}`);
        }
        if (newWritable !== currentWritable) {
            assignments.push(`${objectExpr}.w = ${newWritable}`);
        }
        if (newFertile !== currentFertile) {
            assignments.push(`${objectExpr}.f = ${newFertile}`);
        }

        // If nothing changed, just close the dialog
        if (assignments.length === 0 && newUser === currentUser) {
            setShowEditFlagsDialog(false);
            return;
        }

        setIsSubmittingEditFlags(true);
        setEditFlagsDialogError(null);
        try {
            // Handle player flag change if needed (requires set_player_flag builtin)
            if (newUser !== currentUser) {
                const userExpr = `return set_player_flag(${objectExpr}, ${newUser});`;
                await performEvalFlatBuffer(authToken, userExpr);
            }

            // Handle other flag changes
            if (assignments.length > 0) {
                const expr = assignments.join("; ") + "; return 1;";
                await performEvalFlatBuffer(authToken, expr);
            }

            // Reload the objects list to reflect the change
            const updated = await loadObjects();
            const updatedObj = updated.find(obj => obj.obj === selectedObject.obj);
            if (updatedObj) {
                setSelectedObject(updatedObj);
            }

            setActionMessage("Flags updated successfully");
            setTimeout(() => setActionMessage(null), 3000);
            setShowEditFlagsDialog(false);
        } catch (error) {
            console.error("Failed to update flags:", error);
            setEditFlagsDialogError(
                "Failed to update flags: " + (error instanceof Error ? error.message : String(error)),
            );
        } finally {
            setIsSubmittingEditFlags(false);
        }
    }, [authToken, loadObjects, selectedObject, setSelectedObject]);

    const handleCreateSubmit = useCallback(async (form: CreateChildFormValues) => {
        const parentExpr = normalizeObjectInput(form.parent || "#-1");
        if (!parentExpr) {
            setCreateDialogError("Unable to determine parent object reference.");
            return;
        }

        const ownerExpr = normalizeObjectInput(form.owner || "player") || "player";
        const trimmedInit = form.initArgs.trim();
        const includeType = form.objectType !== "server-default" || trimmedInit.length > 0;
        const typeExpr = resolveObjectTypeValue(form.objectType);

        const args: string[] = [parentExpr, ownerExpr];
        if (includeType) {
            args.push(typeExpr);
        }
        if (trimmedInit.length > 0) {
            args.push(trimmedInit);
        }

        const expr = `return create(${args.join(", ")});`;

        setIsSubmittingCreate(true);
        setCreateDialogError(null);
        try {
            const previousIds = new Set(objects.map(o => o.obj));
            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "create() failed";
                throw new Error(msg);
            }

            // Extract the created object reference from the result
            const createdObjExpr = formatEvalObjectRef(result);
            if (!createdObjExpr) {
                console.error("Could not extract object reference from create() result");
            }

            // Set name if provided
            if (createdObjExpr && form.name.trim().length > 0) {
                const escapedName = form.name.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
                const nameExpr = `${createdObjExpr}.name = "${escapedName}"; return 1;`;
                try {
                    await performEvalFlatBuffer(authToken, nameExpr);
                } catch (error) {
                    console.error("Failed to set name:", error);
                    throw new Error(`Failed to set name: ${error instanceof Error ? error.message : String(error)}`);
                }
            }

            // Set flags if any are set
            if (createdObjExpr && form.flags !== 0) {
                const assignments: string[] = [];
                if ((form.flags & (1 << 1)) !== 0) {
                    assignments.push(`${createdObjExpr}.programmer = 1`);
                }
                if ((form.flags & (1 << 2)) !== 0) {
                    assignments.push(`${createdObjExpr}.wizard = 1`);
                }
                if ((form.flags & (1 << 4)) !== 0) {
                    assignments.push(`${createdObjExpr}.r = 1`);
                }
                if ((form.flags & (1 << 5)) !== 0) {
                    assignments.push(`${createdObjExpr}.w = 1`);
                }
                if ((form.flags & (1 << 7)) !== 0) {
                    assignments.push(`${createdObjExpr}.f = 1`);
                }
                if (assignments.length > 0) {
                    const flagsExpr = assignments.join("; ") + "; return 1;";
                    try {
                        await performEvalFlatBuffer(authToken, flagsExpr);
                    } catch (error) {
                        console.error("Failed to set flags:", error);
                        throw new Error(
                            `Failed to set flags: ${error instanceof Error ? error.message : String(error)}`,
                        );
                    }
                }
            }

            const updated = await loadObjects();
            const newSelection = updated.find(obj => !previousIds.has(obj.obj))
                || (selectedObject ? updated.find(obj => obj.obj === selectedObject.obj) : null);
            if (newSelection && !previousIds.has(newSelection.obj)) {
                handleObjectSelect(newSelection);
            }

            setShowCreateDialog(false);
            if (newSelection && !previousIds.has(newSelection.obj)) {
                setActionMessage(`Created ${describeObject(newSelection)}`);
            } else {
                setActionMessage("Created new object.");
            }
        } catch (error) {
            setCreateDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingCreate(false);
        }
    }, [
        authToken,
        handleObjectSelect,
        loadObjects,
        objects,
        resolveObjectTypeValue,
        selectedObject,
    ]);

    const handleRecycleConfirm = useCallback(async () => {
        if (!selectedObject) return;
        const target = selectedObject;
        const objectExpr = normalizeObjectInput(target.obj ? `#${target.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setRecycleDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingRecycle(true);
        setRecycleDialogError(null);

        try {
            const recycleExpr = `return recycle(${objectExpr});`;
            const result = await performEvalFlatBuffer(authToken, recycleExpr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "recycle() failed";
                throw new Error(msg);
            }
            if (typeof result === "string") {
                const trimmed = result.trim();
                if (trimmed.length > 0) {
                    throw new Error(trimmed);
                }
            }

            const updated = await loadObjects();
            setShowRecycleDialog(false);

            const parentId = target.parent;
            let navigated = false;
            if (parentId) {
                const parentObj = updated.find(obj => obj.obj === parentId);
                if (parentObj) {
                    handleObjectSelect(parentObj);
                    navigated = true;
                }
            }
            if (!navigated) {
                setSelectedObject(null);
                clearSelection();
            }

            setActionMessage(`Recycled ${describeObject(target)}`);
        } catch (error) {
            setRecycleDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingRecycle(false);
        }
    }, [authToken, clearSelection, handleObjectSelect, loadObjects, selectedObject, setSelectedObject]);

    const handleDumpObject = useCallback(async () => {
        if (!selectedObject) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setActionMessage("Unable to determine object reference.");
            return;
        }

        try {
            const expr = `return dump_object(${objectExpr});`;
            const result = await performEvalFlatBuffer(authToken, expr);

            // Check for error
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "dump_object() failed";
                throw new Error(msg);
            }

            // Result should be an array of strings
            if (!Array.isArray(result)) {
                throw new Error("dump_object() returned unexpected result");
            }

            // Join the lines with newlines
            const content = result.join("\n");

            // Create a blob and download it
            const blob = new Blob([content], { type: "text/plain" });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = `${objectExpr.replace("#", "")}.moo`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);

            setActionMessage(`Dumped ${describeObject(selectedObject)} to file`);
            setTimeout(() => setActionMessage(null), 3000);
        } catch (error) {
            console.error("Failed to dump object:", error);
            setActionMessage(`Failed to dump object: ${error instanceof Error ? error.message : String(error)}`);
            setTimeout(() => setActionMessage(null), 5000);
        }
    }, [authToken, selectedObject]);

    const handleReloadObjectSubmit = useCallback(async (form: ReloadObjectFormValues) => {
        if (!selectedObject) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setReloadDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingReload(true);
        setReloadDialogError(null);

        try {
            const objdefText = await readFileAsText(form.objdefFile);
            const objdefLines = objdefText.split(/\r?\n/);
            const objdefLiteral = listToMooLiteral(objdefLines);

            let expr = `return reload_object(${objdefLiteral}, [], ${objectExpr});`;

            if (form.constantsFile) {
                const constantsText = await readFileAsText(form.constantsFile);
                const constantsLines = constantsText.split(/\r?\n/);
                const constantsLiteral = listToMooLiteral(constantsLines);
                expr = `constants = parse_objdef_constants(${constantsLiteral}); `
                    + `return reload_object(${objdefLiteral}, constants, ${objectExpr});`;
            }

            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "reload_object() failed";
                throw new Error(msg);
            }

            const updatedObjects = await loadObjects();
            const updated = updatedObjects.find(obj => obj.obj === selectedObject.obj);
            if (updated) {
                setSelectedObject(updated);
                setEditingName(updated.name);
                await loadPropertiesAndVerbs(updated);
            }

            setShowReloadDialog(false);
            setActionMessage(`Reloaded ${describeObject(selectedObject)}`);
            setTimeout(() => setActionMessage(null), 3000);
        } catch (error) {
            setReloadDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingReload(false);
        }
    }, [authToken, loadObjects, loadPropertiesAndVerbs, selectedObject, setSelectedObject]);

    const handleAddPropertySubmit = useCallback(async (form: AddPropertyFormValues) => {
        if (!selectedObject) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setAddPropertyDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingAddProperty(true);
        setAddPropertyDialogError(null);

        try {
            // Escape the property name and value for MOO
            const escapedName = form.name.trim();
            if (!escapedName) {
                throw new Error("Property name cannot be empty");
            }

            const ownerExpr = normalizeObjectInput(form.owner || "player") || "player";
            const perms = form.perms.trim() || "rw";

            // Validate perms string
            if (!/^[rwc]*$/.test(perms)) {
                throw new Error("Invalid permissions. Use r, w, and/or c");
            }

            // Build the add_property call
            // add_property(obj, 'name, value, {owner, "perms"})
            const expr =
                `return add_property(${objectExpr}, '${escapedName}, ${form.value}, {${ownerExpr}, "${perms}"});`;

            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "add_property() failed";
                throw new Error(msg);
            }

            // Reload properties list
            await loadPropertiesAndVerbs(selectedObject);

            setShowAddPropertyDialog(false);
            setActionMessage(`Added property "${escapedName}" to ${describeObject(selectedObject)}`);
        } catch (error) {
            setAddPropertyDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingAddProperty(false);
        }
    }, [authToken, loadPropertiesAndVerbs, selectedObject]);

    const handleAddVerbSubmit = useCallback(async (form: AddVerbFormValues) => {
        if (!selectedObject) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setAddVerbDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingAddVerb(true);
        setAddVerbDialogError(null);

        try {
            // Validate and normalize verb names
            const verbNames = form.names.trim();
            if (!verbNames) {
                throw new Error("Verb names cannot be empty");
            }

            const ownerExpr = normalizeObjectInput(form.owner || "player") || "player";
            const perms = form.perms.trim() || "rxd";

            // Validate perms string for verbs (r, w, x, d)
            if (!/^[rwxd]*$/.test(perms)) {
                throw new Error("Invalid permissions. Use r, w, x, and/or d");
            }

            // Normalize argument specs
            const dobj = form.dobj.trim() || "this";
            const prep = form.prep.trim() || "none";
            const iobj = form.iobj.trim() || "none";

            // Build the add_verb call
            // add_verb(obj, {owner, "perms", "names"}, {"dobj", "prep", "iobj"})
            const expr =
                `return add_verb(${objectExpr}, {${ownerExpr}, "${perms}", "${verbNames}"}, {"${dobj}", "${prep}", "${iobj}"});`;

            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "add_verb() failed";
                throw new Error(msg);
            }

            // Reload verbs list
            await loadPropertiesAndVerbs(selectedObject);

            setShowAddVerbDialog(false);
            setActionMessage(`Added verb "${verbNames}" to ${describeObject(selectedObject)}`);
        } catch (error) {
            setAddVerbDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingAddVerb(false);
        }
    }, [authToken, loadPropertiesAndVerbs, selectedObject]);

    const handleDeleteVerbConfirm = useCallback(async () => {
        if (!selectedObject || !verbToDelete) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setDeleteVerbDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingDeleteVerb(true);
        setDeleteVerbDialogError(null);

        try {
            // delete_verb(obj, verbname)
            const verbName = verbToDelete.names[0];
            const expr = `return delete_verb(${objectExpr}, "${verbName}");`;

            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "delete_verb() failed";
                throw new Error(msg);
            }

            // Reload verbs list
            await loadPropertiesAndVerbs(selectedObject);

            setShowDeleteVerbDialog(false);
            setVerbToDelete(null);
            clearSelection();

            setActionMessage(`Removed verb "${verbName}" from ${describeObject(selectedObject)}`);
        } catch (error) {
            setDeleteVerbDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingDeleteVerb(false);
        }
    }, [authToken, clearSelection, loadPropertiesAndVerbs, selectedObject, verbToDelete]);

    const handleDeletePropertyConfirm = useCallback(async () => {
        if (!selectedObject || !propertyToDelete) return;

        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr || objectExpr === "#-1") {
            setDeletePropertyDialogError("Unable to determine object reference.");
            return;
        }

        setIsSubmittingDeleteProperty(true);
        setDeletePropertyDialogError(null);

        try {
            // delete_property(obj, 'name)
            const expr = `return delete_property(${objectExpr}, '${propertyToDelete.name});`;

            const result = await performEvalFlatBuffer(authToken, expr);
            if (hasEvalError(result)) {
                const msg = result.error?.msg ?? "delete_property() failed";
                throw new Error(msg);
            }

            // Reload properties list
            await loadPropertiesAndVerbs(selectedObject);

            setShowDeletePropertyDialog(false);
            setPropertyToDelete(null);
            clearSelection();

            setActionMessage(`Deleted property "${propertyToDelete.name}" from ${describeObject(selectedObject)}`);
        } catch (error) {
            setDeletePropertyDialogError(error instanceof Error ? error.message : String(error));
        } finally {
            setIsSubmittingDeleteProperty(false);
        }
    }, [authToken, clearSelection, loadPropertiesAndVerbs, propertyToDelete, selectedObject]);

    const handleRunTest = useCallback(async (verb: VerbData) => {
        if (!selectedObject) return;
        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr) return;

        // Use the first name for calling, or the one starting with test_
        const verbName = verb.names.find(n => isTestVerb(n)) || verb.names[0];
        // For now, assume test verbs don't take arguments or we pass none
        const expr = `return ${objectExpr}:${verbName}();`;

        setActionMessage(`Running test ${verbName}...`);
        try {
            const result = await performEvalFlatBuffer(authToken, expr);
            let success = true;
            let resultStr = "";
            let errorStr = undefined;

            if (hasEvalError(result)) {
                success = false;
                errorStr = result.error?.msg ?? "Test failed";
            } else if (result !== undefined) {
                // Try to format result nicely
                const objectRef = formatEvalObjectRef(result);
                if (objectRef) {
                    resultStr = objectRef;
                } else if (isRecord(result)) {
                    resultStr = JSON.stringify(result);
                } else {
                    resultStr = String(result);
                }
            }

            setTestResults([{
                verb: verbName,
                location: verb.location,
                success,
                result: resultStr,
                error: errorStr,
            }]);
            setShowTestResultsDialog(true);
            setActionMessage(null);
        } catch (error) {
            setTestResults([{
                verb: verbName,
                location: verb.location,
                success: false,
                error: error instanceof Error ? error.message : String(error),
            }]);
            setShowTestResultsDialog(true);
            setActionMessage(null);
        }
    }, [authToken, selectedObject]);

    const handleRunAllTests = useCallback(async () => {
        if (!selectedObject) return;
        const objectExpr = normalizeObjectInput(selectedObject.obj ? `#${selectedObject.obj}` : "");
        if (!objectExpr) return;

        // Find all test verbs for this object (excluding inherited ones)
        const testVerbs = verbs.filter(v => v.names.some(n => isTestVerb(n)) && v.location === selectedObject.obj);

        if (testVerbs.length === 0) {
            setActionMessage("No test verbs found.");
            setTimeout(() => setActionMessage(null), 3000);
            return;
        }

        setIsRunningTests(true);
        setActionMessage(`Running ${testVerbs.length} tests...`);
        const results: TestResult[] = [];

        for (const verb of testVerbs) {
            const verbName = verb.names.find(n => isTestVerb(n)) || verb.names[0];
            const expr = `return ${objectExpr}:${verbName}();`;

            try {
                const result = await performEvalFlatBuffer(authToken, expr);
                let success = true;
                let resultStr = "";
                let errorStr = undefined;

                if (hasEvalError(result)) {
                    success = false;
                    errorStr = result.error?.msg ?? "Test failed";
                } else {
                    const objectRef = formatEvalObjectRef(result);
                    if (objectRef) {
                        resultStr = objectRef;
                    } else if (isRecord(result)) {
                        resultStr = JSON.stringify(result);
                    } else {
                        resultStr = String(result);
                    }
                }
                results.push({
                    verb: verbName,
                    location: verb.location,
                    success,
                    result: resultStr,
                    error: errorStr,
                });
            } catch (error) {
                results.push({
                    verb: verbName,
                    location: verb.location,
                    success: false,
                    error: error instanceof Error ? error.message : String(error),
                });
            }
        }

        setTestResults(results);
        setShowTestResultsDialog(true);
        setIsRunningTests(false);
        setActionMessage(null);
    }, [authToken, selectedObject, verbs]);

    return {
        showCreateDialog,
        setShowCreateDialog,
        showRecycleDialog,
        setShowRecycleDialog,
        showAddPropertyDialog,
        setShowAddPropertyDialog,
        showDeletePropertyDialog,
        setShowDeletePropertyDialog,
        showAddVerbDialog,
        setShowAddVerbDialog,
        showDeleteVerbDialog,
        setShowDeleteVerbDialog,
        showEditFlagsDialog,
        setShowEditFlagsDialog,
        showReloadDialog,
        setShowReloadDialog,
        showTestResultsDialog,
        setShowTestResultsDialog,
        testResults,
        isRunningTests,
        isSubmittingCreate,
        isSubmittingRecycle,
        isSubmittingAddProperty,
        isSubmittingDeleteProperty,
        isSubmittingAddVerb,
        isSubmittingDeleteVerb,
        isSubmittingEditFlags,
        isSubmittingReload,
        createDialogError,
        setCreateDialogError,
        recycleDialogError,
        setRecycleDialogError,
        addPropertyDialogError,
        setAddPropertyDialogError,
        deletePropertyDialogError,
        setDeletePropertyDialogError,
        addVerbDialogError,
        setAddVerbDialogError,
        deleteVerbDialogError,
        setDeleteVerbDialogError,
        editFlagsDialogError,
        setEditFlagsDialogError,
        reloadDialogError,
        setReloadDialogError,
        actionMessage,
        setActionMessage,
        editingName,
        setEditingName,
        isSavingName,
        propertyToDelete,
        setPropertyToDelete,
        verbToDelete,
        setVerbToDelete,
        handleNameSave,
        handleEditFlagsSubmit,
        handleCreateSubmit,
        handleRecycleConfirm,
        handleDumpObject,
        handleReloadObjectSubmit,
        handleAddPropertySubmit,
        handleAddVerbSubmit,
        handleDeleteVerbConfirm,
        handleDeletePropertyConfirm,
        handleRunTest,
        handleRunAllTests,
    };
};
