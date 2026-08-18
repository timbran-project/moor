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

import React, { useEffect, useState } from "react";
import { useCarouselOverflow } from "../../hooks/useCarouselOverflow";
import { Presentation } from "../../types/presentation";
import { Panel } from "../Panel";

interface TopDockProps {
    presentations: Presentation[];
    onClosePresentation: (id: string) => void;
    onLinkClick?: (url: string, position?: { x: number; y: number }) => void;
    onLinkHoldStart?: (url: string, position: { x: number; y: number }) => void;
    onLinkHoldEnd?: () => void;
}

export const TopDock: React.FC<TopDockProps> = (
    { presentations, onClosePresentation, onLinkClick, onLinkHoldStart, onLinkHoldEnd },
) => {
    const { containerRef, hasOverflow, hasScroll } = useCarouselOverflow();
    const [isDockCollapsed, setIsDockCollapsed] = useState(false);
    const [canUseDockCollapse, setCanUseDockCollapse] = useState(false);
    const [collapsedPanelIds, setCollapsedPanelIds] = useState<Set<string>>(new Set());
    const DOCK_TO_NARRATIVE_RATIO_THRESHOLD = 0.25;

    useEffect(() => {
        setCollapsedPanelIds((prev) => {
            const validIds = new Set(presentations.map((presentation) => presentation.id));
            const next = new Set<string>();
            prev.forEach((id) => {
                if (validIds.has(id)) {
                    next.add(id);
                }
            });
            return next;
        });
    }, [presentations]);

    useEffect(() => {
        const evaluateDockCollapseAvailability = () => {
            const topDockEl = containerRef.current;
            const narrativeEl = document.getElementById("narrative");
            if (!topDockEl || !narrativeEl) {
                setCanUseDockCollapse(false);
                return;
            }

            const topDockHeight = topDockEl.getBoundingClientRect().height;
            const narrativeHeight = narrativeEl.getBoundingClientRect().height;
            if (narrativeHeight <= 0) {
                setCanUseDockCollapse(false);
                return;
            }

            const shouldEnable = isDockCollapsed
                || (topDockHeight / narrativeHeight) > DOCK_TO_NARRATIVE_RATIO_THRESHOLD;
            setCanUseDockCollapse(shouldEnable);
            if (!shouldEnable) {
                setIsDockCollapsed(false);
            }
        };

        evaluateDockCollapseAvailability();
        const timeoutId = window.setTimeout(evaluateDockCollapseAvailability, 0);
        window.addEventListener("resize", evaluateDockCollapseAvailability);

        const topDockEl = containerRef.current;
        const narrativeEl = document.getElementById("narrative");
        const observers: ResizeObserver[] = [];

        if (typeof ResizeObserver !== "undefined") {
            if (topDockEl) {
                const topDockObserver = new ResizeObserver(() => evaluateDockCollapseAvailability());
                topDockObserver.observe(topDockEl);
                observers.push(topDockObserver);
            }
            if (narrativeEl) {
                const narrativeObserver = new ResizeObserver(() => evaluateDockCollapseAvailability());
                narrativeObserver.observe(narrativeEl);
                observers.push(narrativeObserver);
            }
        }

        return () => {
            window.clearTimeout(timeoutId);
            window.removeEventListener("resize", evaluateDockCollapseAvailability);
            observers.forEach((observer) => observer.disconnect());
        };
    }, [containerRef, isDockCollapsed, presentations]);

    if (presentations.length === 0) {
        return null;
    }

    // Debug logging for React state
    // console.log('TopDock render:', { hasOverflow, hasScroll });

    const className = [
        "top_dock",
        isDockCollapsed && canUseDockCollapse && "top_dock_collapsed",
        presentations.length === 1 && "single-panel",
        hasOverflow && "has-overflow",
        hasScroll && "has-scroll",
    ].filter(Boolean).join(" ");

    const togglePanelCollapse = (presentationId: string) => {
        setCollapsedPanelIds((prev) => {
            const next = new Set(prev);
            if (next.has(presentationId)) {
                next.delete(presentationId);
            } else {
                next.add(presentationId);
            }
            return next;
        });
    };

    return (
        <>
            <div
                id="top-dock-panels"
                ref={containerRef}
                className={className}
                style={{ display: "flex" }}
            >
                <h2 className="sr-only">Top Dock Panels</h2>
                <div className="sr-only" role="status" aria-live="polite">
                    {canUseDockCollapse ? (isDockCollapsed ? "Room area collapsed" : "Room area expanded") : ""}
                </div>
                {presentations.map((presentation) => (
                    (() => {
                        const panelCollapsed = collapsedPanelIds.has(presentation.id);
                        const contentId = `top-dock-panel-content-${presentation.id.replace(/[^a-zA-Z0-9_-]/g, "-")}`;
                        return (
                            <Panel
                                key={presentation.id}
                                presentation={presentation}
                                onClose={onClosePresentation}
                                contentId={contentId}
                                className="top_dock_panel"
                                titleClassName="top_dock_panel_title"
                                contentClassName={`top_dock_panel_content ${
                                    panelCollapsed ? "top_dock_panel_content_collapsed" : ""
                                }`}
                                closeButtonClassName="top_dock_panel_close"
                                headerActions={
                                    <button
                                        type="button"
                                        className="top_dock_panel_toggle"
                                        onClick={() => togglePanelCollapse(presentation.id)}
                                        aria-expanded={!panelCollapsed}
                                        aria-controls={contentId}
                                        aria-label={panelCollapsed
                                            ? `Expand ${presentation.title} panel`
                                            : `Collapse ${presentation.title} panel`}
                                    >
                                        <span
                                            aria-hidden="true"
                                            className={`top_dock_panel_toggle_chevron ${
                                                panelCollapsed ? "collapsed" : "expanded"
                                            }`}
                                        >
                                            ▼
                                        </span>
                                    </button>
                                }
                                onLinkClick={onLinkClick}
                                onLinkHoldStart={onLinkHoldStart}
                                onLinkHoldEnd={onLinkHoldEnd}
                            />
                        );
                    })()
                ))}
            </div>
            {hasOverflow && !isDockCollapsed && (
                <div
                    aria-hidden="true"
                    style={{
                        position: "absolute",
                        top: "50%",
                        right: "8px",
                        transform: "translateY(-50%)",
                        fontSize: "24px",
                        color: "white",
                        background: "rgba(0, 0, 0, 0.8)",
                        borderRadius: "50%",
                        width: "36px",
                        height: "36px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontWeight: "bold",
                        pointerEvents: "none",
                        zIndex: 1000,
                    }}
                >
                    ›
                </div>
            )}
            {hasScroll && !isDockCollapsed && (
                <div
                    aria-hidden="true"
                    style={{
                        position: "absolute",
                        top: "50%",
                        left: "8px",
                        transform: "translateY(-50%)",
                        fontSize: "24px",
                        color: "white",
                        background: "rgba(0, 0, 0, 0.8)",
                        borderRadius: "50%",
                        width: "36px",
                        height: "36px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontWeight: "bold",
                        pointerEvents: "none",
                        zIndex: 1000,
                    }}
                >
                    ‹
                </div>
            )}
            {canUseDockCollapse && (
                <button
                    type="button"
                    className="top_dock_mobile_handle"
                    onClick={() => setIsDockCollapsed(prev => !prev)}
                    aria-expanded={!isDockCollapsed}
                    aria-controls="top-dock-panels"
                    aria-label={isDockCollapsed ? "Expand room area" : "Collapse room area"}
                >
                    <span className={`top_dock_mobile_handle_chevron ${isDockCollapsed ? "collapsed" : "expanded"}`}>
                        ▼
                    </span>
                </button>
            )}
        </>
    );
};
