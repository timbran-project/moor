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

import { Var } from "@moor/schema/generated/moor-var/var";
import { VarStr } from "@moor/schema/generated/moor-var/var-str";
import { VarUnion } from "@moor/schema/generated/moor-var/var-union";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { Builder, ByteBuffer } from "flatbuffers";
import { beforeEach, expect, it, vi } from "vitest";
import { MoorVar } from "../lib/MoorVar";
import { updatePropertyFlatBuffer } from "../lib/rpc-fb";
import { PropertyValueEditor } from "./PropertyValueEditor";

vi.mock("../lib/rpc-fb", () => ({ updatePropertyFlatBuffer: vi.fn(), performEvalFlatBuffer: vi.fn() }));
vi.mock("./EditorWindow", () => ({ useTitleBarDrag: () => ({}) }));

function renderProperty(onCancel = vi.fn(), splitMode = false) {
    const builder = new Builder(128);
    const str = VarStr.createVarStr(builder, builder.createString("line\nbreak"));
    builder.finish(Var.createVar(builder, VarUnion.VarStr, str));
    render(
        <PropertyValueEditor
            authToken="token"
            objectCurie="oid:42"
            propertyName="payload"
            propertyValue={new MoorVar(Var.getRootAsVar(new ByteBuffer(builder.asUint8Array())))}
            onSave={vi.fn()}
            onCancel={onCancel}
            splitMode={splitMode}
        />,
    );
    fireEvent.click(screen.getByRole("button", { name: "MOO literal mode" }));
}

beforeEach(() => vi.clearAllMocks());

it("marks a successful save clean even when literal spelling differs from server formatting", async () => {
    vi.mocked(updatePropertyFlatBuffer).mockResolvedValue(undefined);
    renderProperty();
    fireEvent.change(screen.getByRole("textbox"), { target: { value: String.raw`"line\nbreak"` } });
    expect(screen.getByText("●")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save property" }));
    await waitFor(() => expect(screen.queryByText("●")).toBeNull());
    expect(updatePropertyFlatBuffer).toHaveBeenCalledWith("token", "oid:42", "payload", String.raw`"line\nbreak"`);
});

it("keeps edits made during a pending save dirty, including after a later failed save", async () => {
    let finishSave!: () => void;
    vi.mocked(updatePropertyFlatBuffer).mockReturnValue(
        new Promise(resolve => {
            finishSave = resolve;
        }),
    );
    renderProperty();
    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "\"submitted\"" } });
    fireEvent.click(screen.getByRole("button", { name: "Save property" }));
    fireEvent.change(input, { target: { value: "\"newer draft\"" } });
    await act(async () => finishSave());
    expect((input as HTMLTextAreaElement).value).toBe("\"newer draft\"");
    expect(screen.getByText("●")).toBeTruthy();
    vi.mocked(updatePropertyFlatBuffer).mockRejectedValue(new Error("Permission denied"));
    fireEvent.click(screen.getByRole("button", { name: "Save property" }));
    await screen.findByText("Permission denied");
    expect((input as HTMLTextAreaElement).value).toBe("\"newer draft\"");
    expect(screen.getByText("●")).toBeTruthy();
});

it("offers a docked close action and preserves the draft when discard is declined", () => {
    const onCancel = vi.fn();
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(false);
    try {
        renderProperty(onCancel, true);
        fireEvent.change(screen.getByRole("textbox"), { target: { value: "\"unsaved\"" } });
        fireEvent.click(screen.getByRole("button", { name: "Close property editor" }));
        expect(onCancel).not.toHaveBeenCalled();
        expect((screen.getByRole("textbox") as HTMLTextAreaElement).value).toBe("\"unsaved\"");
        confirm.mockReturnValue(true);
        fireEvent.click(screen.getByRole("button", { name: "Close property editor" }));
        expect(onCancel).toHaveBeenCalledOnce();
    } finally {
        confirm.mockRestore();
    }
});

it("closes a clean docked property without a discard prompt", () => {
    const onCancel = vi.fn();
    const confirm = vi.spyOn(window, "confirm");
    try {
        renderProperty(onCancel, true);
        fireEvent.click(screen.getByRole("button", { name: "Close property editor" }));
        expect(onCancel).toHaveBeenCalledOnce();
        expect(confirm).not.toHaveBeenCalled();
    } finally {
        confirm.mockRestore();
    }
});
