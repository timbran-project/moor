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

import { fireEvent, render, screen } from "@testing-library/react";
import { useEffect } from "react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { App } from "../App";
import { ErrorBoundary } from "./ErrorBoundary";

vi.mock("../app/AppShell", () => ({
    AppShell: () => {
        throw new Error("private provider failure");
    },
}));
const ignoreError = (event: ErrorEvent) => event.preventDefault();
beforeEach(() => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    window.addEventListener("error", ignoreError);
});
afterEach(() => {
    window.removeEventListener("error", ignoreError);
    vi.restoreAllMocks();
    localStorage.clear();
    sessionStorage.clear();
});

function Fault({ failed, phase }: { failed: boolean; phase: "render" | "effect" }) {
    useEffect(() => {
        if (failed && phase === "effect") throw new Error("private effect failure");
    }, [failed, phase]);
    if (failed && phase === "render") throw new Error("private render failure");
    return <p>Interface restored</p>;
}
it.each(["render", "effect"] as const)("contains a %s failure and retries only on request", phase => {
    const { rerender } = render(
        <ErrorBoundary scope="interface">
            <Fault failed phase={phase} />
        </ErrorBoundary>,
    );
    const alert = screen.getByRole("alert");
    expect(alert.textContent).not.toContain("private");
    expect(document.activeElement).toBe(alert);
    rerender(
        <ErrorBoundary scope="interface">
            <Fault failed={false} phase={phase} />
        </ErrorBoundary>,
    );
    expect(screen.queryByText("Interface restored")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Retry interface" }));
    expect(screen.getByText("Interface restored")).not.toBeNull();
});
it("keeps a persistently failing interface in recovery after another retry", () => {
    render(
        <ErrorBoundary scope="interface">
            <Fault failed phase="render" />
        </ErrorBoundary>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Retry interface" }));
    expect(screen.getByRole("alert")).not.toBeNull();
});
it("catches provider failures at the application boundary without clearing stored credentials", () => {
    localStorage.setItem("moor-auth-session", "stored-session");
    localStorage.setItem("history-key", "stored-key");
    sessionStorage.setItem("client_token", "reconnect-token");
    render(<App />);
    expect(screen.getByRole("button", { name: "Reload Meadow" })).not.toBeNull();
    expect(screen.getByRole("alert").textContent).not.toContain("private provider failure");
    expect(localStorage.getItem("moor-auth-session")).toBe("stored-session");
    expect(localStorage.getItem("history-key")).toBe("stored-key");
    expect(sessionStorage.getItem("client_token")).toBe("reconnect-token");
});
