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

import { AnnotationTable } from "@moor/web-sdk";
import React, { useCallback, useEffect, useMemo, useRef } from "react";
import { useAnnotationActivation } from "../context/AnnotationContext";
import { useArgumentCoordinator } from "../context/ArgumentContext";
import { renderDjot, renderHtmlContent, renderPlainText } from "../lib/djot-renderer";

export interface EventMetadata {
    verb?: string;
    actorName?: string;
    thisName?: string;
    dobjName?: string;
    annotations?: AnnotationTable;
}

interface ContentRendererProps {
    content: string | string[];
    contentType?: "text/plain" | "text/djot" | "text/html" | "text/traceback" | "text/x-uri";
    onLinkClick?: (
        url: string,
        position?: { x: number; y: number },
        metadata?: { actorName?: string; verb?: string },
    ) => void | Promise<void>;
    isStale?: boolean;
    enableEmoji?: boolean;
    eventMetadata?: EventMetadata;
}

export function normalizeEmbeddedUri(uri: string, baseUrl: string = window.location.href): string | null {
    try {
        const parsed = new URL(uri, baseUrl);
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
            return null;
        }
        return parsed.href;
    } catch {
        return null;
    }
}

export const ContentRenderer: React.FC<ContentRendererProps> = ({
    content,
    contentType = "text/plain",
    onLinkClick,
    isStale = false,
    enableEmoji = false,
    eventMetadata,
}) => {
    const activateAnnotation = useAnnotationActivation();
    const coordinator = useArgumentCoordinator();
    const container = useRef<HTMLSpanElement>(null);
    const annotations = eventMetadata?.annotations;
    const source = Array.isArray(content) ? content.join(contentType === "text/x-uri" ? "" : "\n") : String(content);
    const html = useMemo(() => {
        if (contentType === "text/html") return renderHtmlContent(source, enableEmoji, annotations);
        if (contentType === "text/djot") {
            try {
                return renderDjot(source, {
                    annotations,
                    enableEmoji,
                    addTableClass: true,
                    linkHandler: { className: "moo-link", dataAttribute: "data-url" },
                });
            } catch (error) {
                console.warn("Failed to parse Djot:", error);
            }
        }
        return renderPlainText(source, enableEmoji);
    }, [source, contentType, enableEmoji, annotations]);

    useEffect(() => {
        const releases: (() => void)[] = [];
        container.current?.querySelectorAll<HTMLElement>("[data-moor-annotation]").forEach(element => {
            const annotation = annotations?.[element.dataset.moorAnnotation ?? ""];
            if (coordinator && annotation?.kind === "object") {
                releases.push(coordinator.register(element, annotation.ref));
            }
        });
        return () => releases.forEach(release => release());
    }, [html, annotations, coordinator]);

    const activate = useCallback((event: React.MouseEvent | React.KeyboardEvent) => {
        const target = (event.target as HTMLElement).closest<HTMLElement>("[data-moor-annotation], [data-url]");
        if (!target || !event.currentTarget.contains(target)) return;
        // Preserve dragging to select prose and native copy on pointer/touch devices.
        if (event.type === "click" && window.getSelection()?.isCollapsed === false) return;
        const rect = target.getBoundingClientRect();
        const position = { x: rect.left + rect.width / 2, y: rect.bottom };
        const id = target.dataset.moorAnnotation;
        if (id && annotations && Object.prototype.hasOwnProperty.call(annotations, id) && activateAnnotation) {
            event.preventDefault();
            event.stopPropagation();
            target.focus({ preventScroll: true });
            activateAnnotation({ annotation: annotations[id], label: target.textContent ?? "", position });
            return;
        }
        const url = target.dataset.url;
        if (!url || !/^https?:\/\//.test(url) || !onLinkClick) return;
        event.preventDefault();
        void onLinkClick(url, position, { actorName: eventMetadata?.actorName, verb: eventMetadata?.verb });
    }, [activateAnnotation, annotations, onLinkClick, eventMetadata?.actorName, eventMetadata?.verb]);

    const keyDown = useCallback((event: React.KeyboardEvent) => {
        if (event.key === "Enter" || event.key === " ") activate(event);
    }, [activate]);

    const staleClass = isStale ? " content-stale" : "";
    if (contentType === "text/traceback") return <pre className={`traceback_narrative${staleClass}`}>{source}</pre>;
    if (contentType === "text/x-uri") {
        const uri = normalizeEmbeddedUri(source.trim());
        return uri
            ? <iframe src={uri} className="content-iframe" title="Embedded content" sandbox="allow-scripts" />
            : <span className="content-text">Embedded content was blocked because its URL is unsafe.</span>;
    }
    return (
        <span ref={container} className="content-renderer">
            <span
                className={`${contentType === "text/plain" ? "content-text" : "content-html"}${
                    contentType === "text/djot" ? " text_djot" : ""
                }${staleClass}`}
                dangerouslySetInnerHTML={{ __html: html }}
                onClick={activate}
                onKeyDown={keyDown}
            />
        </span>
    );
};
