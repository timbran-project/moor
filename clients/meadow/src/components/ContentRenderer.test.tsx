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

import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ContentRenderer } from "./ContentRenderer";

vi.mock("./Toast", () => ({
    useToast: () => ({ showToast: vi.fn() }),
}));

describe("ContentRenderer URI embeds", () => {
    it.each([
        "javascript:alert(document.domain)",
        "data:text/html,<script>alert(document.domain)</script>",
        "file:///etc/passwd",
        "http://[",
    ])("blocks an unsafe URI: %s", uri => {
        const { container } = render(<ContentRenderer content={uri} contentType="text/x-uri" />);

        expect(container.querySelector("iframe")).toBeNull();
        expect(screen.getByText(/embedded content was blocked/i)).toBeDefined();
    });

    it("isolates an HTTPS embed in a script-only sandbox", () => {
        render(<ContentRenderer content="https://example.com/welcome" contentType="text/x-uri" />);

        const iframe = screen.getByTitle("Embedded content");
        expect(iframe.getAttribute("src")).toBe("https://example.com/welcome");
        expect(iframe.getAttribute("sandbox")).toBe("allow-scripts");
    });

    it("resolves a relative embed against the application origin", () => {
        render(<ContentRenderer content="/welcome" contentType="text/x-uri" />);

        expect(screen.getByTitle("Embedded content").getAttribute("src")).toBe(
            `${window.location.origin}/welcome`,
        );
    });
});
