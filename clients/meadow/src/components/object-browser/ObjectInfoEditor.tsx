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

import React, { useEffect, useState } from "react";
import { performEvalFlatBuffer } from "../../lib/rpc-fb";
import { formatObjectFlags } from "./browserUtils";
import { ObjectData } from "./types";

interface ObjectInfoEditorProps {
    object: ObjectData;
    objects: ObjectData[];
    authToken: string;
    onNavigate: (objectId: string) => void;
    normalizeObjectRef: (raw: string) => { display: string; objectId: string | null };
    normalizeObjectInput: (raw: string) => string;
    getDollarName: (objId: string) => string | null;
    onCreateChild: () => void;
    onRecycle: () => void;
    onEditFlags: () => void;
    onDumpObject: () => void;
    onReloadObject: () => void;
    isSubmittingCreate: boolean;
    isSubmittingRecycle: boolean;
    isSubmittingReload: boolean;
    editingName: string;
    onNameChange: (name: string) => void;
    onNameSave: () => void;
    isSavingName: boolean;
    actionMessage: string | null;
}

export const ObjectInfoEditor: React.FC<ObjectInfoEditorProps> = ({
    object,
    objects,
    authToken,
    onNavigate,
    normalizeObjectRef,
    normalizeObjectInput: _normalizeObjectInput,
    getDollarName,
    onCreateChild,
    onRecycle,
    onEditFlags,
    onDumpObject,
    onReloadObject,
    isSubmittingCreate,
    isSubmittingRecycle,
    isSubmittingReload,
    editingName,
    onNameChange,
    onNameSave,
    isSavingName,
    actionMessage,
}) => {
    const [children, setChildren] = useState<string[]>([]);
    const [ancestors, setAncestors] = useState<string[]>([]);
    const [descendants, setDescendants] = useState<string[]>([]);
    const [contents, setContents] = useState<string[]>([]);
    const [isLoading, setIsLoading] = useState(false);
    const [childrenExpanded, setChildrenExpanded] = useState(true);
    const [ancestorsExpanded, setAncestorsExpanded] = useState(true);
    const [descendantsExpanded, setDescendantsExpanded] = useState(true);
    const [contentsExpanded, setContentsExpanded] = useState(true);

    // Helper to extract object ID from FlatBuffer result
    const extractObjectId = (obj: unknown): string | null => {
        if (!obj) return null;

        // The result from performEvalFlatBuffer is already converted via toJS()
        // For objects, this returns { oid?: number; uuid?: string }
        if (typeof obj === "object" && obj !== null) {
            // Check for oid (numbered objects)
            if ("oid" in obj && obj.oid !== undefined && obj.oid !== null) {
                return String(obj.oid);
            }
            // Check for uuid (UUID objects)
            if ("uuid" in obj && obj.uuid !== undefined && obj.uuid !== null) {
                return String(obj.uuid);
            }
            // Fallback checks for other formats
            if ("id" in obj) return String(obj.id);
            if ("objid" in obj) return String(obj.objid);
        }

        // Try as number
        if (typeof obj === "number") {
            return String(obj);
        }

        // Try as string (but not "[object Object]")
        if (typeof obj === "string" && obj !== "[object Object]") {
            return obj;
        }

        return null;
    };

    // Load hierarchy data when object changes
    useEffect(() => {
        const loadHierarchy = async () => {
            setIsLoading(true);
            try {
                const objectRef = `#${object.obj}`;

                // Load children
                const childrenExpr = `return children(${objectRef});`;
                const childrenResult = await performEvalFlatBuffer(authToken, childrenExpr);
                if (Array.isArray(childrenResult)) {
                    const ids = childrenResult.map(extractObjectId).filter((id): id is string => id !== null);
                    setChildren(ids);
                } else {
                    setChildren([]);
                }

                // Load ancestors
                const ancestorsExpr = `return ancestors(${objectRef});`;
                const ancestorsResult = await performEvalFlatBuffer(authToken, ancestorsExpr);
                if (Array.isArray(ancestorsResult)) {
                    const ids = ancestorsResult.map(extractObjectId).filter((id): id is string => id !== null);
                    setAncestors(ids);
                } else {
                    setAncestors([]);
                }

                // Load descendants
                const descendantsExpr = `return descendants(${objectRef});`;
                const descendantsResult = await performEvalFlatBuffer(authToken, descendantsExpr);
                if (Array.isArray(descendantsResult)) {
                    const ids = descendantsResult.map(extractObjectId).filter((id): id is string => id !== null);
                    setDescendants(ids);
                } else {
                    setDescendants([]);
                }

                // Load contents
                const contentsExpr = `return ${objectRef}.contents;`;
                const contentsResult = await performEvalFlatBuffer(authToken, contentsExpr);
                if (Array.isArray(contentsResult)) {
                    const ids = contentsResult.map(extractObjectId).filter((id): id is string => id !== null);
                    setContents(ids);
                } else {
                    setContents([]);
                }
            } catch (error) {
                console.error("Failed to load hierarchy:", error);
            } finally {
                setIsLoading(false);
            }
        };

        loadHierarchy();
    }, [object.obj, authToken]);

    const renderObjectLink = (objId: string) => {
        const { display, objectId } = normalizeObjectRef(objId);

        // Look up object name and $ name from the objects list
        const objData = objects.find(o => o.obj === objectId);
        const dollarName = objectId ? getDollarName(objectId) : null;

        let displayText = "";
        if (dollarName) {
            displayText = `$${dollarName} / `;
        }
        displayText += display;
        if (objData && objData.name) {
            displayText += ` ("${objData.name}")`;
        }

        if (!objectId) {
            return (
                <span className="font-mono text-secondary">
                    {displayText}
                </span>
            );
        }
        return (
            <button
                type="button"
                className="btn-link font-mono"
                onClick={() => onNavigate(objectId)}
            >
                {displayText}
            </button>
        );
    };

    const sectionStyle = {
        marginBottom: "6px",
        border: "1px solid var(--color-border-medium)",
        borderRadius: "var(--radius-sm)",
        backgroundColor: "var(--color-bg-input)",
        fontSize: "11px",
    } as const;

    const sectionHeaderStyle = {
        fontWeight: 600,
        color: "var(--color-text-primary)",
        textTransform: "uppercase" as const,
        letterSpacing: "0.08em",
        fontSize: "10px",
        padding: "4px 8px",
        cursor: "pointer",
        display: "flex",
        alignItems: "center",
        gap: "4px",
        userSelect: "none" as const,
        backgroundColor: "var(--color-bg-secondary)",
        borderBottom: "1px solid var(--color-border-light)",
    } as const;

    const sectionContentStyle = {
        padding: "6px 8px",
    } as const;

    const listStyle = {
        display: "flex",
        flexWrap: "wrap" as const,
        gap: "4px",
        alignItems: "center",
        lineHeight: "1.3",
    } as const;

    const renderCollapsibleSection = (
        title: string,
        count: number,
        isExpanded: boolean,
        setExpanded: (val: boolean) => void,
        content: React.ReactNode,
    ) => (
        <div className="browser-section">
            <div
                className="browser-section-header"
                onClick={() => setExpanded(!isExpanded)}
            >
                <span style={{ fontSize: "9px" }}>{isExpanded ? "▼" : "▶"}</span>
                <span>{title} ({count})</span>
            </div>
            {isExpanded && <div className="browser-section-content">{content}</div>}
        </div>
    );

    const renderObjectRefSimple = (raw: string): React.ReactNode => {
        const { display, objectId } = normalizeObjectRef(raw);

        // Look up the object name and $ name
        const objData = objectId ? objects.find(o => o.obj === objectId) : null;
        const dollarName = objectId ? getDollarName(objectId) : null;

        let badgeText = "";
        if (dollarName) {
            badgeText = `$${dollarName} / `;
        }
        badgeText += display;

        const tooltip = objData?.name || null;

        if (!objectId) {
            return (
                <span className="object-ref-badge" title={tooltip || undefined}>
                    {badgeText}
                </span>
            );
        }
        return (
            <button
                type="button"
                className="object-ref-badge clickable"
                onClick={() => onNavigate(objectId)}
                title={tooltip || undefined}
            >
                {badgeText}
            </button>
        );
    };

    return (
        <div className="h-full flex-col bg-secondary">
            {/* Title bar */}
            <div className="editor-title-bar">
                <h3 className="editor-title" style={{ alignItems: "baseline" }}>
                    <span className="font-bold">Object info</span>
                    <span
                        className="text-secondary font-mono"
                        style={{
                            fontSize: "0.9em",
                            fontWeight: "normal",
                            textAlign: "center",
                            flex: 1,
                            marginLeft: "var(--space-sm)",
                            marginRight: "var(--space-sm)",
                        }}
                    >
                        {(() => {
                            const dollarName = getDollarName(object.obj);
                            let text = "";
                            if (dollarName) {
                                text = `$${dollarName} / `;
                            }
                            text += normalizeObjectRef(object.obj).display;
                            if (object.name) {
                                text += ` ("${object.name}")`;
                            }
                            return text;
                        })()}
                    </span>
                </h3>
                <div className="flex gap-sm" style={{ flexWrap: "nowrap" }}>
                    <button
                        type="button"
                        className="btn btn-sm btn-success"
                        onClick={onCreateChild}
                        disabled={!object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle}
                        style={{
                            cursor: !object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle
                                ? "not-allowed"
                                : "pointer",
                            opacity: !object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle
                                ? 0.6
                                : 1,
                            whiteSpace: "nowrap",
                        }}
                    >
                        Create Child
                    </button>
                    <button
                        type="button"
                        className="btn btn-sm btn-warning"
                        onClick={onRecycle}
                        disabled={!object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle}
                        style={{
                            cursor: !object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle
                                ? "not-allowed"
                                : "pointer",
                            opacity: !object || object.obj === "-1" || isSubmittingCreate || isSubmittingRecycle
                                ? 0.6
                                : 1,
                            whiteSpace: "nowrap",
                        }}
                    >
                        Recycle
                    </button>
                    <button
                        type="button"
                        className="btn btn-sm"
                        onClick={onDumpObject}
                        disabled={!object || object.obj === "-1"}
                        style={{
                            cursor: !object || object.obj === "-1" ? "not-allowed" : "pointer",
                            opacity: !object || object.obj === "-1" ? 0.6 : 1,
                            whiteSpace: "nowrap",
                        }}
                        title="Export object definition to .moo file"
                    >
                        Export Objdef
                    </button>
                    <button
                        type="button"
                        className="btn btn-sm"
                        onClick={onReloadObject}
                        disabled={!object || object.obj === "-1" || isSubmittingReload}
                        style={{
                            cursor: !object || object.obj === "-1" || isSubmittingReload
                                ? "not-allowed"
                                : "pointer",
                            opacity: !object || object.obj === "-1" || isSubmittingReload ? 0.6 : 1,
                            whiteSpace: "nowrap",
                        }}
                        title="Reload object definition from .moo file"
                    >
                        Reload Objdef
                    </button>
                </div>
            </div>

            {/* Content area with metadata and hierarchy */}
            <div className="flex-1 overflow-auto">
                {/* Object metadata section */}
                <div
                    className="p-md bg-tertiary border-top border-bottom flex-wrap"
                    style={{ fontSize: "0.9em", display: "flex", gap: "var(--space-md)", alignItems: "center" }}
                >
                    {/* Name editor */}
                    <div className="flex gap-sm items-center" style={{ gap: "6px" }}>
                        <span className="text-secondary" style={{ fontFamily: "var(--font-ui)" }}>
                            Name:
                        </span>
                        <input
                            type="text"
                            value={editingName}
                            onChange={(e) => onNameChange(e.target.value)}
                            disabled={isSavingName}
                            className="font-mono border rounded-sm"
                            style={{
                                padding: "2px 6px",
                                fontSize: "0.95em",
                                minWidth: "120px",
                            }}
                            onKeyDown={(e) => {
                                if (e.key === "Enter") {
                                    onNameSave();
                                } else if (e.key === "Escape") {
                                    onNameChange(object.name);
                                }
                            }}
                        />
                        <button
                            type="button"
                            className="btn btn-sm"
                            onClick={onNameSave}
                            disabled={isSavingName || editingName === object.name}
                            style={{
                                backgroundColor: isSavingName || editingName === object.name
                                    ? "var(--color-bg-secondary)"
                                    : "var(--color-button-primary)",
                                color: isSavingName || editingName === object.name
                                    ? "var(--color-text-secondary)"
                                    : "white",
                                cursor: isSavingName || editingName === object.name ? "not-allowed" : "pointer",
                                opacity: isSavingName || editingName === object.name ? 0.6 : 1,
                            }}
                        >
                            {isSavingName ? "💾" : "💾"}
                        </button>
                    </div>

                    {/* Separator bar */}
                    <div style={{ width: "1px", height: "20px", backgroundColor: "var(--color-border-medium)" }} />

                    {/* Flags */}
                    <div className="flex gap-sm items-center" style={{ gap: "6px" }}>
                        <span className="text-secondary" style={{ fontFamily: "var(--font-ui)" }}>
                            Flags:
                        </span>
                        <button
                            type="button"
                            onClick={onEditFlags}
                            style={{
                                background: "none",
                                fontFamily: "var(--font-mono)",
                                border: "1px solid var(--color-border-medium)",
                                borderRadius: "var(--radius-sm)",
                                padding: "2px 6px",
                                fontSize: "0.95em",
                                color: "var(--color-text-primary)",
                                cursor: "pointer",
                            }}
                        >
                            {formatObjectFlags(object.flags) || "none"}
                        </button>
                    </div>

                    {/* Separator bar */}
                    <div
                        style={{
                            width: "1px",
                            height: "20px",
                            backgroundColor: "var(--color-border-medium)",
                        }}
                    />

                    {/* Owner */}
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <span style={{ color: "var(--color-text-secondary)", fontFamily: "var(--font-ui)" }}>
                            Owner:
                        </span>
                        {renderObjectRefSimple(object.owner)}
                    </div>

                    {/* Separator bar */}
                    <div
                        style={{
                            width: "1px",
                            height: "20px",
                            backgroundColor: "var(--color-border-medium)",
                        }}
                    />

                    {/* Location */}
                    <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <span style={{ color: "var(--color-text-secondary)", fontFamily: "var(--font-ui)" }}>
                            Location:
                        </span>
                        {renderObjectRefSimple(object.location)}
                    </div>
                </div>

                {/* Action message */}
                {actionMessage && (
                    <div
                        style={{
                            margin: "8px",
                            marginBottom: "8px",
                            padding: "6px 8px",
                            borderRadius: "var(--radius-sm)",
                            backgroundColor: "rgba(16, 185, 129, 0.15)",
                            border: "1px solid rgba(16, 185, 129, 0.35)",
                            color: "var(--color-text-primary)",
                            fontSize: "11px",
                        }}
                    >
                        {actionMessage}
                    </div>
                )}

                {/* Hierarchy sections */}
                <div style={{ padding: "8px", fontSize: "11px" }}>
                    {isLoading ? <div style={{ color: "var(--color-text-secondary)" }}>Loading hierarchy...</div> : (
                        <>
                            {/* Contents Section */}
                            {contents.length > 0 && renderCollapsibleSection(
                                "Contents",
                                contents.length,
                                contentsExpanded,
                                setContentsExpanded,
                                <div style={listStyle}>
                                    {contents.map((contentId, idx) => (
                                        <React.Fragment key={`content-${contentId}-${idx}`}>
                                            {renderObjectLink(contentId)}
                                        </React.Fragment>
                                    ))}
                                </div>,
                            )}

                            {/* Parent & Children Section */}
                            <div style={sectionStyle}>
                                <div
                                    style={{
                                        ...sectionHeaderStyle,
                                        cursor: "default",
                                        backgroundColor: "var(--color-bg-secondary)",
                                    }}
                                >
                                    <span>Parent & Children</span>
                                </div>
                                <div style={sectionContentStyle}>
                                    <div style={{ marginBottom: "4px" }}>
                                        <strong style={{ marginRight: "4px" }}>Parent:</strong>
                                        {renderObjectLink(object.parent)}
                                    </div>
                                    <div>
                                        <button
                                            type="button"
                                            onClick={() => setChildrenExpanded(!childrenExpanded)}
                                            style={{
                                                background: "none",
                                                border: "none",
                                                padding: "0",
                                                cursor: "pointer",
                                                display: "inline-flex",
                                                alignItems: "center",
                                                gap: "4px",
                                                color: "var(--color-text-primary)",
                                                fontWeight: 600,
                                                fontSize: "11px",
                                            }}
                                        >
                                            <span style={{ fontSize: "9px" }}>{childrenExpanded ? "▼" : "▶"}</span>
                                            <span>Children ({children.length})</span>
                                        </button>
                                        {childrenExpanded && (
                                            <div style={{ ...listStyle, marginTop: "4px" }}>
                                                {children.length === 0
                                                    ? (
                                                        <span
                                                            style={{
                                                                color: "var(--color-text-secondary)",
                                                                fontStyle: "italic",
                                                            }}
                                                        >
                                                            none
                                                        </span>
                                                    )
                                                    : (
                                                        children.map((childId, idx) => (
                                                            <React.Fragment key={`child-${childId}-${idx}`}>
                                                                {renderObjectLink(childId)}
                                                            </React.Fragment>
                                                        ))
                                                    )}
                                            </div>
                                        )}
                                    </div>
                                </div>
                            </div>

                            {/* Ancestors Section */}
                            {ancestors.length > 0 && renderCollapsibleSection(
                                "Ancestors",
                                ancestors.length,
                                ancestorsExpanded,
                                setAncestorsExpanded,
                                <div style={listStyle}>
                                    {ancestors.map((ancestorId, idx) => (
                                        <React.Fragment key={`ancestor-${ancestorId}-${idx}`}>
                                            {renderObjectLink(ancestorId)}
                                        </React.Fragment>
                                    ))}
                                </div>,
                            )}

                            {/* Descendants Section */}
                            {descendants.length > 0 && renderCollapsibleSection(
                                "Descendants",
                                descendants.length,
                                descendantsExpanded,
                                setDescendantsExpanded,
                                <div style={listStyle}>
                                    {descendants.map((descendantId, idx) => (
                                        <React.Fragment key={`descendant-${descendantId}-${idx}`}>
                                            {renderObjectLink(descendantId)}
                                        </React.Fragment>
                                    ))}
                                </div>,
                            )}
                        </>
                    )}
                </div>
            </div>
        </div>
    );
};
