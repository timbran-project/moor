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

import { Var } from "@moor/schema/generated/moor-var/var";
import { MoorVar } from "@moor/web-sdk";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { ByteBuffer } from "flatbuffers";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";
import { ChangeReview } from "./ChangeReview";

vi.mock("../lib/rpc-fb", () => ({ invokeVerbFlatBuffer: vi.fn() }));
vi.mock("../lib/monaco", () => ({}));
vi.mock("../lib/monaco-moo", () => ({ registerMooLanguage: vi.fn() }));
vi.mock("./ThemeProvider", () => ({ useTheme: () => ({ theme: "dark" }) }));
vi.mock("@monaco-editor/react", () => ({
    DiffEditor: ({ original, modified }: { original: string; modified: string }) => (
        <div data-testid="diff">{original} → {modified}</div>
    ),
    default: ({ value, onChange }: { value: string; onChange: (value: string) => void }) => (
        <textarea
            aria-label="Proposed program"
            value={value}
            onChange={event => onChange(event.target.value)}
        />
    ),
}));

const target = { kind: "change", provider: "oid:2000", review: 1, generation: 1, row: "verb/program" } as const;
const baseRow = {
    id: target.row,
    label: "$test:verb",
    classification: "conflict",
    base: "base",
    live: "local",
    incoming: "incoming",
    live_text: "return 1;",
    incoming_text: "return 2;",
    eligible: true,
    blockers: [],
    choices: ["incoming", "local", "edited", "defer"],
    default: "unresolved",
    choice: {},
};
let generation: number;
let saved: Record<string, unknown>;
let rejectChoice: boolean;
let applied: boolean;

beforeEach(() => {
    generation = 1;
    saved = {};
    rejectChoice = false;
    applied = false;
    vi.mocked(invokeVerbFlatBuffer).mockReset().mockImplementation(async (_token, _provider, method, bytes) => {
        const args = new MoorVar(Var.getRootAsVar(new ByteBuffer(bytes!))).toJS() as unknown[];
        const common = { schema: 1, review_id: 1, generation };
        if (method === "status") {
            return {
                result: { ...common, package: "cowbell", status: applied ? "complete" : "ready", error: {} },
                output: [],
            };
        }
        if (args[1] !== generation) throw new Error("Review changed; reload its status.");
        if (method === "diagnostics") {
            return { result: { ...common, diagnostics: [], total: 0, next: 0 }, output: [] };
        }
        if (method === "review") {
            return {
                result: {
                    ...common,
                    operation: "update",
                    rows: [{ ...baseRow, choice: saved }],
                    cursor: [],
                    counts: { conflict: 1, unchanged: 100 },
                    decision_counts: { selected: saved.choice ? 1 : 0, unresolved: saved.choice ? 0 : 1, blocked: 0 },
                },
                output: [],
            };
        }
        if (method === "details") return { result: { ...common, row: { ...baseRow, choice: saved } }, output: [] };
        if (method === "resolve") {
            if (rejectChoice) throw new Error("Live state changed. Refresh before choosing.");
            saved = { choice: args[3], program: args[4] };
            generation++;
            return { result: { ...common, generation, validation: [] }, output: [] };
        }
        if (method === "apply") {
            applied = true;
            return { result: { ...common, status: "applying" }, output: [] };
        }
        throw new Error(`Unexpected method ${method}`);
    });
});
afterEach(cleanup);

const open = () => render(<ChangeReview visible target={target} authToken="token" onClose={vi.fn()} />);

it("opens a review-specific comparison and tells the truth about missing baseline source", async () => {
    open();
    expect(await screen.findByRole("heading", { name: "$test:verb" })).toBeTruthy();
    expect(screen.getByTestId("diff").textContent).toBe("return 1; → return 2;");
    expect(screen.getByText("Accepted source wasn’t saved; only its hash is available.")).toBeTruthy();
    expect(screen.queryByRole("option", { name: "Accepted baseline → Local" })).toBeNull();
    expect(screen.getByRole("button", { name: "Apply 0 choices" })).toHaveProperty("disabled", true);
});

it("advances the generation after a choice and requires a separate explicit apply", async () => {
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Keep local" }));
    await waitFor(() =>
        expect(screen.getByRole("button", { name: "Apply 1 choice" })).toHaveProperty("disabled", false)
    );
    expect(applied).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Apply 1 choice" }));
    expect(applied).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Confirm apply" }));
    await screen.findByText("Updates applied.");
    expect(applied).toBe(true);
});

it("keeps an edited resolution separate from the running verb and protects unsaved drafts", async () => {
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Edit resolution" }));
    fireEvent.change(screen.getByRole("textbox", { name: "Proposed program" }), {
        target: { value: "return 3;\nreturn 4;" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.getByText("Discard the unsaved draft?")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    fireEvent.click(screen.getByRole("button", { name: "Save proposed program" }));
    await waitFor(() => expect(saved.choice).toBe("edited"));
    expect(saved.program).toBe("return 3;\nreturn 4;");
    expect(applied).toBe(false);
});

it("does not offer apply when live evidence becomes stale", async () => {
    rejectChoice = true;
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Use upstream" }));
    await screen.findByText("Live state changed. Refresh before choosing.");
    expect(screen.getByRole("button", { name: "Reload review" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Apply 0 choices" })).toHaveProperty("disabled", true);
});

it("can retry a failed review read without closing the panel", async () => {
    vi.mocked(invokeVerbFlatBuffer).mockRejectedValueOnce(new Error("Permission denied."));
    open();
    expect((await screen.findByRole("alert")).textContent).toContain("Permission denied.");
    fireEvent.click(screen.getByRole("button", { name: "Reload review" }));
    await screen.findByRole("heading", { name: "$test:verb" });
});
