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

import React, { createContext, useContext } from "react";
import { AuthState, useAuth } from "../hooks/useAuth";
import { AuthSession, ReconnectCredentials } from "../lib/auth-session";

interface AuthContextType {
    authState: AuthState;
    connect: (
        mode: "connect" | "create",
        username: string,
        password: string,
        encryptPassword?: string,
    ) => Promise<void>;
    disconnect: () => void;
    establishSession: (session: AuthSession, isInitialAttach?: boolean) => void;
    setPlayerConnected: (connected: boolean) => void;
    updateReconnectCredentials: (credentials: ReconnectCredentials) => void;
    rotatePlayerIdentity: (playerOid: string, authToken: string) => Promise<void>;
    clearInitialAttach: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

interface AuthProviderProps {
    children: React.ReactNode;
    showMessage: (message: string, duration?: number) => void;
}

export const AuthProvider: React.FC<AuthProviderProps> = ({ children, showMessage }) => {
    const authHook = useAuth(showMessage);

    return (
        <AuthContext.Provider value={authHook}>
            {children}
        </AuthContext.Provider>
    );
};

export const useAuthContext = (): AuthContextType => {
    const context = useContext(AuthContext);
    if (context === undefined) {
        throw new Error("useAuthContext must be used within an AuthProvider");
    }
    return context;
};
