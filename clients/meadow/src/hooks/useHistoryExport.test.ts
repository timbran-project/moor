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

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { WorkerResponse } from "../workers/historyExportProtocol";
import { useHistoryExport } from "./useHistoryExport";

class FakeWorker {
    static instances: FakeWorker[] = [];
    onmessage: ((event: { data: WorkerResponse }) => void | Promise<void>) | null = null;
    onerror: ((event: { message: string }) => void) | null = null;
    onmessageerror: (() => void) | null = null;
    postMessage = vi.fn();
    terminate = vi.fn();
    constructor() {
        FakeWorker.instances.push(this);
    }
    emit(data: WorkerResponse) {
        return this.onmessage?.({ data });
    }
}
const args = ["token", "key", "Test World", "oid:1"] as const;
function fileStream() {
    return { write: vi.fn(async () => {}), close: vi.fn(async () => {}), abort: vi.fn(async () => {}) };
}

beforeEach(() => {
    FakeWorker.instances = [];
    vi.stubGlobal("Worker", FakeWorker);
    vi.stubGlobal("showSaveFilePicker", undefined);
});
afterEach(() => vi.unstubAllGlobals());

describe("history export lifecycle", () => {
    it("keeps the fallback download ready until dismissed", async () => {
        const { result } = renderHook(() => useHistoryExport());
        let pending!: Promise<void>;
        await act(async () => {
            pending = result.current.startExport(...args);
        });
        const worker = FakeWorker.instances[0];
        await act(async () => {
            await worker.emit({ type: "chunk", bytes: new TextEncoder().encode("{}") });
            await worker.emit({ type: "complete", skipped: 0 });
            await pending;
        });
        expect(result.current.exportState.readyBlob?.size).toBe(2);
        expect(result.current.exportState.readyFilename).toMatch(/^test-world-history-.*\.json$/);
        expect(result.current.exportState.savedFilename).toBeNull();
        act(() => result.current.dismissReady());
        expect(result.current.exportState.readyBlob).toBeNull();
        expect(worker.terminate).toHaveBeenCalledOnce();
    });

    it("reports a streamed save only after close, without retaining a download Blob", async () => {
        const stream = fileStream();
        vi.stubGlobal("showSaveFilePicker", vi.fn(async () => ({ createWritable: async () => stream })));
        const { result } = renderHook(() => useHistoryExport());
        let pending!: Promise<void>;
        await act(async () => {
            pending = result.current.startExport(...args);
        });
        await act(async () => {
            await FakeWorker.instances[0].emit({ type: "chunk", bytes: new Uint8Array([1]) });
            await FakeWorker.instances[0].emit({ type: "complete", skipped: 3 });
            await pending;
        });
        expect(stream.close).toHaveBeenCalledOnce();
        expect(stream.abort).not.toHaveBeenCalled();
        expect(result.current.exportState).toMatchObject({ isExporting: false, readyBlob: null, skipped: 3 });
        expect(result.current.exportState.savedFilename).toMatch(/^test-world-history-/);
    });

    it("treats closing the picker as cancellation without creating a worker", async () => {
        vi.stubGlobal("showSaveFilePicker", vi.fn().mockRejectedValue(new DOMException("cancel", "AbortError")));
        const { result } = renderHook(() => useHistoryExport());
        await act(async () => {
            await result.current.startExport(...args);
        });
        expect(FakeWorker.instances).toHaveLength(0);
        expect(result.current.exportState).toMatchObject({ isExporting: false, error: null });
    });

    it.each(["cancel", "unmount"])("aborts the file and settles the export on %s", async (action) => {
        const stream = fileStream();
        vi.stubGlobal("showSaveFilePicker", vi.fn(async () => ({ createWritable: async () => stream })));
        const { result, unmount } = renderHook(() => useHistoryExport());
        let pending!: Promise<void>;
        await act(async () => {
            pending = result.current.startExport(...args);
        });
        await act(async () => {
            if (action === "cancel") result.current.cancelExport();
            else unmount();
            await pending;
        });
        expect(FakeWorker.instances[0].terminate).toHaveBeenCalledOnce();
        expect(stream.abort).toHaveBeenCalledOnce();
        expect(stream.close).not.toHaveBeenCalled();
    });

    it("aborts a file opened after cancellation while the picker was pending", async () => {
        const stream = fileStream();
        let choose!: (handle: { createWritable: () => Promise<typeof stream> }) => void;
        vi.stubGlobal("showSaveFilePicker", () =>
            new Promise(resolve => {
                choose = resolve;
            }));
        const { result } = renderHook(() => useHistoryExport());
        let pending!: Promise<void>;
        await act(async () => {
            pending = result.current.startExport(...args);
        });
        act(() => result.current.cancelExport());
        await act(async () => {
            choose({ createWritable: async () => stream });
            await pending;
        });
        expect(stream.abort).toHaveBeenCalledOnce();
        expect(FakeWorker.instances).toHaveLength(0);
        expect(result.current.exportState.readyBlob).toBeNull();
    });

    it("settles a replaced export without clearing the new export's state", async () => {
        const { result } = renderHook(() => useHistoryExport());
        let first!: Promise<void>;
        let second!: Promise<void>;
        await act(async () => {
            first = result.current.startExport(...args);
        });
        await act(async () => {
            second = result.current.startExport(...args);
            await first;
        });
        expect(FakeWorker.instances[0].terminate).toHaveBeenCalledOnce();
        expect(result.current.exportState.isExporting).toBe(true);
        await act(async () => {
            await FakeWorker.instances[1].emit({ type: "complete", skipped: 0 });
            await second;
        });
        expect(result.current.exportState.readyBlob).not.toBeNull();
    });

    it.each(["write", "close"])("aborts the file after %s failure and reports the error", async (operation) => {
        const stream = fileStream();
        stream[operation as "write" | "close"].mockRejectedValue(new Error("disk full"));
        vi.stubGlobal("showSaveFilePicker", vi.fn(async () => ({ createWritable: async () => stream })));
        const { result } = renderHook(() => useHistoryExport());
        let pending!: Promise<void>;
        await act(async () => {
            pending = result.current.startExport(...args);
        });
        const rejected = expect(pending).rejects.toThrow("disk full");
        await act(async () => {
            await FakeWorker.instances[0].emit(
                operation === "write"
                    ? { type: "chunk", bytes: new Uint8Array([1]) }
                    : { type: "complete", skipped: 0 },
            );
            await rejected;
        });
        expect(stream.abort).toHaveBeenCalledOnce();
        expect(result.current.exportState).toMatchObject({
            isExporting: false,
            error: "disk full",
            readyBlob: null,
            savedFilename: null,
        });
    });

    it("aborts the output if worker construction fails", async () => {
        const stream = fileStream();
        vi.stubGlobal("showSaveFilePicker", vi.fn(async () => ({ createWritable: async () => stream })));
        vi.stubGlobal(
            "Worker",
            class {
                constructor() {
                    throw new Error("worker unavailable");
                }
            },
        );
        const { result } = renderHook(() => useHistoryExport());
        await act(async () => {
            await expect(result.current.startExport(...args)).rejects.toThrow("worker unavailable");
        });
        expect(stream.abort).toHaveBeenCalledOnce();
        expect(result.current.exportState.isExporting).toBe(false);
    });
});
