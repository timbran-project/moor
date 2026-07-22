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
import { ContentRenderer } from "./ContentRenderer";

export interface InspectAction {
    label: string;
    verb?: string;
    target?: string; // CURIE like "oid:123"
    args?: string[]; // Optional args (object refs and/or plain strings)
    kind?: "invoke" | "command";
    command?: string;
    inputType?: "text";
    inputPrompt?: string;
    inputPlaceholder?: string;
    resultMode?: "popover" | "narrative" | "panel";
    panelTarget?:
        | "left"
        | "right"
        | "top"
        | "bottom"
        | "tools"
        | "status"
        | "inventory"
        | "navigation"
        | "communication";
    panelId?: string;
    panelTitle?: string;
}

export interface InspectData {
    title: string;
    description: string;
    actions?: InspectAction[];
}

/** Output event from verb invocation */
export interface ActionOutputEvent {
    eventType: string;
    event: any;
}

interface InspectPopoverProps {
    data: InspectData;
    position: { x: number; y: number };
    onClose: () => void;
    onAction: (action: InspectAction, inputValue?: string) => Promise<ActionOutputEvent[]>;
    autoCloseMs?: number;
    isPreview?: boolean;
}

const DEFAULT_AUTO_CLOSE_MS = 5000;

export const InspectPopover: React.FC<InspectPopoverProps> = ({
    data,
    position,
    onClose,
    onAction,
    autoCloseMs = DEFAULT_AUTO_CLOSE_MS,
    isPreview = false,
}) => {
    const popoverRef = useRef<HTMLDivElement>(null);
    const autoCloseTimerRef = useRef<number | null>(null);

    // Reset auto-close timer
    const resetAutoClose = useCallback(() => {
        if (autoCloseTimerRef.current) {
            clearTimeout(autoCloseTimerRef.current);
        }
        autoCloseTimerRef.current = window.setTimeout(() => {
            onClose();
        }, autoCloseMs);
    }, [autoCloseMs, onClose]);

    // Auto-close after inactivity (only for non-preview mode)
    useEffect(() => {
        if (isPreview) return;
        return () => {
            if (autoCloseTimerRef.current) {
                clearTimeout(autoCloseTimerRef.current);
            }
        };
    }, [isPreview]);

    // Close on click outside (only for non-preview mode)
    useEffect(() => {
        if (isPreview) return;

        const handleClickOutside = (e: MouseEvent) => {
            if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
                onClose();
            }
        };

        // Close on escape key
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === "Escape") {
                onClose();
            }
        };

        // Delay adding listener to avoid immediate close from the click that opened it
        const timer = setTimeout(() => {
            document.addEventListener("mousedown", handleClickOutside);
            document.addEventListener("keydown", handleKeyDown);
        }, 10);

        return () => {
            clearTimeout(timer);
            document.removeEventListener("mousedown", handleClickOutside);
            document.removeEventListener("keydown", handleKeyDown);
        };
    }, [onClose, isPreview]);

    // Adjust position to stay within viewport
    useEffect(() => {
        if (!popoverRef.current) return;

        const rect = popoverRef.current.getBoundingClientRect();
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;

        let adjustedX = position.x;
        let adjustedY = position.y;

        // Prevent overflow on right
        if (adjustedX + rect.width > viewportWidth - 16) {
            adjustedX = viewportWidth - rect.width - 16;
        }

        // Prevent overflow on bottom - show above click point if needed
        if (adjustedY + rect.height > viewportHeight - 16) {
            adjustedY = position.y - rect.height - 8;
        }

        // Prevent overflow on left/top
        adjustedX = Math.max(16, adjustedX);
        adjustedY = Math.max(16, adjustedY);

        popoverRef.current.style.left = `${adjustedX}px`;
        popoverRef.current.style.top = `${adjustedY}px`;
    }, [position]);

    // State for feedback messages
    const [feedback, setFeedback] = useState<string[]>([]);
    const [actionsDisabled, setActionsDisabled] = useState(false);

    const handleActionClick = useCallback(async (action: InspectAction) => {
        // Disable immediately to prevent double-clicks
        if (actionsDisabled) return;
        setActionsDisabled(true);
        setFeedback([]);

        try {
            let inputValue: string | undefined;
            if (action.inputType === "text") {
                const response = window.prompt(action.inputPrompt ?? action.label, "");
                if (response === null) {
                    setActionsDisabled(false);
                    return;
                }
                inputValue = response.trim();
                if (!inputValue) {
                    setFeedback(["No input provided."]);
                    setActionsDisabled(false);
                    return;
                }
            }

            const output = await onAction(action, inputValue);

            // Extract text content from NotifyEvents
            const messages: string[] = [];
            for (const event of output) {
                if (event.eventType === "NotifyEvent" && event.event?.value) {
                    const value = event.event.value;
                    if (typeof value === "string") {
                        messages.push(value);
                    } else if (Array.isArray(value)) {
                        messages.push(value.join("\n"));
                    }
                } else if (event.eventType === "TracebackEvent" && event.event?.backtrace) {
                    messages.push(event.event.backtrace.join("\n"));
                }
            }

            if (messages.length > 0) {
                setFeedback(messages);
                setActionsDisabled(false);
            } else {
                onClose();
            }
        } catch (error) {
            setFeedback([`Error: ${error instanceof Error ? error.message : String(error)}`]);
            setActionsDisabled(false);
        }
    }, [actionsDisabled, onAction, onClose]);

    return (
        <div
            ref={popoverRef}
            className={`inspect-popover${isPreview ? " inspect-popover--preview" : ""}`}
            style={{
                position: "fixed",
                left: position.x,
                top: position.y,
                zIndex: 10000,
            }}
        >
            <div className="inspect-popover-header">
                <span className="inspect-popover-title">{data.title}</span>
                {!isPreview && (
                    <button
                        className="inspect-popover-close"
                        onClick={onClose}
                        aria-label="Close"
                    >
                        ×
                    </button>
                )}
            </div>
            <div className="inspect-popover-description">
                {data.description}
            </div>
            {!isPreview && data.actions && data.actions.length > 0 && (
                <div className="inspect-popover-actions">
                    {data.actions.map((action, index) => (
                        <button
                            key={index}
                            className="inspect-popover-action"
                            onClick={() => handleActionClick(action)}
                            disabled={actionsDisabled}
                        >
                            {action.label}
                        </button>
                    ))}
                </div>
            )}
            {feedback.length > 0 && (
                <div className="inspect-popover-feedback">
                    {feedback.map((msg, index) => (
                        <div key={index} className="inspect-popover-feedback-message">
                            <ContentRenderer content={msg} contentType="text/plain" />
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
};
