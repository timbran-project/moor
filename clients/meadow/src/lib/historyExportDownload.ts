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

import { HISTORY_EXPORT_BLOB_LIMIT, StartExportMessage, WorkerResponse } from "../workers/historyExportProtocol";

interface SavePickerWindow extends Window {
    showSaveFilePicker?: (options: {
        suggestedName: string;
        types: { description: string; accept: Record<string, string[]> }[];
    }) => Promise<Pick<FileSystemFileHandle, "createWritable">>;
}

export interface HistoryExportOutput {
    write: (bytes: Uint8Array<ArrayBuffer>) => Promise<void>;
    close: () => Promise<Blob | null>;
    abort: () => Promise<void>;
}

export function supportsHistoryExportStreaming(): boolean {
    return typeof (window as SavePickerWindow).showSaveFilePicker === "function";
}

/** Keep the download fallback bounded by its encoded byte size, including metadata. */
export function createBufferedHistoryExport(limit = HISTORY_EXPORT_BLOB_LIMIT): HistoryExportOutput {
    let parts: Uint8Array<ArrayBuffer>[] = [];
    let size = 0;
    return {
        async write(bytes) {
            if (size + bytes.byteLength > limit) {
                throw new Error(
                    "History export exceeds this browser's 64 MiB download limit. Use a browser with file streaming support for larger exports.",
                );
            }
            parts.push(bytes);
            size += bytes.byteLength;
        },
        async close() {
            const blob = new Blob(parts, { type: "application/json" });
            parts = [];
            return blob;
        },
        async abort() {
            parts = [];
            size = 0;
        },
    };
}

/** Invoke directly from the export button so the picker retains user activation. */
export async function openHistoryExportOutput(filename: string): Promise<HistoryExportOutput> {
    const picker = (window as SavePickerWindow).showSaveFilePicker;
    if (!picker) return createBufferedHistoryExport();
    const handle = await picker.call(window, {
        suggestedName: filename,
        types: [{ description: "History JSON", accept: { "application/json": [".json"] } }],
    });
    const stream = await handle.createWritable();
    return {
        write: (bytes) => stream.write(bytes),
        async close() {
            await stream.close();
            return null;
        },
        abort: () => stream.abort(),
    };
}

/** Acknowledge each chunk only after the sink accepts it, bounding the worker message queue. */
export function runHistoryExportWorker(
    worker: Worker,
    start: StartExportMessage,
    output: HistoryExportOutput,
    signal: AbortSignal,
    onProgress: (processed: number) => void,
): Promise<{ blob: Blob | null; skipped: number }> {
    return new Promise((resolve, reject) => {
        let settled = false;
        const finish = (error?: unknown, result?: { blob: Blob | null; skipped: number }) => {
            if (settled) return;
            settled = true;
            signal.removeEventListener("abort", abort);
            worker.onmessage = null;
            worker.onerror = null;
            worker.onmessageerror = null;
            worker.terminate();
            if (error) reject(error);
            else resolve(result!);
        };
        const abort = () => finish(new DOMException("Export cancelled", "AbortError"));
        signal.addEventListener("abort", abort, { once: true });
        if (signal.aborted) {
            abort();
            return;
        }
        worker.onmessage = async (event: MessageEvent<WorkerResponse>) => {
            if (settled) return;
            const message = event.data;
            try {
                if (message.type === "progress") {
                    onProgress(message.processed);
                    return;
                }
                if (message.type === "error") throw new Error(message.error);
                if (message.type === "chunk") {
                    await output.write(message.bytes);
                    if (!settled) worker.postMessage({ type: "ack" });
                    return;
                }
                const blob = await output.close();
                finish(undefined, { blob, skipped: message.skipped });
            } catch (error) {
                finish(error);
            }
        };
        worker.onerror = (event) => finish(new Error(event.message || "History export worker failed"));
        worker.onmessageerror = () => finish(new Error("Could not read history export worker output"));
        try {
            worker.postMessage(start);
        } catch (error) {
            finish(error);
        }
    });
}
