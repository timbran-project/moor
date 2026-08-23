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

import { createContext, useContext } from "react";

export interface EditorLaunchers {
    showVerbEditor:
        | ((title: string, objectCurie: string, verbName: string, content: string, uploadAction?: string) => void)
        | null;
    showPropertyEditor:
        | ((title: string, objectCurie: string, propertyName: string, content: string, uploadAction?: string) => void)
        | null;
}

export type EditorLaunchBridge = { current: EditorLaunchers };

const emptyLaunchers: EditorLaunchers = {
    showVerbEditor: null,
    showPropertyEditor: null,
};

/**
 * The narrative pipeline (above the WebSocket provider) needs to open editors
 * for MCP edit commands, but the editor launchers are owned by presentation
 * routing below the provider. This bridge is a stable mutable ref shared in
 * both directions without threading props through the whole tree.
 */
export const EditorLaunchBridgeContext = createContext<EditorLaunchBridge | undefined>(undefined);

export const createEditorLaunchBridge = (): EditorLaunchBridge => ({ current: { ...emptyLaunchers } });

export const useEditorLaunchBridge = (): EditorLaunchBridge => {
    const bridge = useContext(EditorLaunchBridgeContext);
    if (!bridge) {
        throw new Error("useEditorLaunchBridge must be used within an EditorLaunchBridgeContext.Provider");
    }
    return bridge;
};
