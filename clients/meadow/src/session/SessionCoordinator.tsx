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

import React, { createContext, useContext, useRef } from "react";
import { useSystemMessage } from "../components/MessageBoard";
import { NarrativeRef } from "../components/Narrative";
import { useAuthContext } from "../context/AuthContext";
import { WebSocketProvider } from "../context/WebSocketContext";
import { createEditorLaunchBridge, EditorLaunchBridge, EditorLaunchBridgeContext } from "./editorLaunchBridge";
import { useNarrativePipeline } from "./useNarrativePipeline";

interface NarrativePipelineContextType {
    narrativeRef: React.RefObject<NarrativeRef | null>;
    narrativeCallbackRef: (node: NarrativeRef | null) => void;
}

const NarrativePipelineContext = createContext<NarrativePipelineContextType | undefined>(undefined);

export const useNarrativePipelineContext = (): NarrativePipelineContextType => {
    const context = useContext(NarrativePipelineContext);
    if (context === undefined) {
        throw new Error("useNarrativePipelineContext must be used within a SessionCoordinator");
    }
    return context;
};

/**
 * Sits directly above the WebSocket provider and owns the narrative ingestion
 * pipeline (MCP filtering, message buffering, room snapshots). Everything
 * below consumes the WebSocket context this component establishes, plus the
 * narrative surface handles exposed through the pipeline context.
 */
export const SessionCoordinator: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const {
        authState,
        clearInitialAttach,
        disconnect,
        rotatePlayerIdentity,
        setPlayerConnected,
        updateReconnectCredentials,
    } = useAuthContext();
    const { showMessage } = useSystemMessage();

    const bridgeRef = useRef<EditorLaunchBridge | null>(null);
    if (bridgeRef.current === null) {
        bridgeRef.current = createEditorLaunchBridge();
    }
    const bridge = bridgeRef.current;

    // The pipeline runs above the bridge context, so it receives the bridge directly
    const pipeline = useNarrativePipeline(bridge);

    const pipelineContext = useRef<NarrativePipelineContextType | null>(null);
    if (pipelineContext.current === null) {
        pipelineContext.current = {
            narrativeRef: pipeline.narrativeRef,
            narrativeCallbackRef: pipeline.narrativeCallbackRef,
        };
    }

    return (
        <EditorLaunchBridgeContext.Provider value={bridge}>
            <NarrativePipelineContext.Provider value={pipelineContext.current}>
                <WebSocketProvider
                    player={authState.player}
                    showMessage={showMessage}
                    setPlayerConnected={setPlayerConnected}
                    rotatePlayerIdentity={rotatePlayerIdentity}
                    updateReconnectCredentials={updateReconnectCredentials}
                    handleNarrativeMessage={pipeline.handlers.handleNarrativeMessage}
                    handlePresentMessage={pipeline.handlers.handlePresentMessage}
                    handleUnpresentMessage={pipeline.handlers.handleUnpresentMessage}
                    handleDataMessage={pipeline.handlers.handleDataMessage}
                    onAuthFailure={disconnect}
                    onInitialAttachComplete={clearInitialAttach}
                >
                    {children}
                </WebSocketProvider>
            </NarrativePipelineContext.Provider>
        </EditorLaunchBridgeContext.Provider>
    );
};
