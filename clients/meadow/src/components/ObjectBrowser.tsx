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

import React, { useCallback, useEffect, useRef, useState } from "react";
import { useAuthContext } from "../context/AuthContext";
import { useMediaQuery } from "../hooks/useMediaQuery.js";
import { usePersistentState } from "../hooks/usePersistentState.js";
import { useTouchDevice } from "../hooks/useTouchDevice.js";
import { stringToCurie } from "../lib/var.js";
import { EditorWindow, useTitleBarDrag } from "./EditorWindow.js";
import {
    clampFontSize,
    describeObject,
    deserializeFontSize,
    formatObjectFlags,
    isTestVerb,
    MAX_FONT_SIZE,
    MIN_FONT_SIZE,
    normalizeObjectInput,
    normalizeObjectRef,
    normalizeObjectRefForCompare,
    persistNonNull,
} from "./object-browser/browserUtils";
import { AddPropertyDialog } from "./object-browser/dialogs/AddPropertyDialog";
import { AddVerbDialog } from "./object-browser/dialogs/AddVerbDialog";
import { CreateChildDialog } from "./object-browser/dialogs/CreateChildDialog";
import { DeletePropertyDialog } from "./object-browser/dialogs/DeletePropertyDialog";
import { DeleteVerbDialog } from "./object-browser/dialogs/DeleteVerbDialog";
import { EditFlagsDialog } from "./object-browser/dialogs/EditFlagsDialog";
import { RecycleObjectDialog } from "./object-browser/dialogs/RecycleObjectDialog";
import { ReloadObjectDialog } from "./object-browser/dialogs/ReloadObjectDialog";
import { TestResultsDialog } from "./object-browser/dialogs/TestResultsDialog";
import { useObjectCatalog } from "./object-browser/hooks/useObjectCatalog";
import { useObjectMembers } from "./object-browser/hooks/useObjectMembers";
import { useObjectMutations } from "./object-browser/hooks/useObjectMutations";
import { ObjectInfoEditor } from "./object-browser/ObjectInfoEditor";
import { ObjectData } from "./object-browser/types";
import { PropertyValueEditor } from "./PropertyValueEditor.js";
import { VerbEditor } from "./VerbEditor.js";

interface ObjectBrowserProps {
    visible: boolean;
    onClose: () => void;
    authToken: string;
    splitMode?: boolean;
    onSplitDrag?: (e: React.MouseEvent) => void;
    onSplitTouchStart?: (e: React.TouchEvent) => void;
    onToggleSplitMode?: () => void;
    isInSplitMode?: boolean;
    focusedObjectCurie?: string; // Focus on specific object when presentation opens it
    onOpenVerbInEditor?: (title: string, objectCurie: string, verbName: string, content: string) => void;
}

/**
 * Smalltalk-style object browser shell. Owns only browser-level chrome and
 * layout (panes, tab navigation, font size, split dragging, persistent object
 * selection) and delegates domain behavior to the catalog, members, and
 * mutations hooks plus the extracted dialog modules.
 */
export const ObjectBrowser: React.FC<ObjectBrowserProps> = ({
    visible,
    onClose,
    authToken,
    splitMode = false,
    onSplitDrag,
    onSplitTouchStart,
    onToggleSplitMode,
    isInSplitMode = false,
    focusedObjectCurie,
    onOpenVerbInEditor,
}) => {
    const { authState } = useAuthContext();
    const playerObjectRef = normalizeObjectRefForCompare(authState.player?.oid);
    const isMobile = useMediaQuery("(max-width: 768px)");
    const isTouchDevice = useTouchDevice();
    // Use tabbed layout on touch devices with mobile-sized screens
    // The split pane with draggable divider doesn't work well on touch
    const useTabLayout = isMobile && isTouchDevice;
    const [activeTab, setActiveTab] = useState<"objects" | "properties" | "verbs">("objects");
    const [isFullscreen, setIsFullscreen] = useState(useTabLayout); // Start fullscreen on mobile
    const [selectedObject, setSelectedObject] = usePersistentState<ObjectData | null>(
        "moor-object-browser-selected-object",
        null,
        { shouldPersist: persistNonNull },
    );
    const containerRef = useRef<HTMLDivElement | null>(null);
    const objectsPaneRef = useRef<HTMLDivElement | null>(null);

    const [browserPaneHeight, setBrowserPaneHeight] = useState(350); // Fixed pixel height for browser pane
    const [isSplitDragging, setIsSplitDragging] = useState(false);
    const [fontSize, setFontSize] = usePersistentState(
        "moor-object-browser-font-size",
        () => (isMobile ? 14 : 12),
        { deserialize: deserializeFontSize },
    );

    const decreaseFontSize = useCallback(() => {
        setFontSize(prev => clampFontSize(prev - 1));
    }, [setFontSize]);
    const increaseFontSize = useCallback(() => {
        setFontSize(prev => clampFontSize(prev + 1));
    }, [setFontSize]);

    // Object list domain
    const catalog = useObjectCatalog({ authToken, visible, playerObjectRef });
    const {
        objects,
        isLoading,
        loadObjects,
        filter,
        setFilter,
        showMineOnly,
        setShowMineOnly,
        getDollarName,
        numericObjects,
        uuidObjects,
    } = catalog;

    // Properties/verbs domain
    const members = useObjectMembers({ authToken, selectedObject });
    const {
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
        restoration,
    } = members;

    // Stable indirection so the mutations hook can trigger object selection
    // without a circular hook dependency
    const selectObjectRef = useRef<(obj: ObjectData) => void>(() => {});

    const defaultObjectTypeValue = useCallback((): string => catalog.serverFeatures?.useUuobjids ? "2" : "0", [
        catalog.serverFeatures,
    ]);

    const resolveObjectTypeValue = useCallback((selection: string): string => {
        switch (selection) {
            case "numbered":
                return "0";
            case "uuid":
                return "2";
            case "anonymous":
                return "1";
            case "server-default":
            default:
                return defaultObjectTypeValue();
        }
    }, [defaultObjectTypeValue]);

    // Mutation/dialog domain
    const mutations = useObjectMutations({
        authToken,
        selectedObject,
        objects,
        verbs,
        loadObjects,
        loadPropertiesAndVerbs,
        handleObjectSelect: useCallback((obj: ObjectData) => selectObjectRef.current(obj), []),
        setSelectedObject,
        clearSelection,
        resolveObjectTypeValue,
    });
    const {
        setShowCreateDialog,
        setShowRecycleDialog,
        setShowAddPropertyDialog,
        setShowDeletePropertyDialog,
        setShowReloadDialog,
        setPropertyToDelete,
        setVerbToDelete,
        actionMessage,
        setActionMessage,
        editingName,
        setEditingName,
    } = mutations;

    const handleObjectSelect = useCallback((obj: ObjectData) => {
        setActionMessage(null);
        setSelectedObject(obj);
        setEditingName(obj.name);
        clearSelection();
        loadPropertiesAndVerbs(obj);
    }, [clearSelection, loadPropertiesAndVerbs, setActionMessage, setEditingName, setSelectedObject]);

    selectObjectRef.current = handleObjectSelect;

    const handleNavigateToObject = useCallback((objectId: string) => {
        const target = objects.find(obj => obj.obj === objectId);
        if (target) {
            handleObjectSelect(target);
        }
    }, [handleObjectSelect, objects]);

    // Focus on a specific object when presentation opens the browser
    useEffect(() => {
        if (focusedObjectCurie && objects.length > 0) {
            // Use stringToCurie to normalize both the focused CURIE and object strings for comparison
            const normalizedFocusCurie = stringToCurie(focusedObjectCurie);
            const objectToFocus = objects.find(obj => stringToCurie(obj.obj) === normalizedFocusCurie);
            if (objectToFocus) {
                setSelectedObject(objectToFocus);
                setEditingName(objectToFocus.name);
                clearSelection();
                loadPropertiesAndVerbs(objectToFocus);
            }
        }
    }, [focusedObjectCurie, objects]); // eslint-disable-line react-hooks/exhaustive-deps

    // Scroll to selected object when it changes
    useEffect(() => {
        if (selectedObject && objectsPaneRef.current) {
            const selectedElement = objectsPaneRef.current.querySelector(
                `.browser-item[data-obj-id="${selectedObject.obj}"]`,
            );
            if (selectedElement) {
                selectedElement.scrollIntoView({ behavior: "smooth", block: "nearest" });
            }
        }
    }, [selectedObject]);

    const objectTypeOptions = (() => {
        const options: Array<{ value: string; label: string }> = [];
        options.push({
            value: "server-default",
            label: catalog.serverFeatures
                ? `Server default (${catalog.serverFeatures.useUuobjids ? "UUID" : "numbered"})`
                : "Server default",
        });
        options.push({ value: "numbered", label: "Numbered (# objects)" });
        if (catalog.serverFeatures?.useUuobjids) {
            options.push({ value: "uuid", label: "UUID objects" });
        }
        if (catalog.serverFeatures?.anonymousObjects) {
            options.push({ value: "anonymous", label: "Anonymous objects" });
        }
        return options;
    })();

    // Load objects on mount and restore any persisted selection
    useEffect(() => {
        if (visible) {
            loadObjects().then((loadedObjects) => {
                // If we have a saved selection, restore it
                if (selectedObject) {
                    // Find the object in the loaded list
                    const matchingObj = loadedObjects.find(obj => obj.obj === selectedObject.obj);
                    if (matchingObj) {
                        // Reload properties and verbs for the restored selection
                        loadPropertiesAndVerbs(matchingObj).then((loadedProps) => {
                            setEditingName(matchingObj.name);

                            // Restore property selection if we had one
                            if (restoration.lastEditorType === "property" && restoration.lastPropertyName) {
                                const prop = loadedProps.find(p => p.name === restoration.lastPropertyName);
                                if (prop) {
                                    handlePropertySelect(prop);
                                    // Clear the restoration flags
                                    restoration.clearRestorationForProperty();
                                }
                            }
                            // Verb restoration happens in separate effect after verbs load
                        });
                    } else {
                        // Object no longer exists, clear selection
                        setSelectedObject(null);
                    }
                }
            });
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [visible, authToken]);

    useEffect(() => {
        if (!visible) {
            setShowCreateDialog(false);
            setShowRecycleDialog(false);
            setShowAddPropertyDialog(false);
            setShowDeletePropertyDialog(false);
            setShowReloadDialog(false);
        }
    }, [visible]); // eslint-disable-line react-hooks/exhaustive-deps

    const handleDetachVerbEditor = () => {
        if (!selectedVerb || !onOpenVerbInEditor) return;

        const objectCurie = stringToCurie(selectedVerb.location);
        const title = `#${selectedVerb.location}:${selectedVerb.names.join(" ")}`;

        // Open in the main verb editor system
        onOpenVerbInEditor(title, objectCurie, selectedVerb.names[0], verbCode);

        // Clear the embedded editor and go back to object view
        // Also clear restoration state to prevent the useEffect from re-selecting the verb
        setSelectedVerb(null);
        setEditorVisible(false);
        setActiveTab("objects");
        restoration.clearAllRestoration();
    };

    // Format an object reference for the "from ..." header
    // Shows: $name / #id ("object name") or just #id ("object name") if no $ name
    const formatInheritedFrom = (objId: string): string => {
        const dollarName = getDollarName(objId);
        const objData = objects.find(o => o.obj === objId);
        const displayRef = normalizeObjectRef(objId).display;

        let result = "";
        if (dollarName) {
            result = `$${dollarName} / `;
        }
        result += displayRef;
        if (objData?.name) {
            result += ` ("${objData.name}")`;
        }
        return result;
    };

    // Mouse event handlers for dragging
    const handleMouseMove = useCallback((e: MouseEvent) => {
        if (isSplitDragging && containerRef.current) {
            const rect = containerRef.current.getBoundingClientRect();
            const relativeY = e.clientY - rect.top;
            // Calculate the height for the browser pane, accounting for the title bar
            // Find the title bar height (we'll subtract it)
            const titleBar = containerRef.current.querySelector("[aria-labelledby=\"object-browser-title\"]")
                ?.children[0];
            const titleBarHeight = titleBar ? (titleBar as HTMLElement).offsetHeight : 0;
            const availableHeight = rect.height - titleBarHeight;

            // Set minimum and maximum heights (20% to 80% of available height)
            const minHeight = availableHeight * 0.2;
            const maxHeight = availableHeight * 0.8;
            const newHeight = Math.max(minHeight, Math.min(maxHeight, relativeY - titleBarHeight));
            setBrowserPaneHeight(newHeight);
        }
    }, [isSplitDragging]);

    const handleMouseUp = useCallback(() => {
        setIsSplitDragging(false);
    }, []);

    const handleSplitDragStart = useCallback((e: React.MouseEvent) => {
        if (e.button !== 0) return;
        setIsSplitDragging(true);
        e.preventDefault();
        e.stopPropagation();
    }, []);

    const handleSplitTouchStartInternal = useCallback((e: React.TouchEvent) => {
        setIsSplitDragging(true);
        e.preventDefault();
        e.stopPropagation();
    }, []);

    const handleTouchMove = useCallback((e: TouchEvent) => {
        if (isSplitDragging && containerRef.current) {
            const touch = e.touches[0];
            const rect = containerRef.current.getBoundingClientRect();
            const relativeY = touch.clientY - rect.top;
            const titleBar = containerRef.current.querySelector("[aria-labelledby=\"object-browser-title\"]")
                ?.children[0];
            const titleBarHeight = titleBar ? (titleBar as HTMLElement).offsetHeight : 0;
            const availableHeight = rect.height - titleBarHeight;

            const minHeight = availableHeight * 0.2;
            const maxHeight = availableHeight * 0.8;
            const newHeight = Math.max(minHeight, Math.min(maxHeight, relativeY - titleBarHeight));
            setBrowserPaneHeight(newHeight);
        }
    }, [isSplitDragging]);

    const handleTouchEnd = useCallback(() => {
        setIsSplitDragging(false);
    }, []);

    // Add global mouse/touch event listeners for internal split dragging
    useEffect(() => {
        if (isSplitDragging) {
            document.addEventListener("mousemove", handleMouseMove);
            document.addEventListener("mouseup", handleMouseUp);
            document.addEventListener("touchmove", handleTouchMove, { passive: false });
            document.addEventListener("touchend", handleTouchEnd);
            document.body.style.userSelect = "none";

            return () => {
                document.removeEventListener("mousemove", handleMouseMove);
                document.removeEventListener("mouseup", handleMouseUp);
                document.removeEventListener("touchmove", handleTouchMove);
                document.removeEventListener("touchend", handleTouchEnd);
                document.body.style.userSelect = "";
            };
        }
    }, [isSplitDragging, handleMouseMove, handleMouseUp, handleTouchMove, handleTouchEnd]);

    const baseFontSize = fontSize;
    const secondaryFontSize = Math.max(8, fontSize - 1);

    const isSplitDraggable = splitMode && typeof onSplitDrag === "function";

    // Title bar component that uses the drag hook (must be inside EditorWindow)
    const TitleBar: React.FC = () => {
        const titleBarDragProps = useTitleBarDrag();

        return (
            <div
                {...(isSplitDraggable
                    ? {
                        onMouseDown: onSplitDrag,
                        onTouchStart: onSplitTouchStart,
                        style: {
                            cursor: "row-resize",
                            touchAction: "none",
                        },
                    }
                    : titleBarDragProps)}
                className="editor-title-bar"
            >
                <h3 id="object-browser-title" className="editor-title">
                    Object Browser
                </h3>
                <div className="object-browser-title-controls">
                    <div className="font-size-control" onClick={(e) => e.stopPropagation()}>
                        <button
                            onClick={decreaseFontSize}
                            aria-label="Decrease browser font size"
                            className="font-size-button"
                            style={{
                                cursor: fontSize <= MIN_FONT_SIZE ? "not-allowed" : "pointer",
                                opacity: fontSize <= MIN_FONT_SIZE ? 0.5 : 1,
                                fontSize: `${secondaryFontSize}px`,
                            }}
                            disabled={fontSize <= MIN_FONT_SIZE}
                        >
                            –
                        </button>
                        <span
                            className="font-size-display"
                            style={{ fontSize: `${secondaryFontSize}px` }}
                            aria-live="polite"
                        >
                            {fontSize}px
                        </span>
                        <button
                            onClick={increaseFontSize}
                            aria-label="Increase browser font size"
                            className="font-size-button"
                            style={{
                                cursor: fontSize >= MAX_FONT_SIZE ? "not-allowed" : "pointer",
                                opacity: fontSize >= MAX_FONT_SIZE ? 0.5 : 1,
                                fontSize: `${secondaryFontSize}px`,
                            }}
                            disabled={fontSize >= MAX_FONT_SIZE}
                        >
                            +
                        </button>
                    </div>
                    <div className="browser-inherited-controls" onClick={(e) => e.stopPropagation()}>
                        <span className="browser-inherited-label-text">
                            Inherited
                        </span>
                        <button
                            type="button"
                            className={`browser-inherited-toggle ${showInheritedProperties ? "active" : ""}`}
                            onClick={() => setShowInheritedProperties(prev => !prev)}
                            aria-label="Show inherited properties"
                            aria-pressed={showInheritedProperties}
                            title={showInheritedProperties
                                ? "Hide inherited properties"
                                : "Show inherited properties"}
                        >
                            P
                        </button>
                        <button
                            type="button"
                            className={`browser-inherited-toggle ${showInheritedVerbs ? "active" : ""}`}
                            onClick={() => setShowInheritedVerbs(prev => !prev)}
                            aria-label="Show inherited verbs"
                            aria-pressed={showInheritedVerbs}
                            title={showInheritedVerbs ? "Hide inherited verbs" : "Show inherited verbs"}
                        >
                            V
                        </button>
                    </div>
                    {/* Split/Float toggle button - only on non-touch devices */}
                    {!isTouchDevice && onToggleSplitMode && (
                        <button
                            className="browser-mode-toggle"
                            onClick={(e) => {
                                e.stopPropagation();
                                onToggleSplitMode();
                            }}
                            aria-label={isInSplitMode ? "Switch to floating window" : "Switch to split screen"}
                            title={isInSplitMode ? "Switch to floating window" : "Switch to split screen"}
                            style={{ fontSize: `${secondaryFontSize}px` }}
                        >
                            {isInSplitMode ? "🪟" : "⬌"}
                        </button>
                    )}
                    {/* Fullscreen toggle button */}
                    <button
                        className="browser-mode-toggle"
                        onClick={(e) => {
                            e.stopPropagation();
                            setIsFullscreen(prev => !prev);
                        }}
                        aria-label={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"}
                        title={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"}
                        style={{ fontSize: `${secondaryFontSize}px` }}
                    >
                        {isFullscreen ? "🗗" : "🗖"}
                    </button>
                    <button
                        className="editor-btn-close"
                        onClick={onClose}
                        aria-label="Close object browser"
                    >
                        <span aria-hidden="true">×</span>
                    </button>
                </div>
            </div>
        );
    };

    return (
        <EditorWindow
            visible={visible}
            onClose={onClose}
            splitMode={splitMode}
            defaultPosition={{ x: 50, y: 50 }}
            defaultSize={{ width: 1000, height: 700 }}
            minSize={{ width: 600, height: 400 }}
            ariaLabel="Object Browser"
            className={`object_browser_container ${isFullscreen ? "fullscreen-mobile" : ""}`}
        >
            <div
                ref={containerRef}
                style={{ fontSize: `${baseFontSize}px`, display: "flex", flexDirection: "column", height: "100%" }}
            >
                <TitleBar />

                {/* Main content area - 3 panes + editor */}
                <div className="browser-content">
                    {/* Tab navigation for small screens */}
                    {useTabLayout && (
                        <div className="browser-tabs">
                            <button
                                className={`browser-tab ${activeTab === "objects" ? "active" : ""}`}
                                onClick={() => setActiveTab("objects")}
                            >
                                Objects
                            </button>
                            <button
                                className={`browser-tab ${activeTab === "properties" ? "active" : ""}`}
                                onClick={() => setActiveTab("properties")}
                                disabled={!selectedObject}
                            >
                                Properties
                            </button>
                            <button
                                className={`browser-tab ${activeTab === "verbs" ? "active" : ""}`}
                                onClick={() => setActiveTab("verbs")}
                                disabled={!selectedObject}
                            >
                                Verbs
                            </button>
                        </div>
                    )}

                    {/* Top area - 3 panes */}
                    <div
                        className={`browser-panes ${useTabLayout ? "tabbed" : ""}`}
                        style={{
                            height: (editorVisible || selectedObject)
                                ? `${browserPaneHeight}px`
                                : "100%",
                        }}
                    >
                        {/* Objects pane */}
                        <div
                            className={`browser-pane ${!useTabLayout || activeTab === "objects" ? "active" : ""}`}
                            role="region"
                            aria-label="Objects"
                        >
                            <div className="browser-pane-header">
                                <span
                                    className="browser-pane-title"
                                    style={{ fontSize: `${secondaryFontSize}px` }}
                                >
                                    Objects
                                </span>
                                <div className="browser-pane-actions">
                                    <div
                                        className="browser-filter-controls browser-filter-segmented"
                                        onClick={(e) => e.stopPropagation()}
                                    >
                                        <button
                                            type="button"
                                            className={`browser-filter-toggle browser-filter-toggle-text ${
                                                !showMineOnly ? "active" : ""
                                            }`}
                                            onClick={() => setShowMineOnly(false)}
                                            aria-label="Show all objects"
                                            aria-pressed={!showMineOnly}
                                            title="Show all objects"
                                        >
                                            All
                                        </button>
                                        <button
                                            type="button"
                                            className={`browser-filter-toggle browser-filter-toggle-text ${
                                                showMineOnly ? "active" : ""
                                            }`}
                                            onClick={() => setShowMineOnly(true)}
                                            aria-label="Show only objects owned by me"
                                            aria-pressed={showMineOnly}
                                            title="Show only objects owned by me"
                                            disabled={!playerObjectRef}
                                        >
                                            Mine
                                        </button>
                                    </div>
                                    <button
                                        type="button"
                                        className="btn btn-sm"
                                        onClick={() => {
                                            mutations.setCreateDialogError(null);
                                            setActionMessage(null);
                                            setShowCreateDialog(true);
                                        }}
                                        style={{ fontSize: `${secondaryFontSize}px` }}
                                        title="Add new object"
                                    >
                                        + Add
                                    </button>
                                </div>
                            </div>
                            <div className="p-sm border-bottom bg-secondary">
                                <input
                                    type="text"
                                    placeholder="Filter objects..."
                                    value={filter}
                                    onChange={(e) => setFilter(e.target.value)}
                                    className="w-full p-xs border rounded-sm"
                                    style={{ fontSize: `${baseFontSize}px` }}
                                />
                            </div>
                            <div
                                ref={objectsPaneRef}
                                className="browser-pane-content"
                                style={{ fontSize: `${baseFontSize}px` }}
                            >
                                {isLoading
                                    ? (
                                        <div className="p-md text-secondary">
                                            Loading objects...
                                        </div>
                                    )
                                    : (
                                        <>
                                            {/* Numeric OID objects */}
                                            {numericObjects.map((obj) => {
                                                const dollarName = getDollarName(obj.obj);
                                                return (
                                                    <div
                                                        key={obj.obj}
                                                        data-obj-id={obj.obj}
                                                        className={`browser-item ${
                                                            selectedObject?.obj === obj.obj ? "selected" : ""
                                                        }`}
                                                        onClick={() => handleObjectSelect(obj)}
                                                        onKeyDown={(e) => {
                                                            if (e.key === "Enter" || e.key === " ") {
                                                                e.preventDefault();
                                                                handleObjectSelect(obj);
                                                            }
                                                        }}
                                                        tabIndex={0}
                                                        role="button"
                                                        aria-pressed={selectedObject?.obj === obj.obj}
                                                    >
                                                        <div className="browser-item-name font-bold">
                                                            {dollarName ? `$${dollarName} / ` : ""}#{obj.obj}{" "}
                                                            {obj.name && `("${obj.name}")`}{" "}
                                                            {formatObjectFlags(obj.flags) && (
                                                                <span
                                                                    className="text-secondary"
                                                                    style={{
                                                                        opacity: selectedObject?.obj === obj.obj
                                                                            ? "0.7"
                                                                            : "1",
                                                                        color: selectedObject?.obj === obj.obj
                                                                            ? "inherit"
                                                                            : undefined,
                                                                        fontWeight: "400",
                                                                    }}
                                                                >
                                                                    ({formatObjectFlags(obj.flags)})
                                                                </span>
                                                            )}
                                                        </div>
                                                    </div>
                                                );
                                            })}

                                            {/* Separator and UUID objects section */}
                                            {uuidObjects.length > 0 && (
                                                <>
                                                    <div
                                                        className="browser-inherited-label"
                                                        style={{
                                                            borderTop: "2px solid var(--color-border-medium)",
                                                            fontSize: `${secondaryFontSize}px`,
                                                        }}
                                                    >
                                                        UUID Objects
                                                    </div>
                                                    {uuidObjects.map((obj) => {
                                                        const dollarName = getDollarName(obj.obj);
                                                        return (
                                                            <div
                                                                key={obj.obj}
                                                                data-obj-id={obj.obj}
                                                                className={`browser-item ${
                                                                    selectedObject?.obj === obj.obj
                                                                        ? "selected"
                                                                        : ""
                                                                }`}
                                                                onClick={() => handleObjectSelect(obj)}
                                                                onKeyDown={(e) => {
                                                                    if (e.key === "Enter" || e.key === " ") {
                                                                        e.preventDefault();
                                                                        handleObjectSelect(obj);
                                                                    }
                                                                }}
                                                                tabIndex={0}
                                                                role="button"
                                                                aria-pressed={selectedObject?.obj === obj.obj}
                                                            >
                                                                <div className="browser-item-name font-bold">
                                                                    {dollarName ? `$${dollarName} / ` : ""}#{obj
                                                                        .obj} {obj.name && `("${obj.name}")`}{" "}
                                                                    {formatObjectFlags(obj.flags) && (
                                                                        <span
                                                                            className="text-secondary"
                                                                            style={{
                                                                                opacity: selectedObject?.obj
                                                                                        === obj.obj
                                                                                    ? "0.7"
                                                                                    : "1",
                                                                                color: selectedObject?.obj === obj.obj
                                                                                    ? "inherit"
                                                                                    : undefined,
                                                                                fontWeight: "400",
                                                                            }}
                                                                        >
                                                                            ({formatObjectFlags(obj.flags)})
                                                                        </span>
                                                                    )}
                                                                </div>
                                                            </div>
                                                        );
                                                    })}
                                                </>
                                            )}
                                        </>
                                    )}
                            </div>
                        </div>

                        {/* Properties pane */}
                        <div
                            className={`browser-pane ${!useTabLayout || activeTab === "properties" ? "active" : ""}`}
                            role="region"
                            aria-label="Properties"
                        >
                            <div className="browser-pane-header">
                                <span
                                    className="browser-pane-title"
                                    style={{ fontSize: `${secondaryFontSize}px` }}
                                >
                                    Properties
                                </span>
                                {selectedObject && (
                                    <button
                                        type="button"
                                        className="btn btn-sm"
                                        onClick={() => {
                                            mutations.setAddPropertyDialogError(null);
                                            setActionMessage(null);
                                            setShowAddPropertyDialog(true);
                                        }}
                                        disabled={mutations.isSubmittingAddProperty}
                                        aria-label="Add property"
                                        title="Add property"
                                        style={{
                                            cursor: mutations.isSubmittingAddProperty
                                                ? "not-allowed"
                                                : "pointer",
                                            opacity: mutations.isSubmittingAddProperty ? 0.6 : 1,
                                            fontSize: `${secondaryFontSize}px`,
                                        }}
                                    >
                                        + Add
                                    </button>
                                )}
                            </div>
                            <div className="p-sm border-bottom bg-secondary">
                                <input
                                    type="text"
                                    placeholder="Filter properties..."
                                    value={propertyFilter}
                                    onChange={(e) => setPropertyFilter(e.target.value)}
                                    className="w-full p-xs border rounded-sm"
                                    style={{ fontSize: `${baseFontSize}px` }}
                                />
                            </div>
                            <div
                                className="browser-pane-content"
                                style={{ fontSize: `${baseFontSize}px` }}
                            >
                                {!selectedObject
                                    ? (
                                        <div className="p-md text-secondary">
                                            Select an object to view properties
                                        </div>
                                    )
                                    : properties.length === 0
                                    ? (
                                        <div className="p-md text-secondary">
                                            No properties
                                        </div>
                                    )
                                    : (
                                        groupedProperties.map(([location, props], _groupIdx) => (
                                            <div key={location}>
                                                {location !== selectedObject.obj && showInheritedProperties && (
                                                    <div
                                                        className="browser-inherited-label"
                                                        style={{ fontSize: `${secondaryFontSize}px` }}
                                                    >
                                                        from {formatInheritedFrom(location)}
                                                    </div>
                                                )}
                                                {props.map((prop, idx) => (
                                                    <div
                                                        key={`${location}-${idx}`}
                                                        className={`browser-item ${
                                                            selectedProperty?.name === prop.name
                                                                && selectedProperty?.location === prop.location
                                                                ? "selected"
                                                                : ""
                                                        }`}
                                                        onClick={() => handlePropertySelect(prop)}
                                                        onKeyDown={(e) => {
                                                            if (e.key === "Enter" || e.key === " ") {
                                                                e.preventDefault();
                                                                handlePropertySelect(prop);
                                                            }
                                                        }}
                                                        tabIndex={0}
                                                        role="button"
                                                        aria-pressed={selectedProperty?.name === prop.name
                                                            && selectedProperty?.location === prop.location}
                                                    >
                                                        <div className="browser-item-name font-bold">
                                                            {prop.name}{" "}
                                                            <span
                                                                className="text-secondary"
                                                                style={{
                                                                    opacity: selectedProperty?.name === prop.name
                                                                            && selectedProperty?.location
                                                                                === prop.location
                                                                        ? "0.7"
                                                                        : "1",
                                                                    color: selectedProperty?.name === prop.name
                                                                            && selectedProperty?.location
                                                                                === prop.location
                                                                        ? "inherit"
                                                                        : undefined,
                                                                    fontWeight: "400",
                                                                    fontSize: `${secondaryFontSize}px`,
                                                                }}
                                                            >
                                                                ({prop.readable ? "r" : ""}
                                                                {prop.writable ? "w" : ""})
                                                            </span>
                                                        </div>
                                                    </div>
                                                ))}
                                            </div>
                                        ))
                                    )}
                            </div>
                        </div>

                        {/* Verbs pane */}
                        <div
                            className={`browser-pane ${!useTabLayout || activeTab === "verbs" ? "active" : ""}`}
                            role="region"
                            aria-label="Verbs"
                        >
                            <div className="browser-pane-header">
                                <span
                                    className="browser-pane-title"
                                    style={{ fontSize: `${secondaryFontSize}px` }}
                                >
                                    Verbs
                                </span>
                                {selectedObject && (
                                    <div className="browser-pane-actions">
                                        <div className="browser-filter-controls" onClick={(e) => e.stopPropagation()}>
                                            <button
                                                type="button"
                                                className={`browser-filter-toggle ${showCommands ? "active" : ""}`}
                                                onClick={() => setShowCommands(prev => !prev)}
                                                aria-label="Show command verbs"
                                                aria-pressed={showCommands}
                                                title={showCommands ? "Hide command verbs" : "Show command verbs"}
                                            >
                                                C
                                            </button>
                                            <button
                                                type="button"
                                                className={`browser-filter-toggle ${showMethods ? "active" : ""}`}
                                                onClick={() => setShowMethods(prev => !prev)}
                                                aria-label="Show method verbs"
                                                aria-pressed={showMethods}
                                                title={showMethods ? "Hide method verbs" : "Show method verbs"}
                                            >
                                                M
                                            </button>
                                            <button
                                                type="button"
                                                className={`browser-filter-toggle ${showTests ? "active" : ""}`}
                                                onClick={() => setShowTests(prev => !prev)}
                                                aria-label="Show test verbs"
                                                aria-pressed={showTests}
                                                title={showTests ? "Hide test verbs" : "Show test verbs"}
                                            >
                                                T
                                            </button>
                                        </div>
                                        <button
                                            type="button"
                                            className="btn btn-sm"
                                            onClick={mutations.handleRunAllTests}
                                            disabled={mutations.isRunningTests
                                                || verbs.every(v =>
                                                    !v.names.some(n => isTestVerb(n))
                                                    || v.location !== selectedObject.obj
                                                )}
                                            aria-label="Run all tests"
                                            title="Run all tests"
                                            style={{
                                                cursor: mutations.isRunningTests || verbs.every(v =>
                                                        !v.names.some(n => isTestVerb(n))
                                                        || v.location !== selectedObject.obj
                                                    )
                                                    ? "not-allowed"
                                                    : "pointer",
                                                opacity: mutations.isRunningTests
                                                        || verbs.every(v =>
                                                            !v.names.some(n =>
                                                                isTestVerb(n)
                                                            )
                                                            || v.location !== selectedObject.obj
                                                        )
                                                    ? 0.6
                                                    : 1,
                                                fontSize: `${secondaryFontSize}px`,
                                            }}
                                        >
                                            🧪 Run Tests
                                        </button>
                                        <button
                                            type="button"
                                            className="btn btn-sm"
                                            onClick={() => {
                                                mutations.setAddVerbDialogError(null);
                                                setActionMessage(null);
                                                mutations.setShowAddVerbDialog(true);
                                            }}
                                            disabled={mutations.isSubmittingAddVerb}
                                            aria-label="Add verb"
                                            title="Add verb"
                                            style={{
                                                cursor: mutations.isSubmittingAddVerb ? "not-allowed" : "pointer",
                                                opacity: mutations.isSubmittingAddVerb ? 0.6 : 1,
                                                fontSize: `${secondaryFontSize}px`,
                                            }}
                                        >
                                            + Add
                                        </button>
                                    </div>
                                )}
                            </div>
                            <div className="p-sm border-bottom bg-secondary">
                                <input
                                    type="text"
                                    placeholder="Filter verbs..."
                                    value={verbFilter}
                                    onChange={(e) => setVerbFilter(e.target.value)}
                                    className="w-full p-xs border rounded-sm"
                                    style={{ fontSize: `${baseFontSize}px` }}
                                />
                            </div>
                            <div
                                className="browser-pane-content"
                                style={{ fontSize: `${baseFontSize}px` }}
                            >
                                {!selectedObject
                                    ? (
                                        <div className="p-md text-secondary">
                                            Select an object to view verbs
                                        </div>
                                    )
                                    : verbs.length === 0
                                    ? (
                                        <div className="p-md text-secondary">
                                            No verbs
                                        </div>
                                    )
                                    : (
                                        groupedVerbs.map(([location, verbList], _groupIdx) => (
                                            <div key={location}>
                                                {location !== selectedObject.obj && showInheritedVerbs && (
                                                    <div
                                                        className="browser-inherited-label"
                                                        style={{ fontSize: `${secondaryFontSize}px` }}
                                                    >
                                                        from {formatInheritedFrom(location)}
                                                    </div>
                                                )}
                                                {verbList.map((verb, idx) => (
                                                    <div
                                                        key={`${location}-${idx}`}
                                                        className={`browser-item ${
                                                            selectedVerb?.location === verb.location
                                                                && selectedVerb?.indexInLocation
                                                                    === verb.indexInLocation
                                                                ? "selected"
                                                                : ""
                                                        }`}
                                                        onClick={() => handleVerbSelect(verb)}
                                                        onKeyDown={(e) => {
                                                            if (e.key === "Enter" || e.key === " ") {
                                                                e.preventDefault();
                                                                handleVerbSelect(verb);
                                                            }
                                                        }}
                                                        tabIndex={0}
                                                        role="button"
                                                        aria-pressed={selectedVerb?.location === verb.location
                                                            && selectedVerb?.indexInLocation === verb.indexInLocation}
                                                    >
                                                        <div className="browser-item-name font-bold">
                                                            {verb.names.some(n => isTestVerb(n)) && (
                                                                <span
                                                                    title="Unit Test"
                                                                    style={{ marginRight: "4px" }}
                                                                >
                                                                    🧪
                                                                </span>
                                                            )}
                                                            {verb.names.join(" ")}{" "}
                                                            <span
                                                                className="text-secondary"
                                                                style={{
                                                                    opacity: selectedVerb?.location === verb.location
                                                                            && selectedVerb?.indexInLocation
                                                                                === verb.indexInLocation
                                                                        ? "0.7"
                                                                        : "1",
                                                                    color: selectedVerb?.location === verb.location
                                                                            && selectedVerb?.indexInLocation
                                                                                === verb.indexInLocation
                                                                        ? "inherit"
                                                                        : undefined,
                                                                    fontWeight: "400",
                                                                    fontSize: `${secondaryFontSize}px`,
                                                                }}
                                                            >
                                                                ({verb.readable ? "r" : ""}
                                                                {verb.writable ? "w" : ""}
                                                                {verb.executable ? "x" : ""}
                                                                {verb.debug ? "d" : ""})
                                                                {verbLabels.duplicateNames.has(
                                                                    `${location}:${verb.indexInLocation}`,
                                                                ) && " (duplicate name)"}
                                                                {verbLabels.overridden.has(
                                                                    `${location}:${verb.indexInLocation}`,
                                                                ) && " (overridden)"}
                                                            </span>
                                                        </div>
                                                    </div>
                                                ))}
                                            </div>
                                        ))
                                    )}
                            </div>
                        </div>
                    </div>

                    {/* Draggable splitter bar */}
                    {(editorVisible || selectedObject) && (
                        <div
                            className={`browser-resize-handle ${isSplitDragging ? "dragging" : ""}`}
                            onMouseDown={handleSplitDragStart}
                            onTouchStart={handleSplitTouchStartInternal}
                            style={{
                                position: "relative",
                                zIndex: 10,
                            }}
                        />
                    )}

                    {/* Bottom editor area */}
                    {(editorVisible || selectedObject) && (
                        <div className="flex-1 overflow-hidden bg-secondary">
                            {selectedObject && !selectedProperty && !selectedVerb && (
                                <ObjectInfoEditor
                                    object={selectedObject}
                                    objects={objects}
                                    authToken={authToken}
                                    onNavigate={handleNavigateToObject}
                                    normalizeObjectRef={normalizeObjectRef}
                                    normalizeObjectInput={normalizeObjectInput}
                                    getDollarName={getDollarName}
                                    onCreateChild={() => {
                                        mutations.setCreateDialogError(null);
                                        setActionMessage(null);
                                        setShowCreateDialog(true);
                                    }}
                                    onRecycle={() => {
                                        mutations.setRecycleDialogError(null);
                                        setActionMessage(null);
                                        setShowRecycleDialog(true);
                                    }}
                                    onEditFlags={() => {
                                        mutations.setEditFlagsDialogError(null);
                                        setActionMessage(null);
                                        mutations.setShowEditFlagsDialog(true);
                                    }}
                                    onDumpObject={mutations.handleDumpObject}
                                    onReloadObject={() => {
                                        mutations.setReloadDialogError(null);
                                        setActionMessage(null);
                                        setShowReloadDialog(true);
                                    }}
                                    isSubmittingCreate={mutations.isSubmittingCreate}
                                    isSubmittingRecycle={mutations.isSubmittingRecycle}
                                    isSubmittingReload={mutations.isSubmittingReload}
                                    editingName={editingName}
                                    onNameChange={setEditingName}
                                    onNameSave={mutations.handleNameSave}
                                    isSavingName={mutations.isSavingName}
                                    actionMessage={actionMessage}
                                />
                            )}
                            {selectedProperty && selectedProperty.moorVar && selectedObject && (
                                <PropertyValueEditor
                                    authToken={authToken}
                                    objectCurie={stringToCurie(selectedObject.obj)}
                                    propertyName={selectedProperty.name}
                                    propertyValue={selectedProperty.moorVar}
                                    onSave={async () => {
                                        // Reload properties list to get updated metadata, then reload property value
                                        if (selectedObject) {
                                            const freshProps = await loadPropertiesAndVerbs(selectedObject);
                                            // Find the updated property in the freshly loaded list
                                            const updatedProp = freshProps.find(p =>
                                                p.name === selectedProperty.name
                                                && p.location === selectedProperty.location
                                            ) ?? freshProps.find(p => p.name === selectedProperty.name);
                                            if (updatedProp) {
                                                await handlePropertySelect(updatedProp);
                                            }
                                        }
                                    }}
                                    onCancel={() => {
                                        setSelectedProperty(null);
                                        setEditorVisible(false);
                                    }}
                                    onDelete={selectedProperty.location === selectedObject.obj
                                        ? () => {
                                            setPropertyToDelete(selectedProperty);
                                            mutations.setDeletePropertyDialogError(null);
                                            setActionMessage(null);
                                            setShowDeletePropertyDialog(true);
                                        }
                                        : undefined}
                                    owner={selectedProperty.owner}
                                    definer={selectedProperty.definer}
                                    permissions={{
                                        readable: selectedProperty.readable,
                                        writable: selectedProperty.writable,
                                        chown: selectedProperty.chown,
                                    }}
                                    onNavigateToObject={handleNavigateToObject}
                                    normalizeObjectInput={normalizeObjectInput}
                                    getDollarName={getDollarName}
                                />
                            )}
                            {selectedProperty && !selectedProperty.moorVar && (
                                <div style={{ padding: "var(--space-md)", color: "var(--color-text-secondary)" }}>
                                    Loading property value...
                                </div>
                            )}
                            {selectedVerb && (
                                <VerbEditor
                                    visible={true}
                                    onClose={() => {
                                        setSelectedVerb(null);
                                        setEditorVisible(false);
                                    }}
                                    title={`#${selectedVerb.location}:${selectedVerb.names.join(" ")}${
                                        selectedObject && selectedVerb.location !== selectedObject.obj
                                            ? ` (inherited from #${selectedVerb.location})`
                                            : ""
                                    }`}
                                    objectCurie={stringToCurie(selectedVerb.location)}
                                    verbName={selectedVerb.names[0]}
                                    verbNames={selectedVerb.names.join(" ")}
                                    initialContent={verbCode}
                                    authToken={authToken}
                                    splitMode={true}
                                    isInSplitMode={true}
                                    preventAutoFocus={true}
                                    onToggleSplitMode={onOpenVerbInEditor ? handleDetachVerbEditor : undefined}
                                    owner={selectedVerb.owner}
                                    definer={selectedVerb.location}
                                    permissions={{
                                        readable: selectedVerb.readable,
                                        writable: selectedVerb.writable,
                                        executable: selectedVerb.executable,
                                        debug: selectedVerb.debug,
                                    }}
                                    argspec={{
                                        dobj: selectedVerb.dobj,
                                        prep: selectedVerb.prep,
                                        iobj: selectedVerb.iobj,
                                    }}
                                    onSave={() => {
                                        // Reload verbs list in background to update the list
                                        if (selectedObject) {
                                            loadPropertiesAndVerbs(selectedObject);
                                        }
                                    }}
                                    onDelete={() => {
                                        setVerbToDelete(selectedVerb);
                                        mutations.setDeleteVerbDialogError(null);
                                        mutations.setShowDeleteVerbDialog(true);
                                    }}
                                    normalizeObjectInput={normalizeObjectInput}
                                    getDollarName={getDollarName}
                                />
                            )}
                        </div>
                    )}
                </div>
            </div>
            {mutations.showCreateDialog && (
                <CreateChildDialog
                    key={selectedObject?.obj || "new"}
                    defaultParent={selectedObject ? `#${selectedObject.obj}` : "#-1"}
                    defaultOwner="player"
                    objectTypeOptions={objectTypeOptions}
                    onCancel={() => setShowCreateDialog(false)}
                    onSubmit={mutations.handleCreateSubmit}
                    isSubmitting={mutations.isSubmittingCreate}
                    errorMessage={mutations.createDialogError}
                />
            )}
            {mutations.showRecycleDialog && selectedObject && (
                <RecycleObjectDialog
                    key={`recycle-${selectedObject.obj}`}
                    objectLabel={describeObject(selectedObject)}
                    onCancel={() => setShowRecycleDialog(false)}
                    onConfirm={mutations.handleRecycleConfirm}
                    isSubmitting={mutations.isSubmittingRecycle}
                    errorMessage={mutations.recycleDialogError}
                />
            )}
            {mutations.showAddPropertyDialog && selectedObject && (
                <AddPropertyDialog
                    key={`add-property-${selectedObject.obj}`}
                    objectLabel={describeObject(selectedObject)}
                    defaultOwner="player"
                    onCancel={() => setShowAddPropertyDialog(false)}
                    onSubmit={mutations.handleAddPropertySubmit}
                    isSubmitting={mutations.isSubmittingAddProperty}
                    errorMessage={mutations.addPropertyDialogError}
                />
            )}
            {mutations.showDeletePropertyDialog && mutations.propertyToDelete && selectedObject && (
                <DeletePropertyDialog
                    key={`delete-property-${mutations.propertyToDelete.name}`}
                    propertyName={mutations.propertyToDelete.name}
                    objectLabel={describeObject(selectedObject)}
                    onCancel={() => {
                        setShowDeletePropertyDialog(false);
                        mutations.setPropertyToDelete(null);
                    }}
                    onConfirm={mutations.handleDeletePropertyConfirm}
                    isSubmitting={mutations.isSubmittingDeleteProperty}
                    errorMessage={mutations.deletePropertyDialogError}
                />
            )}
            {mutations.showAddVerbDialog && selectedObject && (
                <AddVerbDialog
                    key={`add-verb-${selectedObject.obj}`}
                    objectLabel={describeObject(selectedObject)}
                    defaultOwner="player"
                    onCancel={() => mutations.setShowAddVerbDialog(false)}
                    onSubmit={mutations.handleAddVerbSubmit}
                    isSubmitting={mutations.isSubmittingAddVerb}
                    errorMessage={mutations.addVerbDialogError}
                />
            )}
            {mutations.showDeleteVerbDialog && mutations.verbToDelete && selectedObject && (
                <DeleteVerbDialog
                    key={`delete-verb-${mutations.verbToDelete.names[0]}`}
                    verbName={mutations.verbToDelete.names.join(" ")}
                    objectLabel={describeObject(selectedObject)}
                    onCancel={() => {
                        mutations.setShowDeleteVerbDialog(false);
                        mutations.setVerbToDelete(null);
                    }}
                    onConfirm={mutations.handleDeleteVerbConfirm}
                    isSubmitting={mutations.isSubmittingDeleteVerb}
                    errorMessage={mutations.deleteVerbDialogError}
                />
            )}
            {mutations.showEditFlagsDialog && selectedObject && (
                <EditFlagsDialog
                    key={`edit-flags-${selectedObject.obj}`}
                    objectLabel={describeObject(selectedObject)}
                    currentFlags={selectedObject.flags}
                    onCancel={() => mutations.setShowEditFlagsDialog(false)}
                    onSubmit={mutations.handleEditFlagsSubmit}
                    isSubmitting={mutations.isSubmittingEditFlags}
                    errorMessage={mutations.editFlagsDialogError}
                />
            )}
            {mutations.showReloadDialog && selectedObject && (
                <ReloadObjectDialog
                    key={`reload-${selectedObject.obj}`}
                    objectLabel={describeObject(selectedObject)}
                    objectId={selectedObject.obj}
                    onCancel={() => setShowReloadDialog(false)}
                    onSubmit={mutations.handleReloadObjectSubmit}
                    isSubmitting={mutations.isSubmittingReload}
                    errorMessage={mutations.reloadDialogError}
                />
            )}
            {mutations.showTestResultsDialog && (
                <TestResultsDialog
                    results={mutations.testResults}
                    onClose={() => mutations.setShowTestResultsDialog(false)}
                />
            )}
        </EditorWindow>
    );
};
