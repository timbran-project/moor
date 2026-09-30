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

export type RecoveryScope = "application" | "interface" | "transcript" | "optional-surface";

const SURFACE_NAMES = new Set([
    "verb editor",
    "text editor",
    "property editor",
    "property value editor",
    "object browser",
    "evaluation panel",
]);

const COMPONENT_NAMES = new Set([
    "App",
    "AppShell",
    "AuthenticatedArea",
    "EncryptionBoundary",
    "ThemeProvider",
    "ToastProvider",
    "SystemMessageProvider",
    "ExternalNavigationProvider",
    "AuthProvider",
    "PresentationProvider",
    "EncryptionProvider",
    "SessionCoordinator",
    "WebSocketProvider",
    "MainSurface",
    "Narrative",
    "OutputWindow",
    "ContentRenderer",
    "LazySurface",
    "VerbEditor",
    "TextEditor",
    "PropertyEditor",
    "PropertyValueEditorWindow",
    "ObjectBrowser",
    "EvalPanel",
    "TopDock",
    "LeftDock",
    "RightDock",
    "BottomDock",
]);

/** Only application-owned labels are recorded; exception strings and URLs can contain credentials or output. */
export function reportUiFailure(
    scope: RecoveryScope,
    error: unknown,
    componentStack?: string | null,
    surface?: string,
) {
    let kind = "unknown";
    try {
        if (error instanceof TypeError) kind = "type";
        else if (error instanceof RangeError) kind = "range";
        else if (error instanceof ReferenceError) kind = "reference";
        else if (error instanceof SyntaxError) kind = "syntax";
        else if (error instanceof Error) kind = "error";
    } catch {
        // A thrown proxy need not allow prototype inspection.
    }
    const components = (componentStack ?? "").split("\n").slice(0, 32)
        .map(line => /^\s*(?:at\s+)?([A-Za-z_$][\w$]*)(?:\s|@|$)/.exec(line)?.[1])
        .filter((name): name is string => !!name && COMPONENT_NAMES.has(name))
        .slice(0, 8);
    const diagnostic = {
        code: "MEADOW_UI_FAILURE",
        scope,
        kind,
        ...(surface && SURFACE_NAMES.has(surface) ? { surface } : {}),
        revision: typeof __GIT_HASH__ === "string" ? __GIT_HASH__ : "development",
        time: new Date().toISOString(),
        components,
    };
    console.error("[Meadow UI failure]", diagnostic);
    return diagnostic;
}
