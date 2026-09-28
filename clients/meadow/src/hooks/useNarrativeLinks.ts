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

import { useCallback, useEffect, useRef } from "react";
import { useExternalNavigation } from "../context/ExternalNavigationContext";
import { MoorVar } from "../lib/MoorVar";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { curieToObjectRef, ORefKind } from "../lib/var";
import { InspectController } from "./useInspectPopover";

interface UseNarrativeLinksArgs {
    authToken: string | null;
    sendMessage: (message: string) => boolean;
    showMessage: (message: string, duration?: number) => void;
    inspect: InspectController;
}

/**
 * Routes narrative link clicks by URL scheme:
 * - `moo://exit/` traverses a specific registered exit after server validation
 * - `moo://cmd/` sends the command as if typed
 * - `moo://inspect/` opens the object inspection popover
 * - `moo://help/` is not yet implemented
 * - http(s) links go through the external-navigation trust policy
 */
export const useNarrativeLinks = ({ authToken, sendMessage, showMessage, inspect }: UseNarrativeLinksArgs) => {
    const { openExternalLink } = useExternalNavigation();
    const pendingExits = useRef(new Map<string, Promise<void>>());
    const generationRef = useRef(0);
    useEffect(() => {
        generationRef.current += 1;
        pendingExits.current.clear();
        return () => {
            generationRef.current += 1;
        };
    }, [authToken]);

    const handleLinkClick = useCallback(async (
        url: string,
        position?: { x: number; y: number },
        metadata?: { actorName?: string; verb?: string },
    ) => {
        if (url.startsWith("moo://exit/")) {
            const pending = pendingExits.current.get(url);
            if (pending) return pending;
            const generation = generationRef.current;
            const request = (async () => {
                try {
                    if (!authToken) throw new Error("Not connected");
                    const parts = url.slice("moo://exit/".length).split("/").map(decodeURIComponent);
                    if (parts.length !== 3 || !parts.every(Boolean)) throw new Error("Invalid exit link");
                    const [source, destination, linkId] = parts;
                    if (![source, destination].every(ref => /^(oid|uuid):/.test(ref))) {
                        throw new Error("Invalid exit room reference");
                    }
                    const sourceRef = curieToObjectRef(source);
                    const destinationRef = curieToObjectRef(destination);
                    if (sourceRef.kind !== ORefKind.Oid || destinationRef.kind !== ORefKind.Oid) {
                        throw new Error("Invalid exit room reference");
                    }
                    const { result } = await invokeVerbFlatBuffer(
                        authToken,
                        sourceRef.curie,
                        "follow_exit",
                        MoorVar.buildInvokeArgs([destinationRef.curie, linkId]),
                    );
                    if (generation !== generationRef.current) return;
                    const response = result as { moved?: boolean; message?: string } | null;
                    if (response?.moved === true) {
                        // Fetch the narrative look through the current connection; capture RPCs have no connection.
                        if (!sendMessage("look")) showMessage("Moved. Reconnect to refresh your surroundings.", 4);
                    } else {
                        showMessage(response?.message || "That exit is no longer available.", 4);
                    }
                } catch (error) {
                    if (generation === generationRef.current) {
                        showMessage(error instanceof Error ? error.message : "Could not use that exit.", 4);
                    }
                }
            })();
            pendingExits.current.set(url, request);
            try {
                await request;
            } finally {
                if (pendingExits.current.get(url) === request) pendingExits.current.delete(url);
            }
        } else if (url.startsWith("moo://cmd/")) {
            // Command link: send as if typed
            const command = decodeURIComponent(url.slice(10));
            sendMessage(command);
        } else if (url.startsWith("moo://inspect/")) {
            // Inspect link: call web_inspect verb and show popover
            const oref = url.slice(14);
            await inspect.inspectObject(oref, position);
        } else if (url.startsWith("moo://help/")) {
            // Help link: show help in panel (TODO)
            const topic = decodeURIComponent(url.slice(11));
            console.log("Help link clicked:", topic);
            showMessage("Help links not yet implemented", 2);
        } else if (url.startsWith("http://") || url.startsWith("https://")) {
            openExternalLink(url, metadata);
        } else {
            console.warn("Unknown link scheme:", url);
        }
    }, [authToken, inspect, openExternalLink, sendMessage, showMessage]);

    return { handleLinkClick };
};
