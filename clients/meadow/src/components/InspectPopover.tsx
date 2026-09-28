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

import React, { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react";

export interface InspectAction {
    id: string;
    label: string;
    command: string;
    input?: { label: string; placeholder: string };
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
    data: InspectData;
    position: { x: number; y: number };
    onClose: () => void;
    onCommand: (command: string) => boolean;
    returnFocusTo?: HTMLElement | null;
    isPreview?: boolean;
}

/** Keep the card inside the visible viewport, including when the mobile keyboard opens. */
function placeInspector(card: HTMLDivElement, x: number, y: number, preferAbove = false) {
    const viewport = window.visualViewport;
    const left = (viewport?.offsetLeft ?? 0) + 16;
    const top = (viewport?.offsetTop ?? 0) + 16;
    const width = viewport?.width ?? window.innerWidth;
    const height = viewport?.height ?? window.innerHeight;
    card.style.maxWidth = `${Math.max(0, Math.min(360, width - 32))}px`;
    card.style.maxHeight = `${Math.max(0, height - 32)}px`;
    const rect = card.getBoundingClientRect();
    if (preferAbove && y + rect.height > top + height - 32) y -= rect.height + 8;
    card.style.left = `${Math.max(left, Math.min(x, left + width - 32 - rect.width))}px`;
    card.style.top = `${Math.max(top, Math.min(y, top + height - 32 - rect.height))}px`;
}

export const InspectPopover: React.FC<InspectPopoverProps> = ({
    data,
    position,
    onClose,
    onCommand,
    returnFocusTo,
    isPreview = false,
}) => {
    const popoverRef = useRef<HTMLDivElement>(null);
    const drag = useRef<{ pointerId: number; offsetX: number; offsetY: number } | null>(null);
    const [isDragging, setIsDragging] = useState(false);
    const titleId = useId();
    const dismiss = useCallback(() => {
        if (returnFocusTo?.isConnected) returnFocusTo.focus({ preventScroll: true });
        onClose();
    }, [onClose, returnFocusTo]);

    useEffect(() => {
        if (isPreview) return;
        popoverRef.current?.focus({ preventScroll: true });
        const outside = (event: PointerEvent) => {
            if (!popoverRef.current?.contains(event.target as Node)) dismiss();
        };
        const escape = (event: KeyboardEvent) => {
            if (event.key !== "Escape") return;
            event.preventDefault();
            event.stopPropagation();
            dismiss();
        };
        document.addEventListener("pointerdown", outside);
        document.addEventListener("keydown", escape, true);
        return () => {
            document.removeEventListener("pointerdown", outside);
            document.removeEventListener("keydown", escape, true);
        };
    }, [dismiss, isPreview]);

    // Feedback and refreshed descriptions can change the card's size after opening.
    useLayoutEffect(() => {
        const card = popoverRef.current;
        if (!card) return;
        let placed = false;
        const place = () => {
            const rect = card.getBoundingClientRect();
            placeInspector(card, placed ? rect.left : position.x, placed ? rect.top : position.y, !placed);
            placed = true;
        };
        place();
        const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(place);
        observer?.observe(card);
        window.addEventListener("resize", place);
        window.visualViewport?.addEventListener("resize", place);
        window.visualViewport?.addEventListener("scroll", place);
        return () => {
            observer?.disconnect();
            window.removeEventListener("resize", place);
            window.visualViewport?.removeEventListener("resize", place);
            window.visualViewport?.removeEventListener("scroll", place);
        };
    }, [position]);

    const startDrag = (event: React.PointerEvent<HTMLDivElement>) => {
        if (isPreview || event.button !== 0 || drag.current || (event.target as Element).closest("button")) return;
        const card = popoverRef.current;
        if (!card) return;
        const rect = card.getBoundingClientRect();
        event.currentTarget.setPointerCapture(event.pointerId);
        drag.current = {
            pointerId: event.pointerId,
            offsetX: event.clientX - rect.left,
            offsetY: event.clientY - rect.top,
        };
        setIsDragging(true);
        event.preventDefault();
    };

    const moveDrag = (event: React.PointerEvent<HTMLDivElement>) => {
        const current = drag.current;
        const card = popoverRef.current;
        if (!current || current.pointerId !== event.pointerId || !card) return;
        placeInspector(card, event.clientX - current.offsetX, event.clientY - current.offsetY);
    };

    const endDrag = (event: React.PointerEvent<HTMLDivElement>) => {
        if (drag.current?.pointerId !== event.pointerId) return;
        drag.current = null;
        setIsDragging(false);
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
            event.currentTarget.releasePointerCapture(event.pointerId);
        }
    };

    const [activeInput, setActiveInput] = useState<string | null>(null);
    const [drafts, setDrafts] = useState<Record<string, string>>({});
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
            const command = inspectionCommand(action, drafts[action.id]);
            if (!onCommand(command)) throw new Error("Not connected. Your command was not sent.");
            setNotice(`Sent: ${command}`);
            setActiveInput(null);
            setDrafts(current => ({ ...current, [action.id]: "" }));
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
                onPointerDown={startDrag}
                onPointerMove={moveDrag}
                onPointerUp={endDrag}
                onPointerCancel={endDrag}
                onLostPointerCapture={endDrag}
            >
                <div>
                    <div className="inspect-popover-eyebrow">Inspect</div>
                    <div id={titleId} className="inspect-popover-title">{data.title}</div>
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
                        const preview = action.command.split("{input}").join(drafts[action.id] || "…");
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
                                        <input
                                            ref={inputRef}
                                            id={fieldId}
                                            value={drafts[action.id] || ""}
                                            placeholder={action.input.placeholder}
                                            autoComplete="off"
                                            onChange={event =>
                                                setDrafts(current => ({ ...current, [action.id]: event.target.value }))}
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
