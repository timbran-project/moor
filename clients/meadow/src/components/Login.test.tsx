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

import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Login } from "./Login";

vi.mock("../context/AuthContext", () => ({
    useAuthContext: () => ({ authState: { player: null, isConnecting: false, error: null } }),
}));
vi.mock("../lib/rpc-fb", () => ({
    getSystemPropertyFlatBuffer: vi.fn(async () => null),
    invokeWelcomeMessageFlatBuffer: vi.fn(async () => ({ welcomeMessage: "", contentType: "text/plain" })),
}));
vi.mock("./ContentRenderer", () => ({ ContentRenderer: () => null }));
vi.mock("./OAuth2Buttons", () => ({ OAuth2Buttons: () => null }));
vi.mock("./ThemeProvider", () => ({ useTheme: () => ({ theme: "light", setTheme: vi.fn() }) }));

describe("Login", () => {
    it("logs in once when Enter is pressed in a field", () => {
        const onConnect = vi.fn();
        const { container } = render(
            <Login
                visible
                welcomeMessage=""
                contentType="text/plain"
                isServerReady
                onConnect={onConnect}
            />,
        );
        const username = container.querySelector<HTMLInputElement>("#login_username")!;
        const password = container.querySelector<HTMLInputElement>("#login_password")!;
        fireEvent.change(username, { target: { value: "wizard" } });
        fireEvent.change(password, { target: { value: "secret" } });

        // What a browser does for Enter in a field: it submits the form as the key goes down, and
        // the field then sees the key come up.
        fireEvent.keyDown(password, { key: "Enter" });
        fireEvent.submit(container.querySelector("form#login-form-panel")!);
        fireEvent.keyUp(password, { key: "Enter" });

        expect(onConnect).toHaveBeenCalledTimes(1);
    });
});
