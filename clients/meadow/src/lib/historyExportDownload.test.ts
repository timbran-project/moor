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

import { afterEach, describe, expect, it, vi } from "vitest";
import { HISTORY_EXPORT_BLOB_LIMIT, StartExportMessage, WorkerResponse } from "../workers/historyExportProtocol";
import {
    createBufferedHistoryExport,
    HistoryExportOutput,
    openHistoryExportOutput,
    runHistoryExportWorker,
} from "./historyExportDownload";

const start: StartExportMessage = {
    type: "start",
    authToken: "token",
    ageIdentity: "key",
    systemTitle: "World",
    playerOid: "oid:1",
};
function fakeWorker() {
    return {
        onmessage: null as ((event: { data: WorkerResponse }) => Promise<void>) | null,
        onerror: null as ((event: { message: string }) => void) | null,
        onmessageerror: null as (() => void) | null,
        postMessage: vi.fn(),
        terminate: vi.fn(),
    };
}
function sink(): HistoryExportOutput {
    return { write: vi.fn(async () => {}), close: vi.fn(async () => null), abort: vi.fn(async () => {}) };
}
function run(worker: ReturnType<typeof fakeWorker>, output = sink(), controller = new AbortController()) {
    return runHistoryExportWorker(worker as unknown as Worker, start, output, controller.signal, vi.fn());
}

const readBlob = (blob: Blob) =>
    new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result));
        reader.onerror = reject;
        reader.readAsText(blob);
    });

afterEach(() => vi.unstubAllGlobals());

describe("history export output", () => {
    it("counts encoded bytes at the fallback boundary, including Unicode", async () => {
        const output = createBufferedHistoryExport(4);
        await output.write(new TextEncoder().encode("🌿"));
        await expect(output.write(new Uint8Array(1))).rejects.toThrow("64 MiB");
        expect(await readBlob((await output.close())!)).toBe("🌿");
    });
    it("enforces the default 64 MiB limit across chunks", async () => {
        const output = createBufferedHistoryExport();
        const chunk = new Uint8Array(1024 * 1024);
        for (let size = 0; size < HISTORY_EXPORT_BLOB_LIMIT; size += chunk.length) await output.write(chunk);
        await expect(output.write(new Uint8Array(1))).rejects.toThrow("64 MiB");
        await output.abort();
        expect((await output.close())?.size).toBe(0);
    });
    it("selects and writes directly to a file when the picker is available", async () => {
        const stream = { write: vi.fn(async () => {}), close: vi.fn(async () => {}), abort: vi.fn(async () => {}) };
        const picker = vi.fn(async () => ({ createWritable: async () => stream }));
        vi.stubGlobal("showSaveFilePicker", picker);
        const output = await openHistoryExportOutput("history.json");
        expect(picker).toHaveBeenCalledWith(expect.objectContaining({ suggestedName: "history.json" }));
        const chunk = new Uint8Array([1]);
        await output.write(chunk);
        expect(stream.write).toHaveBeenCalledWith(chunk);
        expect(await output.close()).toBeNull();
        expect(stream.close).toHaveBeenCalledOnce();
    });
    it("does not fall back silently when the picker is cancelled", async () => {
        vi.stubGlobal("showSaveFilePicker", vi.fn().mockRejectedValue(new DOMException("cancel", "AbortError")));
        await expect(openHistoryExportOutput("history.json")).rejects.toMatchObject({ name: "AbortError" });
    });
});

describe("worker backpressure and cleanup", () => {
    it("acknowledges chunks after writing, then waits for file close before completing", async () => {
        const worker = fakeWorker();
        const output = sink();
        let release!: () => void;
        output.write = vi.fn(() =>
            new Promise<void>(resolve => {
                release = resolve;
            })
        );
        const pending = run(worker, output);
        const writing = worker.onmessage!({ data: { type: "chunk", bytes: new Uint8Array([1]) } });
        expect(worker.postMessage.mock.calls).toEqual([[start]]);
        release();
        await writing;
        expect(worker.postMessage).toHaveBeenLastCalledWith({ type: "ack" });
        let close!: () => void;
        output.close = () =>
            new Promise<null>(resolve => {
                close = () => resolve(null);
            });
        const closing = worker.onmessage!({ data: { type: "complete", skipped: 2 } });
        expect(worker.terminate).not.toHaveBeenCalled();
        close();
        await closing;
        await expect(pending).resolves.toEqual({ blob: null, skipped: 2 });
        expect(worker.terminate).toHaveBeenCalledOnce();
    });
    it("terminates and rejects on a failed write without acknowledging it", async () => {
        const worker = fakeWorker();
        const output = sink();
        output.write = vi.fn().mockRejectedValue(new Error("disk full"));
        const pending = run(worker, output);
        const rejected = expect(pending).rejects.toThrow("disk full");
        await worker.onmessage!({ data: { type: "chunk", bytes: new Uint8Array([1]) } });
        await rejected;
        expect(worker.postMessage.mock.calls).toEqual([[start]]);
        expect(worker.terminate).toHaveBeenCalledOnce();
    });
    it("cancels during a pending write and ignores late completion", async () => {
        const worker = fakeWorker();
        const output = sink();
        const controller = new AbortController();
        let release!: () => void;
        output.write = () =>
            new Promise<void>(resolve => {
                release = resolve;
            });
        const pending = run(worker, output, controller);
        const rejected = expect(pending).rejects.toMatchObject({ name: "AbortError" });
        const writing = worker.onmessage!({ data: { type: "chunk", bytes: new Uint8Array([1]) } });
        controller.abort();
        await rejected;
        release();
        await writing;
        expect(worker.postMessage.mock.calls).toEqual([[start]]);
        expect(worker.terminate).toHaveBeenCalledOnce();
        expect(output.close).not.toHaveBeenCalled();
    });
    it("rejects close failures and cleans up the worker", async () => {
        const worker = fakeWorker();
        const output = sink();
        output.close = vi.fn().mockRejectedValue(new Error("close failed"));
        const pending = run(worker, output);
        const rejected = expect(pending).rejects.toThrow("close failed");
        await worker.onmessage!({ data: { type: "complete", skipped: 0 } });
        await rejected;
        expect(worker.terminate).toHaveBeenCalledOnce();
    });
});
