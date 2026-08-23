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

import { useCallback, useState } from "react";
import { InspectAction, InspectData } from "../components/InspectPopover";
import { MoorVar } from "../lib/MoorVar";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { PresentationData } from "../types/presentation";

interface InspectPopoverState {
    data: InspectData;
    position: { x: number; y: number };
    isPreview?: boolean;
}

interface UseInspectPopoverArgs {
    authToken: string | null;
    showMessage: (message: string, duration?: number) => void;
    sendMessage: (message: string) => boolean;
    addPresentation: (data: PresentationData) => void;
}

interface VerbOutputEvent {
    eventType: string;
    event: unknown;
}

const extractOutputMessages = (output: VerbOutputEvent[]): string[] => {
    const messages: string[] = [];
    for (const evt of output) {
        const event = evt.event as { value?: unknown; backtrace?: string[] } | undefined;
        if (evt.eventType === "NotifyEvent" && event?.value) {
            const value = event.value;
            if (typeof value === "string") {
                messages.push(value);
            } else if (Array.isArray(value)) {
                const text = value
                    .map((item) => (typeof item === "string" ? item : String(item)))
                    .join("\n");
                messages.push(text);
            } else {
                messages.push(String(value));
            }
            continue;
        }
        if (evt.eventType === "TracebackEvent" && Array.isArray(event?.backtrace)) {
            messages.push(event.backtrace.join("\n"));
        }
    }
    return messages;
};

/**
 * Owns the object-inspection popover lifecycle: fetching inspection data for
 * `moo://inspect/` links (including mobile hold-to-preview), and executing
 * popover actions such as sending commands or invoking verbs into panels.
 */
export const useInspectPopover = ({ authToken, showMessage, sendMessage, addPresentation }: UseInspectPopoverArgs) => {
    const [inspectPopover, setInspectPopover] = useState<InspectPopoverState | null>(null);

    const closeInspectPopover = useCallback(() => {
        setInspectPopover(null);
    }, []);

    const inspectObject = useCallback(async (
        oref: string,
        position?: { x: number; y: number },
        isPreview?: boolean,
    ) => {
        if (!authToken) {
            showMessage("Not connected", 2);
            return;
        }

        try {
            const { result } = await invokeVerbFlatBuffer(authToken, oref, "inspection");
            if (result) {
                const data = result as InspectData;
                setInspectPopover({
                    data,
                    position: position ?? { x: window.innerWidth / 2, y: window.innerHeight / 2 },
                    ...(isPreview ? { isPreview } : {}),
                });
            } else if (!isPreview) {
                showMessage("No inspect data available", 2);
            }
        } catch (error) {
            console.error("Failed to inspect object:", error);
            if (!isPreview) {
                showMessage(`Inspect failed: ${error instanceof Error ? error.message : String(error)}`, 3);
            }
        }
    }, [authToken, showMessage]);

    // Handle hold-to-preview for inspect links (mobile)
    const handleLinkHoldStart = useCallback(async (url: string, position: { x: number; y: number }) => {
        if (!url.startsWith("moo://inspect/") || !authToken) return;

        const oref = url.slice(14);
        await inspectObject(oref, position, true);
    }, [authToken, inspectObject]);

    // Handle end of hold-to-preview
    const handleLinkHoldEnd = useCallback(() => {
        setInspectPopover((current) => {
            // Only dismiss if it's a preview popover
            if (current?.isPreview) return null;
            return current;
        });
    }, []);

    const executeInspectAction = useCallback(async (
        action: InspectAction,
        inputValue?: string,
    ): Promise<Array<{ eventType: string; event: any }>> => {
        if (!authToken) return [];
        if (action.kind === "command" || action.command) {
            let command = action.command ?? "";
            if (inputValue) {
                command = command.includes("{input}")
                    ? command.split("{input}").join(inputValue)
                    : `${command} ${inputValue}`.trim();
            }
            if (!command) {
                return [];
            }
            sendMessage(command);
            return [];
        }

        if (!action.verb || !action.target) {
            return [];
        }

        const invokeArgs = action.args ? [...action.args] : [];
        if (inputValue) {
            invokeArgs.push(inputValue);
        }

        const argsBytes = invokeArgs.length > 0 ? MoorVar.buildInvokeArgs(invokeArgs) : undefined;
        const { output } = await invokeVerbFlatBuffer(authToken, action.target, action.verb, argsBytes);

        if (action.resultMode === "panel") {
            const messages = extractOutputMessages(output);
            if (messages.length > 0) {
                const presentationId = action.panelId
                    || `inspect-action-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
                const panelTarget = action.panelTarget ?? "tools";
                const panelTitle = action.panelTitle ?? action.label;
                addPresentation({
                    id: presentationId,
                    target: panelTarget,
                    content_type: "text/plain",
                    content: messages.join("\n"),
                    attributes: [
                        ["title", panelTitle],
                        ["kind", "action_output"],
                        ["source", "inspect_action"],
                    ],
                });
            }
            return [];
        }

        return output;
    }, [addPresentation, authToken, sendMessage]);

    return {
        inspectPopover,
        closeInspectPopover,
        inspectObject,
        handleLinkHoldStart,
        handleLinkHoldEnd,
        executeInspectAction,
    };
};

export type InspectController = Pick<ReturnType<typeof useInspectPopover>, "inspectObject">;
