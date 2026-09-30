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
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ExternalNavigationProvider } from "../context/ExternalNavigationContext";
import { createTranscript } from "../lib/transcript";
import { addTrustedDomain, clearAllTrustedDomains, getTrustedDomains } from "../lib/trusted-domains";
import { LinkPreview, LinkPreviewCard } from "./LinkPreviewCard";
import { OutputWindow } from "./OutputWindow";
import { ToastProvider } from "./Toast";

const preview: LinkPreview = {
    url: "https://article.example/story",
    title: "A story",
    description: "Read about it",
    site_name: "A publisher",
    image: "https://images.example/thumbnail.png",
};

function card(value = preview) {
    return <LinkPreviewCard preview={value} metadata={{ actorName: "Alex", verb: "say" }} />;
}

describe("link preview navigation and remote images", () => {
    beforeEach(() => {
        clearAllTrustedDomains();
        vi.spyOn(window, "open").mockReturnValue(null);
    });
    afterEach(() => {
        vi.restoreAllMocks();
        clearAllTrustedDomains();
    });

    it("confirms navigation with the actual host and event context", () => {
        const { container } = render(card(), { wrapper: ExternalNavigationProvider });
        expect(container.querySelector("a[href]")).toBeNull();
        expect(screen.getByText("A publisher · article.example")).not.toBeNull();
        fireEvent.click(screen.getByRole("button", { name: /open link preview/i }));
        expect(screen.getByRole("alertdialog").textContent).toContain("Alex shared this link via say");
        expect(window.open).not.toHaveBeenCalled();
        fireEvent.click(screen.getByRole("button", { name: "Visit Site" }));
        expect(window.open).toHaveBeenCalledWith(preview.url, "_blank", "noopener,noreferrer");
        expect(container.querySelector("img")).toBeNull();
    });

    it("allows cancelling a preview without navigating or loading its image", () => {
        const { container } = render(card(), { wrapper: ExternalNavigationProvider });
        fireEvent.click(screen.getByRole("button", { name: /open link preview/i }));
        fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
        expect(window.open).not.toHaveBeenCalled();
        expect(container.querySelector("img")).toBeNull();
    });

    it("honors navigation trust without granting image-loading permission", () => {
        addTrustedDomain("article.example");
        addTrustedDomain("images.example");
        const { container } = render(card(), { wrapper: ExternalNavigationProvider });
        fireEvent.click(screen.getByRole("button", { name: /open link preview/i }));
        expect(window.open).toHaveBeenCalledWith(preview.url, "_blank", "noopener,noreferrer");
        expect(screen.queryByRole("alertdialog")).toBeNull();
        expect(container.querySelector("img")).toBeNull();
        expect(screen.getByRole("button", { name: "Load image from images.example" })).not.toBeNull();
    });

    it("loads an image only on explicit request without navigating or trusting its host", () => {
        const { container } = render(card(), { wrapper: ExternalNavigationProvider });
        expect(container.querySelector("img")).toBeNull();
        fireEvent.click(screen.getByRole("button", { name: "Load image from images.example" }));
        const image = container.querySelector("img");
        expect(image?.getAttribute("src")).toBe(preview.image);
        expect(image?.getAttribute("referrerpolicy")).toBe("no-referrer");
        expect(window.open).not.toHaveBeenCalled();
        expect(screen.queryByRole("alertdialog")).toBeNull();
        expect(getTrustedDomains()).toEqual([]);
    });

    it.each([
        { ...preview, image: "https://other-images.example/new.png" },
        { ...preview, url: "https://other-article.example/new" },
    ])("requires fresh image consent when the card destination or image changes: %j", (replacement) => {
        const { container, rerender } = render(card(), { wrapper: ExternalNavigationProvider });
        fireEvent.click(screen.getByRole("button", { name: /load image from/i }));
        expect(container.querySelector("img")).not.toBeNull();
        rerender(card(replacement));
        expect(container.querySelector("img")).toBeNull();
        expect(screen.getByRole("button", { name: /load image from/i })).not.toBeNull();
        rerender(card());
        expect(container.querySelector("img")).toBeNull();
    });

    it.each([
        "javascript:alert(1)",
        "java\nscript:alert(1)",
        "data:text/html,test",
        "file:///tmp/test",
        "blob:https://article.example/id",
        "ftp://article.example/image",
        "//article.example/image",
        "/relative",
        "not a URL",
        "",
    ])("rejects an unsafe preview destination or image: %s", (url) => {
        const { container, rerender } = render(card({ ...preview, url }), { wrapper: ExternalNavigationProvider });
        expect(container.querySelector("article")).toBeNull();
        rerender(card({ ...preview, image: url }));
        expect(screen.getByRole("button", { name: /open link preview/i })).not.toBeNull();
        expect(screen.queryByRole("button", { name: /load image/i })).toBeNull();
        expect(container.querySelector("img")).toBeNull();
        expect(window.open).not.toHaveBeenCalled();
    });

    it.each([undefined, "An accessible summary"])("keeps output preview controls accessible with TTS %s", (ttsText) => {
        render(
            <ExternalNavigationProvider>
                <ToastProvider>
                    <OutputWindow
                        transcript={(() => {
                            const transcript = createTranscript();
                            transcript.replace([{
                                id: "preview-event",
                                content: "A story was shared",
                                type: "narrative",
                                ttsText,
                                linkPreview: preview,
                                eventMetadata: { actorName: "Alex", verb: "say" },
                            }]);
                            return transcript;
                        })()}
                    />
                </ToastProvider>
            </ExternalNavigationProvider>,
        );
        fireEvent.click(screen.getByRole("button", { name: /open link preview/i }));
        expect(screen.getByRole("alertdialog").textContent).toContain("Alex shared this link via say");
        expect(window.open).not.toHaveBeenCalled();
    });
});
