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

import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";

interface MessageBoardProps {
    className?: string;
}

interface SystemMessage {
    message: string;
    visible: boolean;
}

interface SystemMessageContextType {
    systemMessage: SystemMessage;
    showMessage: (message: string, duration?: number) => void;
    hideMessage: () => void;
}

const SystemMessageContext = createContext<SystemMessageContextType | undefined>(undefined);

export const SystemMessageProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [systemMessage, setSystemMessage] = useState<SystemMessage>({
        message: "",
        visible: false,
    });
    const dismissalTimerRef = useRef<number | null>(null);

    const clearDismissalTimer = useCallback(() => {
        if (dismissalTimerRef.current === null) return;
        window.clearTimeout(dismissalTimerRef.current);
        dismissalTimerRef.current = null;
    }, []);

    const showMessage = useCallback((message: string, duration: number = 5) => {
        clearDismissalTimer();
        setSystemMessage({ message, visible: true });

        dismissalTimerRef.current = window.setTimeout(() => {
            setSystemMessage(prev => ({ ...prev, visible: false }));
            dismissalTimerRef.current = null;
        }, duration * 1000);
    }, [clearDismissalTimer]);

    const hideMessage = useCallback(() => {
        clearDismissalTimer();
        setSystemMessage(prev => ({ ...prev, visible: false }));
    }, [clearDismissalTimer]);

    useEffect(() => {
        return () => clearDismissalTimer();
    }, [clearDismissalTimer]);

    return (
        <SystemMessageContext.Provider value={{ systemMessage, showMessage, hideMessage }}>
            {children}
        </SystemMessageContext.Provider>
    );
};

export const useSystemMessage = (): SystemMessageContextType => {
    const context = useContext(SystemMessageContext);
    if (!context) {
        throw new Error("useSystemMessage must be used within a SystemMessageProvider");
    }
    return context;
};

/**
 * Displays a temporary notification message that automatically disappears.
 *
 * @param props - Component properties
 * @returns A React component
 */
export const MessageBoard: React.FC<
    MessageBoardProps & {
        message: string;
        visible: boolean;
    }
> = ({ message, visible, className = "" }) => {
    return (
        <div
            className={`message_board ${className} ${!visible ? "hidden" : ""}`}
            role="status"
            aria-live="polite"
            aria-atomic="true"
        >
            {message}
        </div>
    );
};
