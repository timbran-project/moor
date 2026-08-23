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

import { useCallback, useEffect, useRef, useState } from "react";
import { usePresentationContext } from "../context/PresentationContext";
import { usePropertyEditor } from "../hooks/usePropertyEditor";
import { usePropertyValueEditor } from "../hooks/usePropertyValueEditor";
import { useTextEditor } from "../hooks/useTextEditor";
import { useVerbEditor } from "../hooks/useVerbEditor";
import { MoorVar } from "../lib/MoorVar";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { stringToCurie } from "../lib/var";
import { useEditorLaunchBridge } from "../session/editorLaunchBridge";
import { Presentation } from "../types/presentation";

export interface PresentationRoutingArgs {
    authToken: string | null;
    showMessage: (message: string, duration?: number) => void;
    canUseObjectBrowser: boolean;
    isObjectBrowserOpen: boolean;
    onOpenObjectBrowserRequested: () => void;
    onObjectBrowserPresentationsCleared: () => void;
}

/**
 * Owns interpretation of server presentations into editor and dialog
 * sessions. Each presentation family (verb editor, property editor, property
 * value editor, text editor, profile setup, object browser) has a dedicated
 * effect that opens, supersedes, or closes its sessions, and close handlers
 * that notify the server by dismissing the corresponding presentations.
 */
export const usePresentationRouting = ({
    authToken,
    showMessage,
    canUseObjectBrowser,
    isObjectBrowserOpen,
    onOpenObjectBrowserRequested,
    onObjectBrowserPresentationsCleared,
}: PresentationRoutingArgs) => {
    const bridge = useEditorLaunchBridge();
    const {
        dismissPresentation,
        getVerbEditorPresentations,
        getPropertyEditorPresentations,
        getPropertyValueEditorPresentations,
        getObjectBrowserPresentations,
        getTextEditorPresentations,
        getProfileSetupPresentations,
        clearAll: clearAllPresentations,
    } = usePresentationContext();

    // Verb editor state
    const {
        editorSession,
        editorSessions,
        activeSessionIndex,
        launchVerbEditor,
        closeEditor,
        showVerbEditor,
        previousSession,
        nextSession,
    } = useVerbEditor();

    // Property editor state
    const {
        propertyEditorSession,
        launchPropertyEditor,
        closePropertyEditor,
        showPropertyEditor,
    } = usePropertyEditor();
    const {
        propertyValueEditorSession,
        launchPropertyValueEditor,
        refreshPropertyValueEditor,
        closePropertyValueEditor,
    } = usePropertyValueEditor();

    const {
        textEditorSession,
        showTextEditor,
        closeTextEditor,
    } = useTextEditor();

    // Expose editor launchers to the narrative pipeline for MCP edit commands
    useEffect(() => {
        bridge.current.showVerbEditor = showVerbEditor;
        bridge.current.showPropertyEditor = showPropertyEditor;
    }, [bridge, showVerbEditor, showPropertyEditor]);

    const [objectBrowserPresentationIds, setObjectBrowserPresentationIds] = useState<string[]>([]);
    const [objectBrowserLinkedToPresentation, setObjectBrowserLinkedToPresentation] = useState(false);
    const [objectBrowserFocusedObjectCurie, setObjectBrowserFocusedObjectCurie] = useState<string | undefined>();

    const [profileSetupPresentation, setProfileSetupPresentation] = useState<Presentation | null>(null);
    const closedProfileSetupPresentationsRef = useRef<Set<string>>(new Set());
    const [profileRefreshKey, setProfileRefreshKey] = useState(0);

    const textEditorPresentationId = textEditorSession?.presentationId;
    const closedTextEditorPresentationsRef = useRef<Set<string>>(new Set());

    // Custom close handler for verb editor that also dismisses presentations
    const handleVerbEditorClose = useCallback(() => {
        // If there are multiple sessions, close only the current one
        if (editorSessions.length > 1 && editorSession) {
            // Dismiss the presentation for the current session
            if (editorSession.presentationId && authToken) {
                dismissPresentation(editorSession.presentationId, authToken);
            }
            // Close just this session
            closeEditor(editorSession.id);
        } else {
            // Last session - dismiss all presentations and close all
            const verbEditorPresentations = getVerbEditorPresentations();
            if (verbEditorPresentations.length > 0 && authToken) {
                verbEditorPresentations.forEach(presentation => {
                    dismissPresentation(presentation.id, authToken);
                });
            }
            closeEditor();
        }
    }, [authToken, closeEditor, dismissPresentation, editorSession, editorSessions.length, getVerbEditorPresentations]);

    const propertyEditorPresentationId = propertyEditorSession?.presentationId;

    const handlePropertyEditorClose = useCallback(() => {
        if (propertyEditorPresentationId && authToken) {
            dismissPresentation(propertyEditorPresentationId, authToken);
        }
        closePropertyEditor();
    }, [authToken, closePropertyEditor, dismissPresentation, propertyEditorPresentationId]);

    const propertyValueEditorPresentationId = propertyValueEditorSession?.presentationId;

    const handlePropertyValueEditorClose = useCallback(() => {
        if (propertyValueEditorPresentationId && authToken) {
            dismissPresentation(propertyValueEditorPresentationId, authToken);
        }
        closePropertyValueEditor();
    }, [authToken, closePropertyValueEditor, dismissPresentation, propertyValueEditorPresentationId]);

    const handleTextEditorClose = useCallback(() => {
        // Track this presentation as closed to prevent the effect from reopening it
        if (textEditorPresentationId) {
            closedTextEditorPresentationsRef.current.add(textEditorPresentationId);
        }

        // Notify the server by calling the verb with 'close symbol
        if (textEditorSession && authToken) {
            const closeArgs = MoorVar.buildTextEditorCloseArgs(textEditorSession.sessionId);
            invokeVerbFlatBuffer(
                authToken,
                textEditorSession.objectCurie,
                textEditorSession.verbName,
                closeArgs,
            ).catch(err => console.error("Failed to send close notification:", err));
        }

        closeTextEditor();
        if (textEditorPresentationId && authToken) {
            dismissPresentation(textEditorPresentationId, authToken);
        }
    }, [authToken, closeTextEditor, dismissPresentation, textEditorPresentationId, textEditorSession]);

    // Handle verb editor presentations from server
    useEffect(() => {
        const verbEditorPresentations = getVerbEditorPresentations();

        if (verbEditorPresentations.length > 0 && authToken) {
            for (const presentation of verbEditorPresentations) {
                const existingSession = editorSessions.find(s => s.presentationId === presentation.id);

                if (!existingSession) {
                    const rawObjectId = presentation.attrs.object || presentation.attrs.objectCurie;
                    const verbName = presentation.attrs.verb || presentation.attrs.verbName;

                    if (rawObjectId && verbName) {
                        const objectCurie = stringToCurie(rawObjectId);

                        launchVerbEditor(
                            presentation.title,
                            objectCurie,
                            verbName,
                            authToken,
                            presentation.id,
                        ).catch((error) => {
                            const errorMsg = `Failed to open verb editor: ${error.message}`;
                            console.log("[VerbEditor] Showing error:", errorMsg);
                            showMessage(errorMsg, 5);
                            if (authToken) {
                                dismissPresentation(presentation.id, authToken);
                            }
                        });
                    }
                }
            }
        }

        for (const session of editorSessions) {
            if (session.presentationId && !session.uploadAction) {
                const hasPresentation = verbEditorPresentations.some(p => p.id === session.presentationId);
                if (!hasPresentation) {
                    closeEditor(session.id);
                }
            }
        }
    }, [
        authToken,
        closeEditor,
        dismissPresentation,
        editorSessions,
        getVerbEditorPresentations,
        launchVerbEditor,
        showMessage,
    ]);

    // Handle property editor presentations from server
    useEffect(() => {
        if (!authToken) {
            return;
        }

        const propertyPresentations = getPropertyEditorPresentations();

        for (const presentation of propertyPresentations) {
            if (propertyEditorSession?.presentationId === presentation.id) {
                continue;
            }

            const rawObjectId = presentation.attrs.object || presentation.attrs.objectCurie;
            const propertyName = presentation.attrs.property || presentation.attrs.propertyName;

            if (!rawObjectId || !propertyName) {
                showMessage("Property editor presentation missing object/property metadata", 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            const objectCurie = stringToCurie(rawObjectId);
            if (!objectCurie) {
                showMessage(`Cannot parse object reference ${rawObjectId} for property editor`, 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            launchPropertyEditor(
                presentation.title || `${objectCurie}.${propertyName}`,
                objectCurie,
                propertyName,
                authToken,
                presentation.id,
            ).catch((error: unknown) => {
                const message = error instanceof Error ? error.message : String(error);
                const errorMsg = `Failed to open property editor: ${message}`;
                console.log("[PropertyEditor] Showing error:", errorMsg);
                showMessage(errorMsg, 5);
                dismissPresentation(presentation.id, authToken);
            });

            break;
        }

        if (propertyEditorSession?.presentationId) {
            const hasPresentation = propertyPresentations.some(
                presentation => presentation.id === propertyEditorSession.presentationId,
            );
            if (!hasPresentation) {
                closePropertyEditor();
            }
        }
    }, [
        authToken,
        closePropertyEditor,
        dismissPresentation,
        getPropertyEditorPresentations,
        launchPropertyEditor,
        propertyEditorSession,
        showMessage,
    ]);

    // Handle property value editor presentations from server
    useEffect(() => {
        if (!authToken) {
            return;
        }

        const valuePresentations = getPropertyValueEditorPresentations();

        for (const presentation of valuePresentations) {
            if (propertyValueEditorSession?.presentationId === presentation.id) {
                continue;
            }

            const rawObjectId = presentation.attrs.object || presentation.attrs.objectCurie;
            const propertyName = presentation.attrs.property || presentation.attrs.propertyName;

            if (!rawObjectId || !propertyName) {
                showMessage("Property value editor presentation missing object/property metadata", 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            const objectCurie = stringToCurie(rawObjectId);
            if (!objectCurie) {
                showMessage(`Cannot parse object reference ${rawObjectId} for property value editor`, 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            launchPropertyValueEditor(
                presentation.title || `${objectCurie}.${propertyName}`,
                objectCurie,
                propertyName,
                authToken,
                presentation.id,
            ).catch((error: unknown) => {
                const message = error instanceof Error ? error.message : String(error);
                const errorMsg = `Failed to open property value editor: ${message}`;
                console.log("[PropertyValueEditor] Showing error:", errorMsg);
                showMessage(errorMsg, 5);
                dismissPresentation(presentation.id, authToken);
            });

            break;
        }

        if (propertyValueEditorSession?.presentationId) {
            const hasPresentation = valuePresentations.some(
                presentation => presentation.id === propertyValueEditorSession.presentationId,
            );
            if (!hasPresentation) {
                closePropertyValueEditor();
            }
        }
    }, [
        authToken,
        closePropertyValueEditor,
        dismissPresentation,
        getPropertyValueEditorPresentations,
        launchPropertyValueEditor,
        propertyValueEditorSession,
        showMessage,
    ]);

    // Handle object browser presentations from server
    useEffect(() => {
        const objectPresentations = getObjectBrowserPresentations();
        setObjectBrowserPresentationIds(objectPresentations.map(presentation => presentation.id));

        if (objectPresentations.length === 0) {
            if (objectBrowserLinkedToPresentation) {
                onObjectBrowserPresentationsCleared();
                setObjectBrowserLinkedToPresentation(false);
                setObjectBrowserFocusedObjectCurie(undefined);
            }
            return;
        }

        if (!canUseObjectBrowser) {
            objectPresentations.forEach(presentation => {
                showMessage("Object browser is unavailable for this account", 5);
                if (authToken) {
                    dismissPresentation(presentation.id, authToken);
                }
            });
            return;
        }

        // Use the most recent presentation and dismiss old ones
        const latestPresentation = objectPresentations[objectPresentations.length - 1];
        const objectCurie = latestPresentation.attrs.object || latestPresentation.attrs.objectCurie;
        if (objectCurie) {
            setObjectBrowserFocusedObjectCurie(objectCurie);
        }

        // Dismiss superseded presentations
        if (objectPresentations.length > 1 && authToken) {
            for (let i = 0; i < objectPresentations.length - 1; i++) {
                dismissPresentation(objectPresentations[i].id, authToken);
            }
        }

        // Open browser if not already open
        if (!isObjectBrowserOpen) {
            onOpenObjectBrowserRequested();
            setObjectBrowserLinkedToPresentation(true);
        }
    }, [
        authToken,
        canUseObjectBrowser,
        dismissPresentation,
        getObjectBrowserPresentations,
        onOpenObjectBrowserRequested,
        isObjectBrowserOpen,
        objectBrowserLinkedToPresentation,
        onObjectBrowserPresentationsCleared,
        showMessage,
    ]);

    // Handle text editor presentations from server
    useEffect(() => {
        if (!authToken) {
            return;
        }

        const textPresentations = getTextEditorPresentations();

        for (const presentation of textPresentations) {
            if (textEditorSession?.presentationId === presentation.id) {
                continue;
            }

            // Skip presentations that were recently closed (prevents reopening race)
            if (closedTextEditorPresentationsRef.current.has(presentation.id)) {
                // Clean up once we've skipped it
                closedTextEditorPresentationsRef.current.delete(presentation.id);
                continue;
            }

            const rawObjectId = presentation.attrs.object || presentation.attrs.objectCurie;
            const verbName = presentation.attrs.verb || presentation.attrs.verbName;

            if (!rawObjectId || !verbName) {
                showMessage("Text editor presentation missing object/verb metadata", 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            const objectCurie = stringToCurie(rawObjectId);
            if (!objectCurie) {
                showMessage(`Cannot parse object reference ${rawObjectId} for text editor`, 5);
                dismissPresentation(presentation.id, authToken);
                continue;
            }

            // Get optional session ID
            const sessionId = presentation.attrs.session_id || undefined;

            // Get content type (default to text/plain)
            const contentType = presentation.attrs.content_type === "text/djot" ? "text/djot" : "text/plain";

            // Get text mode (default to list)
            const textMode = presentation.attrs.text_mode === "string" ? "string" : "list";

            // Get description (optional)
            const description = presentation.attrs.description || "";

            // Convert content to string (may be string or string[])
            const content = Array.isArray(presentation.content)
                ? presentation.content.join("\n")
                : (presentation.content || "");

            // Show the text editor with content from the presentation
            showTextEditor(
                presentation.id,
                presentation.title || "Edit Text",
                description,
                objectCurie,
                verbName,
                sessionId,
                content,
                contentType,
                textMode,
                presentation.id,
            );

            break;
        }

        if (textEditorSession?.presentationId) {
            const hasPresentation = textPresentations.some(
                presentation => presentation.id === textEditorSession.presentationId,
            );
            if (!hasPresentation) {
                closeTextEditor();
            }
        }
    }, [
        authToken,
        closeTextEditor,
        dismissPresentation,
        getTextEditorPresentations,
        showTextEditor,
        showMessage,
        textEditorSession,
    ]);

    // Handle profile-setup presentations from server
    useEffect(() => {
        const profilePresentations = getProfileSetupPresentations();

        if (profilePresentations.length === 0) {
            if (profileSetupPresentation) {
                setProfileSetupPresentation(null);
            }
            return;
        }

        // Filter out presentations we've already closed
        const activePresentations = profilePresentations.filter(
            p => !closedProfileSetupPresentationsRef.current.has(p.id),
        );

        if (activePresentations.length === 0) {
            if (profileSetupPresentation) {
                setProfileSetupPresentation(null);
            }
            return;
        }

        // Use the most recent presentation
        const latestPresentation = activePresentations[activePresentations.length - 1];

        // Dismiss older presentations
        if (activePresentations.length > 1 && authToken) {
            for (let i = 0; i < activePresentations.length - 1; i++) {
                dismissPresentation(activePresentations[i].id, authToken);
            }
        }

        // Only set if it's a different presentation
        if (!profileSetupPresentation || profileSetupPresentation.id !== latestPresentation.id) {
            setProfileSetupPresentation(latestPresentation);
        }
    }, [authToken, dismissPresentation, getProfileSetupPresentations, profileSetupPresentation]);

    // Handlers for profile setup panel
    const handleProfileSetupComplete = useCallback(() => {
        if (profileSetupPresentation) {
            closedProfileSetupPresentationsRef.current.add(profileSetupPresentation.id);
            if (authToken) {
                dismissPresentation(profileSetupPresentation.id, authToken);
            }
        }
        setProfileSetupPresentation(null);
        // Trigger refresh of profile data in AccountMenu
        setProfileRefreshKey((k) => k + 1);
    }, [authToken, dismissPresentation, profileSetupPresentation]);

    const handleProfileSetupSkip = useCallback(() => {
        if (profileSetupPresentation) {
            closedProfileSetupPresentationsRef.current.add(profileSetupPresentation.id);
            if (authToken) {
                dismissPresentation(profileSetupPresentation.id, authToken);
            }
        }
        setProfileSetupPresentation(null);
    }, [authToken, dismissPresentation, profileSetupPresentation]);

    /** Dismisses every presentation currently linked to the object browser. */
    const dismissAllObjectBrowserPresentations = useCallback(() => {
        if (authToken) {
            objectBrowserPresentationIds.forEach(id => dismissPresentation(id, authToken));
        }
    }, [authToken, dismissPresentation, objectBrowserPresentationIds]);

    /** Drops authority-scoped editor state after a player switch. */
    const resetForPlayerSwitch = useCallback(() => {
        closeEditor();
        closePropertyEditor();
        closePropertyValueEditor();
        closeTextEditor();
        clearAllPresentations();
    }, [clearAllPresentations, closeEditor, closePropertyEditor, closePropertyValueEditor, closeTextEditor]);

    return {
        // Verb editors
        editorSession,
        editorSessions,
        activeSessionIndex,
        previousSession,
        nextSession,
        showVerbEditor,
        handleVerbEditorClose,
        closeEditor,
        // Property editors
        propertyEditorSession,
        showPropertyEditor,
        handlePropertyEditorClose,
        closePropertyEditor,
        // Property value editors
        propertyValueEditorSession,
        refreshPropertyValueEditor,
        handlePropertyValueEditorClose,
        closePropertyValueEditor,
        // Text editors
        textEditorSession,
        handleTextEditorClose,
        closeTextEditor,
        // Object browser linkage
        objectBrowserFocusedObjectCurie,
        dismissAllObjectBrowserPresentations,
        // Profile setup
        profileSetupPresentation,
        profileRefreshKey,
        handleProfileSetupComplete,
        handleProfileSetupSkip,
        // Lifecycle
        resetForPlayerSwitch,
    };
};
