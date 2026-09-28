// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { renderHook } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { useNarrativeLinks } from "./useNarrativeLinks";

const { openExternalLink } = vi.hoisted(() => ({ openExternalLink: vi.fn() }));
vi.mock("../context/ExternalNavigationContext", () => ({ useExternalNavigation: () => ({ openExternalLink }) }));

describe("narrative URL routing", () => {
    it("routes external links with their event context", () => {
        const { result } = renderHook(() => useNarrativeLinks());
        result.current.handleLinkClick("https://example.com", undefined, { actorName: "Alex" });
        expect(openExternalLink).toHaveBeenCalledWith("https://example.com", { actorName: "Alex" });
    });
    it("cannot execute historic scheme-only action links", () => {
        openExternalLink.mockClear();
        const { result } = renderHook(() => useNarrativeLinks());
        for (const url of ["moo://exit/oid:10/oid:20/id", "moo://cmd/go%20east", "moo://inspect/oid:10"]) {
            result.current.handleLinkClick(url);
        }
        expect(openExternalLink).not.toHaveBeenCalled();
    });
});
