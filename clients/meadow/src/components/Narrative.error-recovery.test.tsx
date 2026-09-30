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

import { act, fireEvent, render, screen } from "@testing-library/react";
import { createRef, useSyncExternalStore } from "react";
import { expect, it, vi } from "vitest";
import type { Transcript } from "../lib/transcript";
import { Narrative, type NarrativeRef } from "./Narrative";

const fault = vi.hoisted(() => ({ active: false }));
vi.mock("./InputArea", () => ({ InputArea: () => <input aria-label="Command" /> }));
vi.mock("./OutputWindow", () => ({
    OutputWindow: ({ transcript }: { transcript: Transcript }) => {
        useSyncExternalStore(transcript.subscribe, transcript.getVersion);
        if (fault.active) throw new Error("render failure");
        return <div>{transcript.allMessages().map(message => <p key={message.id}>{message.content}</p>)}</div>;
    },
}));
it("keeps loaded and incoming messages and command input when transcript rendering fails", () => {
    vi.stubGlobal("matchMedia", () => ({ matches: false }));
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const ignoreError = (event: ErrorEvent) => event.preventDefault();
    window.addEventListener("error", ignoreError);
    try {
        const ref = createRef<NarrativeRef>();
        render(<Narrative ref={ref} visible connectionStatus="connected" onSendMessage={() => true} />);
        act(() => ref.current!.addSystemMessage("Already displayed"));
        fireEvent.change(screen.getByRole("textbox"), { target: { value: "unfinished command" } });
        fault.active = true;
        act(() => ref.current!.addSystemMessage("Triggers failure"));
        expect(screen.getByRole("button", { name: "Retry transcript" })).not.toBeNull();
        expect(ref.current).not.toBeNull();
        act(() => ref.current!.addSystemMessage("Arrived during failure"));
        fault.active = false;
        fireEvent.click(screen.getByRole("button", { name: "Retry transcript" }));
        for (const text of ["Already displayed", "Triggers failure", "Arrived during failure"]) {
            expect(screen.getByText(text)).not.toBeNull();
        }
        expect((screen.getByRole("textbox") as HTMLInputElement).value).toBe("unfinished command");
    } finally {
        fault.active = false;
        window.removeEventListener("error", ignoreError);
        log.mockRestore();
        vi.unstubAllGlobals();
    }
});
