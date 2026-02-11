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
import { useMediaQuery } from "../../hooks/useMediaQuery";
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
    const isSpaceConstrained = useMediaQuery("(max-height: 860px)");
    const [isCollapsed, setIsCollapsed] = useState(false);
    const [canCollapse, setCanCollapse] = useState(false);
    const COLLAPSED_CONTENT_MAX_HEIGHT_PX = 112;

    useEffect(() => {
        setIsCollapsed(isSpaceConstrained);
    }, [isSpaceConstrained, presentations.length]);

    useEffect(() => {
        if (!isSpaceConstrained) {
            setCanCollapse(false);
            return;
        }

        const evaluateCanCollapse = () => {
            const container = containerRef.current;
            if (!container) {
                setCanCollapse(false);
                return;
            }

            const contentNodes = Array.from(container.querySelectorAll(".top_dock_panel_content"));
            if (contentNodes.length === 0) {
                setCanCollapse(false);
                return;
            }

            const needsCollapse = contentNodes.some((node) => {
                const el = node as HTMLElement;
                return el.scrollHeight > (COLLAPSED_CONTENT_MAX_HEIGHT_PX + 2);
            });
            setCanCollapse(needsCollapse);
            if (!needsCollapse) {
                setIsCollapsed(false);
            }
        };

        evaluateCanCollapse();
        const timeoutId = window.setTimeout(evaluateCanCollapse, 0);
        window.addEventListener("resize", evaluateCanCollapse);

        return () => {
            window.clearTimeout(timeoutId);
            window.removeEventListener("resize", evaluateCanCollapse);
        };
    }, [containerRef, isSpaceConstrained, presentations]);

    if (presentations.length === 0) {
        return null;
    }

    // Debug logging for React state
    // console.log('TopDock render:', { hasOverflow, hasScroll });

    const className = [
        "top_dock",
        isSpaceConstrained && "top_dock_compact",
        isCollapsed && canCollapse && "top_dock_collapsed",
        presentations.length === 1 && "single-panel",
        hasOverflow && "has-overflow",
        hasScroll && "has-scroll",
    ].filter(Boolean).join(" ");

    const shouldShowHeaderToggle = isSpaceConstrained && canCollapse;

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
                    {shouldShowHeaderToggle ? (isCollapsed ? "Room panel collapsed" : "Room panel expanded") : ""}
                </div>
                {presentations.map((presentation) => (
                    <Panel
                        key={presentation.id}
                        presentation={presentation}
                        onClose={onClosePresentation}
                        contentId={`top-dock-panel-content-${presentation.id.replace(/[^a-zA-Z0-9_-]/g, "-")}`}
                        className="top_dock_panel"
                        titleClassName="top_dock_panel_title"
                        contentClassName="top_dock_panel_content"
                        closeButtonClassName="top_dock_panel_close"
                        headerActions={shouldShowHeaderToggle
                            ? (
                                <button
                                    type="button"
                                    className="top_dock_panel_toggle"
                                    onClick={() => setIsCollapsed(prev => !prev)}
                                    aria-expanded={!isCollapsed}
                                    aria-controls={`top-dock-panel-content-${
                                        presentation.id.replace(/[^a-zA-Z0-9_-]/g, "-")
                                    }`}
                                    aria-label={isCollapsed ? "Expand room panel" : "Collapse room panel"}
                                >
                                    <span
                                        aria-hidden="true"
                                        className={`top_dock_panel_toggle_chevron ${
                                            isCollapsed ? "collapsed" : "expanded"
                                        }`}
                                    >
                                        ▼
                                    </span>
                                </button>
                            )
                            : undefined}
                        onLinkClick={onLinkClick}
                        onLinkHoldStart={onLinkHoldStart}
                        onLinkHoldEnd={onLinkHoldEnd}
                    />
                ))}
            </div>
            {hasOverflow && !isCollapsed && !isSpaceConstrained && (
                <div
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
            {hasScroll && !isCollapsed && !isSpaceConstrained && (
                <div
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
            {isSpaceConstrained && canCollapse && (
                <button
                    type="button"
                    className="top_dock_mobile_handle"
                    onClick={() => setIsCollapsed(prev => !prev)}
                    aria-expanded={!isCollapsed}
                    aria-controls="top-dock-panels"
                    aria-label={isCollapsed ? "Expand room panel" : "Collapse room panel"}
                >
                    <span className={`top_dock_mobile_handle_chevron ${isCollapsed ? "collapsed" : "expanded"}`}>
                        ▼
                    </span>
                </button>
            )}
        </>
    );
};
