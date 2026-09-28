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

import React, { useCallback, useEffect, useId, useRef, useState } from "react";

import { useFloatingCard } from "../hooks/useFloatingCard";
import { SuggestionSource } from "../hooks/useSuggestions";
import { SuggestionInput } from "./SuggestionInput";

export interface InspectAction {
    id: string;
    label: string;
    command: string;
    input?: { label: string; placeholder: string; suggestions?: SuggestionSource };
}

export interface InspectData {
    title: string;
    description: string;
    state?: string[];
    actions: InspectAction[];
}

/** Build exactly one command, preserving the core-authored parser syntax. */
export function inspectionCommand(action: InspectAction, input = ""): string {
    if (/[\r\n]/.test(input) || /[\r\n]/.test(action.command)) {
        throw new Error("Enter a single-line command.");
    }
    if (action.input && !input.trim()) throw new Error(action.input.label);
    const command = action.input ? action.command.split("{input}").join(input.trim()) : action.command;
    if (!command.trim()) throw new Error("This command is empty.");
    return command;
}

interface InspectPopoverProps {
    reference?: string;
    data: InspectData;
    position: { x: number; y: number };
    onClose: () => void;
    onCommand: (command: string) => boolean;
    returnFocusTo?: HTMLElement | null;
    isPreview?: boolean;
    authToken?: string | null;
    revision?: number;
}

export const InspectPopover: React.FC<InspectPopoverProps> = ({
    data,
    reference,
    position,
    onClose,
    onCommand,
    returnFocusTo,
    isPreview = false,
    authToken = null,
    revision = 0,
}) => {
    const { cardRef: popoverRef, isDragging, dragHandlers } = useFloatingCard(position, !isPreview);
    const titleId = useId();
    const [copyState, setCopyState] = useState("");
    const copyFeedback = useRef({ request: 0, timer: undefined as ReturnType<typeof setTimeout> | undefined });
    const displayReference = reference?.replace(/^(oid|uuid):/, "#");
    useEffect(() => {
        const feedback = copyFeedback.current;
        setCopyState("");
        return () => {
            ++feedback.request;
            clearTimeout(feedback.timer);
        };
    }, [reference]);
    const copyReference = async () => {
        if (!displayReference) return;
        const feedback = copyFeedback.current;
        const request = ++feedback.request;
        clearTimeout(feedback.timer);
        try {
            await navigator.clipboard.writeText(displayReference);
            if (request !== feedback.request) return;
            setCopyState(`Copied ${displayReference}`);
        } catch {
            if (request !== feedback.request) return;
            setCopyState("Could not copy the reference");
        }
        feedback.timer = setTimeout(() => setCopyState(""), 1800);
    };
    const dismiss = useCallback(() => {
        if (returnFocusTo?.isConnected) returnFocusTo.focus({ preventScroll: true });
        onClose();
    }, [onClose, returnFocusTo]);

    useEffect(() => {
        if (isPreview) return;
        popoverRef.current?.focus({ preventScroll: true });
        const outside = (event: PointerEvent) => {
            if ((event.target as HTMLElement).closest("[data-moor-annotation]")) return;
            if (!popoverRef.current?.contains(event.target as Node)) dismiss();
        };
        const escape = (event: KeyboardEvent) => {
            if (event.key !== "Escape" || event.defaultPrevented) return;
            event.preventDefault();
            event.stopPropagation();
            dismiss();
        };
        document.addEventListener("pointerdown", outside);
        document.addEventListener("keydown", escape);
        return () => {
            document.removeEventListener("pointerdown", outside);
            document.removeEventListener("keydown", escape);
        };
    }, [dismiss, isPreview, popoverRef]);

    const [activeInput, setActiveInput] = useState<string | null>(null);
    const [drafts, setDrafts] = useState<Record<string, { text: string; value: string }>>({});
    const [notice, setNotice] = useState("");
    const [error, setError] = useState("");
    const fieldId = useId();
    const inputRef = useRef<HTMLInputElement>(null);
    useEffect(() => {
        if (activeInput) inputRef.current?.focus({ preventScroll: true });
    }, [activeInput]);

    const send = (action: InspectAction) => {
        setError("");
        try {
            const command = inspectionCommand(action, drafts[action.id]?.value);
            if (!onCommand(command)) throw new Error("Not connected. Your command was not sent.");
            setNotice(`Sent: ${command}`);
            setActiveInput(null);
            setDrafts(current => ({ ...current, [action.id]: { text: "", value: "" } }));
        } catch (e) {
            setError(e instanceof Error ? e.message : "Could not send the command.");
        }
    };

    return (
        <div
            ref={popoverRef}
            role={isPreview ? "tooltip" : "dialog"}
            aria-labelledby={titleId}
            tabIndex={isPreview ? undefined : -1}
            className={`inspect-popover${isPreview ? " inspect-popover--preview" : ""}`}
            style={{ position: "fixed", left: position.x, top: position.y, zIndex: 10000 }}
        >
            <div
                className="inspect-popover-header"
                title={isPreview ? undefined : "Drag to move"}
                data-dragging={isDragging || undefined}
                {...dragHandlers}
            >
                <div>
                    <div className="inspect-popover-eyebrow">Inspect</div>
                    <div className="inspect-popover-title-row">
                        <div id={titleId} className="inspect-popover-title">{data.title}</div>
                        {reference && !isPreview && (
                            <div className="inspect-popover-copy-control">
                                <button
                                    type="button"
                                    className="inspect-popover-copy"
                                    aria-label="Copy reference"
                                    title={`Copy reference ${displayReference}`}
                                    onClick={() => void copyReference()}
                                >
                                    <svg
                                        viewBox="0 0 24 24"
                                        width="18"
                                        height="18"
                                        fill="none"
                                        stroke="currentColor"
                                        strokeWidth="1.6"
                                        aria-hidden="true"
                                    >
                                        <path d="M9 5H6a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3" />
                                        <rect x="9" y="2" width="6" height="6" rx="1.5" />
                                    </svg>
                                </button>
                                {copyState && (
                                    <span className="inspect-popover-copy-feedback" role="status">{copyState}</span>
                                )}
                            </div>
                        )}
                    </div>
                </div>
                {!isPreview && (
                    <button className="inspect-popover-close" onClick={dismiss} aria-label="Close inspection">×</button>
                )}
            </div>
            <div className="inspect-popover-summary">
                {data.state && data.state.length > 0 && (
                    <div className="inspect-popover-state">
                        {data.state.map(state => <span key={state}>{state}</span>)}
                    </div>
                )}
                <p className="inspect-popover-description">{data.description}</p>
            </div>
            {!isPreview && (
                <div className="inspect-popover-commands">
                    <div className="inspect-popover-section-label">Commands</div>
                    {data.actions.length === 0 && <p>No commands available here.</p>}
                    {data.actions.map(action => {
                        const expanded = activeInput === action.id;
                        const preview = action.command.split("{input}").join(drafts[action.id]?.value || "…");
                        return (
                            <div className="inspect-popover-command" key={action.id}>
                                <button
                                    className="inspect-popover-action"
                                    aria-label={action.label}
                                    aria-expanded={action.input ? expanded : undefined}
                                    onClick={event => {
                                        if (event.detail > 1) return;
                                        if (action.input) setActiveInput(expanded ? null : action.id);
                                        else send(action);
                                    }}
                                >
                                    <span>
                                        <span className="inspect-popover-action-label">{action.label}</span>
                                        <code>{preview}</code>
                                    </span>
                                    <span className="inspect-popover-action-arrow" aria-hidden="true">
                                        {action.input ? "+" : "↵"}
                                    </span>
                                </button>
                                {expanded && action.input && (
                                    <form
                                        className="inspect-popover-input"
                                        onSubmit={event => {
                                            event.preventDefault();
                                            send(action);
                                        }}
                                    >
                                        <label htmlFor={fieldId}>{action.input.label}</label>
                                        <SuggestionInput
                                            ref={inputRef}
                                            id={fieldId}
                                            value={drafts[action.id]?.text || ""}
                                            placeholder={action.input.placeholder}
                                            authToken={authToken}
                                            revision={revision}
                                            source={action.input.suggestions && {
                                                ...action.input.suggestions,
                                                context: { template: action.command, active: "input", bindings: {} },
                                            }}
                                            onChange={(text, selection) =>
                                                setDrafts(current => ({
                                                    ...current,
                                                    [action.id]: { text, value: selection?.value ?? text },
                                                }))}
                                        />
                                        <button type="submit">
                                            {action.label} <span aria-hidden="true">↵</span>
                                        </button>
                                    </form>
                                )}
                            </div>
                        );
                    })}
                    <div className="inspect-popover-footer">
                        {error
                            ? <span role="alert">{error}</span>
                            : <span role="status">{notice || "Results appear in the transcript."}</span>}
                    </div>
                </div>
            )}
        </div>
    );
};
