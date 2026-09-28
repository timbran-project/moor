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
