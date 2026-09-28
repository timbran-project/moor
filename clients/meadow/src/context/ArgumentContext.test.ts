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

// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
import { afterEach, expect, it, vi } from "vitest";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { ArgumentCoordinator } from "./ArgumentContext";
vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));
afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
});
const source = {
    provider: "oid:2",
    source: "nearby",
    context: { template: "take {input}", active: "input", bindings: {} },
};
it("checks a selected reference again and discards replies after another editor takes focus", async () => {
    vi.useFakeTimers();
    const coordinator = new ArgumentCoordinator();
    coordinator.configure("session", false);
    const choose = vi.fn();
    const feedback = vi.fn();
    coordinator.focus({ id: "give", label: "item", source, choose, feedback });
    let resolve!: (value: { result: unknown; output: [] }) => void;
    vi.mocked(invokeVerbFlatBuffer).mockImplementationOnce(() =>
        new Promise(done => {
            resolve = done;
        })
    );
    expect(coordinator.select("oid:47")).toBe(true);
    coordinator.focus({ id: "put", label: "container", source, choose, feedback });
    resolve({ result: { "oid:47": { eligible: true, label: "Compass", value: "#47" } }, output: [] });
    await Promise.resolve();
    await Promise.resolve();
    expect(choose).not.toHaveBeenCalled();
    vi.mocked(invokeVerbFlatBuffer).mockResolvedValueOnce({
        result: { "oid:47": { eligible: true, label: "Compass", value: "#47" } },
        output: [],
    });
    coordinator.select("oid:47");
    await Promise.resolve();
    await Promise.resolve();
    expect(choose).toHaveBeenCalledWith(expect.objectContaining({ value: "#47", label: "Compass" }));
    coordinator.configure("session", true);
    expect(coordinator.select("oid:47")).toBe(false);
    coordinator.configure("another login", false);
    expect(coordinator.select("oid:47")).toBe(false);
    coordinator.dispose();
});
it("deduplicates visible references into bounded batches and restores marker behavior on dismissal", async () => {
    vi.useFakeTimers();
    const coordinator = new ArgumentCoordinator();
    coordinator.configure("session", false);
    const nodes = Array.from({ length: 150 }, (_, i) => {
        const node = document.createElement("span");
        node.title = "Inspect";
        node.textContent = "Item";
        coordinator.register(node, `oid:${i % 70}`);
        return node;
    });
    vi.mocked(invokeVerbFlatBuffer).mockResolvedValue({
        result: { "oid:0": { eligible: true, label: "Item", value: "#0" } },
        output: [],
    });
    coordinator.focus({ id: "item", label: "item", source, choose: vi.fn(), feedback: vi.fn() });
    await vi.advanceTimersByTimeAsync(121);
    expect(invokeVerbFlatBuffer).toHaveBeenCalledTimes(2);
    expect(nodes[0].title).toBe("Use Item for item");
    coordinator.release("item");
    await vi.advanceTimersByTimeAsync(121);
    expect(nodes[0].title).toBe("Inspect");
    coordinator.dispose();
});
