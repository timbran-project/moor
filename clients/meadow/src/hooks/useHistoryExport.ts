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

// Hook for exporting event history using a Web Worker

import { useCallback, useEffect, useRef, useState } from "react";
import {
    HistoryExportOutput,
    openHistoryExportOutput,
    runHistoryExportWorker,
    supportsHistoryExportStreaming,
} from "../lib/historyExportDownload";

interface ExportState {
    isExporting: boolean;
    progress: { processed: number; total?: number } | null;
    error: string | null;
    readyBlob: Blob | null;
    readyFilename: string | null;
    savedFilename: string | null;
    skipped: number;
}

const idleState: ExportState = {
    isExporting: false,
    progress: null,
    error: null,
    readyBlob: null,
    readyFilename: null,
    savedFilename: null,
    skipped: 0,
};

export const useHistoryExport = () => {
    const [exportState, setExportState] = useState<ExportState>(idleState);
    const active = useRef<AbortController | null>(null);

    useEffect(() => () => {
        active.current?.abort();
        active.current = null;
    }, []);

    const cancelExport = useCallback(() => {
        active.current?.abort();
        active.current = null;
        setExportState(idleState);
    }, []);

    const startExport = useCallback(async (
        authToken: string,
        ageIdentity: string,
        systemTitle: string,
        playerOid: string,
    ): Promise<void> => {
        active.current?.abort();
        const controller = new AbortController();
        active.current = controller;
        setExportState({ ...idleState, isExporting: true, progress: { processed: 0 } });
        const title = systemTitle.toLowerCase().replace(/[^a-z0-9]+/g, "-");
        const filename = `${title}-history-${new Date().toISOString().split("T")[0]}.json`;
        let output: HistoryExportOutput | undefined;
        let completed = false;
        try {
            output = await openHistoryExportOutput(filename);
            if (controller.signal.aborted) return;
            const worker = new Worker(new URL("../workers/historyExportWorker.ts", import.meta.url), {
                type: "module",
            });
            const result = await runHistoryExportWorker(
                worker,
                {
                    type: "start",
                    authToken,
                    ageIdentity,
                    systemTitle,
                    playerOid,
                },
                output,
                controller.signal,
                (processed) => {
                    if (active.current !== controller) return;
                    setExportState(prev => ({ ...prev, progress: { processed } }));
                },
            );
            completed = true;
            if (active.current !== controller) return;
            setExportState({
                ...idleState,
                readyBlob: result.blob,
                readyFilename: result.blob ? filename : null,
                savedFilename: result.blob ? null : filename,
                skipped: result.skipped,
            });
        } catch (error) {
            if (controller.signal.aborted) return;
            if (error instanceof DOMException && error.name === "AbortError") {
                if (active.current === controller) setExportState(idleState);
                return;
            }
            if (active.current === controller) {
                setExportState({
                    ...idleState,
                    error: error instanceof Error ? error.message : "History export failed",
                });
            }
            throw error;
        } finally {
            if (!completed && output) {
                try {
                    await output.abort();
                } catch {
                    // An errored or already-aborted writable may reject abort as well.
                }
            }
            if (active.current === controller) active.current = null;
        }
    }, []);

    const downloadReady = useCallback(() => {
        if (!exportState.readyBlob || !exportState.readyFilename) {
            return;
        }

        // Trigger the download
        const url = URL.createObjectURL(exportState.readyBlob);
        const a = document.createElement("a");
        a.href = url;
        a.download = exportState.readyFilename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        // Clear the ready state after download
        setExportState((prev) => ({
            ...prev,
            readyBlob: null,
            readyFilename: null,
        }));
    }, [exportState.readyBlob, exportState.readyFilename]);

    const dismissReady = useCallback(() => {
        // Clear the ready state without downloading
        setExportState((prev) => ({
            ...prev,
            readyBlob: null,
            readyFilename: null,
        }));
    }, []);

    return {
        exportState,
        supportsStreaming: supportsHistoryExportStreaming(),
        startExport,
        cancelExport,
        downloadReady,
        dismissReady,
    };
};
