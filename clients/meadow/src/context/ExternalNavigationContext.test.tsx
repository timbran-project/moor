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

import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { clearAllTrustedDomains, getTrustedDomains } from "../lib/trusted-domains";
import { ExternalNavigationProvider, useExternalNavigation } from "./ExternalNavigationContext";

function installLocalStorageMock() {
    let store: Record<string, string> = {};
    Object.defineProperty(window, "localStorage", {
        configurable: true,
        value: {
            getItem: (key: string) => store[key] ?? null,
            setItem: (key: string, value: string) => {
                store[key] = value;
            },
            removeItem: (key: string) => {
                delete store[key];
            },
            clear: () => {
                store = {};
            },
        },
    });
}

function NavigationProbe({ url }: { url: string }) {
    const { openExternalLink } = useExternalNavigation();
    return (
        <button type="button" onClick={() => openExternalLink(url, { actorName: "Wizard" })}>
            navigate
        </button>
    );
}

describe("ExternalNavigationProvider", () => {
    afterEach(() => {
        vi.restoreAllMocks();
        clearAllTrustedDomains();
    });

    it("opens trusted domains directly without confirmation", async () => {
        installLocalStorageMock();
        localStorage.setItem(
            "moor-trusted-external-domains",
            JSON.stringify({ domains: ["trusted.example"], version: 1 }),
        );
        const open = vi.spyOn(window, "open").mockReturnValue(null);

        render(
            <ExternalNavigationProvider>
                <NavigationProbe url="https://trusted.example/page" />
            </ExternalNavigationProvider>,
        );

        fireEvent.click(screen.getByRole("button", { name: "navigate" }));

        expect(open).toHaveBeenCalledWith("https://trusted.example/page", "_blank", "noopener,noreferrer");
        expect(screen.queryByRole("alertdialog")).toBeNull();
    });

    it("requires confirmation for untrusted domains and remembers trust on confirm", async () => {
        installLocalStorageMock();
        const open = vi.spyOn(window, "open").mockReturnValue(null);

        render(
            <ExternalNavigationProvider>
                <NavigationProbe url="https://untrusted.example/page" />
            </ExternalNavigationProvider>,
        );

        fireEvent.click(screen.getByRole("button", { name: "navigate" }));

        // Modal is shown instead of opening directly
        await waitFor(() => {
            expect(screen.getByRole("alertdialog")).not.toBeNull();
        });
        expect(open).not.toHaveBeenCalled();

        // Opt into trusting the domain, then proceed
        fireEvent.click(screen.getByLabelText(/don't ask again/i));
        fireEvent.click(screen.getByRole("button", { name: /visit site/i }));

        expect(open).toHaveBeenCalledWith("https://untrusted.example/page", "_blank", "noopener,noreferrer");
        expect(getTrustedDomains()).toContain("untrusted.example");
        await waitFor(() => {
            expect(screen.queryByRole("alertdialog")).toBeNull();
        });
    });

    it("does not remember the domain when confirming without trust", async () => {
        installLocalStorageMock();
        const open = vi.spyOn(window, "open").mockReturnValue(null);

        render(
            <ExternalNavigationProvider>
                <NavigationProbe url="https://once.example/page" />
            </ExternalNavigationProvider>,
        );

        fireEvent.click(screen.getByRole("button", { name: "navigate" }));
        await waitFor(() => {
            expect(screen.getByRole("alertdialog")).not.toBeNull();
        });

        fireEvent.click(screen.getByRole("button", { name: /visit site/i }));

        expect(open).toHaveBeenCalled();
        expect(getTrustedDomains()).not.toContain("once.example");
        await waitFor(() => {
            expect(screen.queryByRole("alertdialog")).toBeNull();
        });
    });

    it("closes the modal without navigation on cancel", async () => {
        installLocalStorageMock();
        const open = vi.spyOn(window, "open").mockReturnValue(null);

        render(
            <ExternalNavigationProvider>
                <NavigationProbe url="https://cancel.example/page" />
            </ExternalNavigationProvider>,
        );

        fireEvent.click(screen.getByRole("button", { name: "navigate" }));
        await waitFor(() => {
            expect(screen.getByRole("alertdialog")).not.toBeNull();
        });

        fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

        expect(open).not.toHaveBeenCalled();
        await waitFor(() => {
            expect(screen.queryByRole("alertdialog")).toBeNull();
        });
    });

    it("throws when used outside the provider", () => {
        function Orphan() {
            useExternalNavigation();
            return null;
        }
        const spy = vi.spyOn(console, "error").mockImplementation(() => {});
        expect(() => render(<Orphan />)).toThrow(/ExternalNavigationProvider/);
        spy.mockRestore();
    });
});
