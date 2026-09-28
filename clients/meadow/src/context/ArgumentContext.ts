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

import { buildStructuredArgs } from "@moor/web-sdk";
import { createContext, useContext } from "react";
import { Suggestion, SuggestionSource } from "../hooks/useSuggestions";
import { invokeVerbFlatBuffer } from "../lib/rpc-fb";

export interface ArgumentTarget {
    id: string;
    label: string;
    source: SuggestionSource;
    choose: (item: Suggestion) => void;
    feedback: (message: string) => void;
}
export interface Eligibility {
    eligible: boolean;
    label?: string;
    value?: string;
    reason?: string;
}

export async function checkReferences(token: string, source: SuggestionSource, references: string[]) {
    const { result } = await invokeVerbFlatBuffer(
        token,
        source.provider,
        "suggestion_eligibility",
        buildStructuredArgs([source.source, references, source.context ? { ...source.context } : {}]),
    );
    return result as Record<string, Eligibility>;
}

/** One coordinator per connected surface. Advisory changes touch visible markers, not retained React history. */
export class ArgumentCoordinator {
    private target?: ArgumentTarget;
    private token: string | null = null;
    private blocked = false;
    private generation = 0;
    private timer?: ReturnType<typeof setTimeout>;
    private nodes = new Map<HTMLElement, { reference: string; title: string; aria: string; visible: boolean }>();
    private observer = typeof IntersectionObserver === "undefined" ? undefined : new IntersectionObserver(entries => {
        for (const entry of entries) {
            const node = this.nodes.get(entry.target as HTMLElement);
            if (node) node.visible = entry.isIntersecting;
        }
        this.schedule();
    });

    configure(token: string | null, blocked: boolean) {
        if (token !== this.token) this.target = undefined;
        this.token = token;
        this.blocked = blocked;
        this.invalidate();
    }
    focus(target?: ArgumentTarget) {
        this.target = target;
        this.invalidate();
    }
    owns(id: string) {
        return this.target?.id === id;
    }
    release(id: string) {
        if (this.owns(id)) this.focus();
    }
    invalidate() {
        ++this.generation;
        this.schedule();
    }
    dispose() {
        clearTimeout(this.timer);
        this.observer?.disconnect();
        this.nodes.clear();
        this.focus();
        clearTimeout(this.timer);
    }
    register(element: HTMLElement, reference: string) {
        this.nodes.set(element, {
            reference,
            title: element.title,
            aria: element.getAttribute("aria-label") ?? "",
            visible: !this.observer,
        });
        this.observer?.observe(element);
        this.schedule();
        return () => {
            this.observer?.unobserve(element);
            this.nodes.delete(element);
        };
    }
    private schedule() {
        clearTimeout(this.timer);
        this.timer = setTimeout(() => {
            void this.refresh();
        }, 120);
    }
    private async refresh() {
        const target = this.target;
        const token = this.token;
        const generation = this.generation;
        for (const [element, node] of this.nodes) {
            element.title = node.title;
            element.setAttribute("aria-label", node.aria);
            element.removeAttribute("data-argument-eligible");
        }
        if (!target || !token || this.blocked) return;
        const visible = [...this.nodes].filter(([, node]) => node.visible);
        const references = [...new Set(visible.map(([, node]) => node.reference))].slice(0, 256);
        for (let i = 0; i < references.length; i += 64) {
            let result: Record<string, Eligibility>;
            try {
                result = await checkReferences(token, target.source, references.slice(i, i + 64));
            } catch {
                return;
            }
            if (generation !== this.generation) return;
            for (const [element, node] of visible) {
                if (!this.nodes.has(element)) continue;
                const choice = result[node.reference];
                if (!choice) continue;
                const title = choice.eligible
                    ? `Use ${element.textContent} for ${target.label}`
                    : "Unavailable for this argument";
                element.title = title;
                element.setAttribute("aria-label", title);
                element.dataset.argumentEligible = String(choice.eligible);
            }
        }
    }
    /** Activation rechecks even a cached eligible marker. Filling never submits. */
    select(reference: string): boolean {
        const target = this.target;
        const token = this.token;
        const generation = this.generation;
        if (!target || !token || this.blocked) return false;
        target.feedback("Checking reference…");
        void checkReferences(token, target.source, [reference]).then(result => {
            if (generation !== this.generation) return;
            const item = result[reference];
            if (!item?.eligible || !item.label || !item.value) {
                target.feedback(item?.reason ?? "That reference is unavailable for this argument.");
                return;
            }
            target.choose({ id: reference, label: item.label, value: item.value, detail: item.value });
            target.feedback(`${item.label} selected. Review the command before submitting.`);
        }).catch(() => {
            if (generation === this.generation) target.feedback("Could not check this reference. Try again.");
        });
        return true;
    }
}

export const ArgumentContext = createContext<ArgumentCoordinator | null>(null);
export const useArgumentCoordinator = () => useContext(ArgumentContext);
