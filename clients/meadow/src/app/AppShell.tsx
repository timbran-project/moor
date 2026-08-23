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

import React from "react";
import { SystemMessageProvider, useSystemMessage } from "../components/MessageBoard";
import { ThemeProvider } from "../components/ThemeProvider";
import { ToastProvider } from "../components/Toast";
import { AuthProvider } from "../context/AuthContext";
import { useAuthContext } from "../context/AuthContext";
import { EncryptionProvider } from "../context/EncryptionContext";
import { ExternalNavigationProvider } from "../context/ExternalNavigationContext";
import { PresentationProvider } from "../context/PresentationContext";
import { SessionCoordinator } from "../session/SessionCoordinator";
import { MainSurface } from "./MainSurface";

/**
 * Composes the application's provider stack and top-level layout:
 * theme → toasts → system messages → external navigation policy →
 * authentication → presentations → encryption → session (WebSocket) → surface.
 */
export const AppShell: React.FC = () => {
    return (
        <ThemeProvider>
            <ToastProvider>
                <SystemMessageProvider>
                    <ExternalNavigationProvider>
                        <AuthenticatedArea />
                    </ExternalNavigationProvider>
                </SystemMessageProvider>
            </ToastProvider>
        </ThemeProvider>
    );
};

function AuthenticatedArea() {
    const { showMessage } = useSystemMessage();

    return (
        <AuthProvider showMessage={showMessage}>
            <PresentationProvider>
                <EncryptionBoundary />
            </PresentationProvider>
        </AuthProvider>
    );
}

function EncryptionBoundary() {
    const { authState } = useAuthContext();

    return (
        <EncryptionProvider
            authToken={authState.player?.historyAuthToken || null}
            playerOid={authState.player?.historyOid || null}
        >
            <SessionCoordinator>
                <MainSurface />
            </SessionCoordinator>
        </EncryptionProvider>
    );
}
