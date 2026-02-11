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

import React, { useEffect, useMemo, useRef, useState } from "react";
import { Presentation } from "../types/presentation";
import { ContentRenderer } from "./ContentRenderer";

interface PanelProps {
    presentation: Presentation;
    onClose: (id: string) => void;
    className: string;
    titleClassName: string;
    contentClassName: string;
    closeButtonClassName: string;
    contentId?: string;
    headerActions?: React.ReactNode;
    onLinkClick?: (url: string, position?: { x: number; y: number }) => void;
    onLinkHoldStart?: (url: string, position: { x: number; y: number }) => void;
    onLinkHoldEnd?: () => void;
}

export const Panel: React.FC<PanelProps> = ({
    presentation,
    onClose,
    className,
    titleClassName,
    contentClassName,
    closeButtonClassName,
    contentId,
    headerActions,
    onLinkClick,
    onLinkHoldStart,
    onLinkHoldEnd,
}) => {
    const [isRoomLookRefreshing, setIsRoomLookRefreshing] = useState(false);
    const refreshTimeoutRef = useRef<number | null>(null);
    const previousSignatureRef = useRef<string | null>(null);

    const roomLookKind = presentation.attrs.kind;
    const isRoomLook = roomLookKind === "room_look" || roomLookKind === "room-look";

    const contentSignature = useMemo(() => {
        const content = presentation.content;
        if (typeof content == "string") {
            return content;
        }
        if (Array.isArray(content)) {
            return content.join("\n");
        }
        return "";
    }, [presentation.content]);

    useEffect(() => {
        if (!isRoomLook) {
            previousSignatureRef.current = null;
            setIsRoomLookRefreshing(false);
            return;
        }

        const signature = `${presentation.title}\n${contentSignature}`;
        if (previousSignatureRef.current === null) {
            previousSignatureRef.current = signature;
            return;
        }

        if (previousSignatureRef.current === signature) {
            return;
        }

        previousSignatureRef.current = signature;
        setIsRoomLookRefreshing(true);

        if (refreshTimeoutRef.current !== null) {
            window.clearTimeout(refreshTimeoutRef.current);
        }
        refreshTimeoutRef.current = window.setTimeout(() => {
            setIsRoomLookRefreshing(false);
            refreshTimeoutRef.current = null;
        }, 220);
    }, [contentSignature, isRoomLook, presentation.title]);

    useEffect(() => {
        return () => {
            if (refreshTimeoutRef.current !== null) {
                window.clearTimeout(refreshTimeoutRef.current);
            }
        };
    }, []);

    const handleClose = () => {
        onClose(presentation.id);
    };

    const panelClassName = [
        className,
        isRoomLook && "room_look_panel",
        isRoomLookRefreshing && "room_look_panel_refresh",
    ].filter(Boolean).join(" ");

    return (
        <div className={panelClassName}>
            <div className={titleClassName}>
                <span>{presentation.title}</span>
                {headerActions}
                <button
                    type="button"
                    className={closeButtonClassName}
                    onClick={handleClose}
                    aria-label={`Close ${presentation.title} panel`}
                >
                    <span aria-hidden="true">×</span>
                </button>
            </div>
            <div id={contentId} className={contentClassName}>
                <ContentRenderer
                    content={presentation.content}
                    contentType={presentation.contentType}
                    onLinkClick={onLinkClick}
                    onLinkHoldStart={onLinkHoldStart}
                    onLinkHoldEnd={onLinkHoldEnd}
                />
            </div>
        </div>
    );
};
