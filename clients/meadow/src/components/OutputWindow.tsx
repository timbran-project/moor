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

import { parse, renderHTML } from "@djot/djot";
import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { useTranscriptWindow } from "../hooks/useTranscriptWindow";
import { roomLookKey as getRoomLookKeyFromMessage, type Transcript } from "../lib/transcript";
import { ContentRenderer } from "./ContentRenderer";
import { getEmojiEnabled } from "./EmojiToggle";
import { LinkPreview, LinkPreviewCard } from "./LinkPreviewCard";
import type { EventMetadata, NarrativeMessage } from "./Narrative";

function announcementText(message: NarrativeMessage): string {
    if (message.ttsText) return message.ttsText;
    const source = Array.isArray(message.content) ? message.content.join("\n") : message.content;
    if (message.contentType !== "text/djot" && message.contentType !== "text/html") return source;
    try {
        // Template contents stay inert: announcing offscreen HTML must not load its images.
        const template = document.createElement("template");
        template.innerHTML = message.contentType === "text/djot" ? renderHTML(parse(source)) : source;
        template.content.querySelectorAll("script, style, template, iframe, object").forEach(node => node.remove());
        template.content.querySelectorAll("img").forEach(image =>
            image.replaceWith(document.createTextNode(image.alt))
        );
        template.content.querySelectorAll("br").forEach(node => node.replaceWith(document.createTextNode("\n")));
        template.content.querySelectorAll("p, div, li, tr, h1, h2, h3, h4, h5, h6")
            .forEach(node => node.appendChild(document.createTextNode("\n")));
        return template.content.textContent || "";
    } catch {
        return source;
    }
}

const COLLAPSED_INSETS_KEY = "moor-collapsed-insets";

interface OutputWindowProps {
    transcript: Transcript;
    onLoadMoreHistory?: () => void;
    isLoadingHistory?: boolean;
    onLinkClick?: (
        url: string,
        position?: { x: number; y: number },
        metadata?: { actorName?: string; verb?: string },
    ) => void;
    fontSize?: number;
    playerOid?: string | null;
    currentRoomLookKey?: string | null;
    onActiveRoomLookVisibilityChange?: (
        roomKey: string | null,
        isVisible: boolean,
        lookMessageId?: string | null,
    ) => void;
}

export const OutputWindow: React.FC<OutputWindowProps> = ({
    transcript,
    onLoadMoreHistory,
    isLoadingHistory = false,
    onLinkClick,
    fontSize,
    playerOid: _playerOid,
    currentRoomLookKey,
    onActiveRoomLookVisibilityChange,
}) => {
    const {
        outputRef,
        version,
        visibleGroups,
        start,
        end,
        handleScroll,
        jumpToNow,
        older,
        newer,
        hasOlder,
        hasNewer,
        isViewingHistory,
    } = useTranscriptWindow(transcript, onLoadMoreHistory, isLoadingHistory);
    const staleMessageIds = transcript.stale;
    const latestCurrentRoomLookMessageId = currentRoomLookKey ? transcript.latestRoomLook(currentRoomLookKey) : null;
    const announcedRevision = useRef(transcript.liveRevision);
    const announcedGeneration = useRef(transcript.generation);
    const [announcements, setAnnouncements] = useState<{ id: string; text: string }[]>([]);
    const [omittedAnnouncements, setOmittedAnnouncements] = useState(0);
    useLayoutEffect(() => {
        if (announcedGeneration.current !== transcript.generation) {
            announcedGeneration.current = transcript.generation;
            announcedRevision.current = 0;
            setAnnouncements([]);
            setOmittedAnnouncements(0);
        }
        const revision = transcript.liveRevision;
        if (revision === announcedRevision.current) return;
        const messages = transcript.announcementsAfter(announcedRevision.current);
        setOmittedAnnouncements(Math.max(0, revision - announcedRevision.current - messages.length));
        setAnnouncements(messages.map(message => ({ id: message.id, text: announcementText(message) })));
        announcedRevision.current = revision;
    }, [transcript, version]);

    // Track collapsed insets by their first message ID.
    const [collapsedInsets, setCollapsedInsets] = useState<Set<string>>(() => {
        if (typeof window === "undefined") return new Set();
        try {
            const stored = sessionStorage.getItem(COLLAPSED_INSETS_KEY);
            return stored ? new Set(JSON.parse(stored)) : new Set();
        } catch {
            return new Set();
        }
    });

    // Toggle the existing inset collapse control.
    const toggleInsetCollapse = useCallback((messageId: string) => {
        setCollapsedInsets(prev => {
            const next = new Set(prev);
            if (next.has(messageId)) {
                next.delete(messageId);
            } else {
                next.add(messageId);
            }
            // Persist to session storage
            try {
                sessionStorage.setItem(COLLAPSED_INSETS_KEY, JSON.stringify([...next]));
            } catch {
                // Ignore storage errors
            }
            return next;
        });
    }, []);

    // Retain event context for external navigation.
    const createLinkClickHandler = useCallback((_messageId: string, eventMetadata?: EventMetadata) => {
        return (url: string, position?: { x: number; y: number }) => {
            return onLinkClick?.(url, position, {
                actorName: eventMetadata?.actorName,
                verb: eventMetadata?.verb,
            });
        };
    }, [onLinkClick]);

    // Render content with optional TTS text for screen readers
    const renderContentWithTts = useCallback((
        content: string | string[],
        contentType: "text/plain" | "text/djot" | "text/html" | "text/traceback" | undefined,
        ttsText: string | undefined,
        thumbnail?: { contentType: string; data: string },
        linkPreview?: LinkPreview,
        messageId?: string,
        isStale?: boolean,
        enableEmojis?: boolean,
        eventMetadata?: EventMetadata,
    ) => {
        // Use a wrapped handler that marks the message stale, or fall back to direct handler
        const linkClickHandler = messageId ? createLinkClickHandler(messageId, eventMetadata) : onLinkClick;

        // Enable emoji only if server says to AND client setting is on
        const enableEmoji = enableEmojis === true && getEmojiEnabled();

        if (ttsText) {
            return (
                <>
                    {thumbnail && (
                        <img src={thumbnail.data} alt="" aria-hidden="true" className="narrative_thumbnail" />
                    )}
                    <span className="sr-only">{ttsText}</span>
                    <span aria-hidden="true">
                        <ContentRenderer
                            content={content}
                            contentType={contentType}
                            onLinkClick={linkClickHandler}
                            isStale={isStale}
                            enableEmoji={enableEmoji}
                            eventMetadata={eventMetadata}
                        />
                    </span>
                    {linkPreview && <LinkPreviewCard preview={linkPreview} metadata={eventMetadata} />}
                </>
            );
        }
        return (
            <>
                {thumbnail && <img src={thumbnail.data} alt="" aria-hidden="true" className="narrative_thumbnail" />}
                <ContentRenderer
                    content={content}
                    contentType={contentType}
                    onLinkClick={linkClickHandler}
                    isStale={isStale}
                    enableEmoji={enableEmoji}
                    eventMetadata={eventMetadata}
                />
                {linkPreview && <LinkPreviewCard preview={linkPreview} metadata={eventMetadata} />}
            </>
        );
    }, [onLinkClick, createLinkClickHandler]);

    const getMessageClassName = (type: string, isHistorical?: boolean) => {
        let baseClass = "";
        switch (type) {
            case "input_echo":
                baseClass = "input_echo";
                break;
            case "system":
                baseClass = "system_message_narrative";
                break;
            case "error":
                baseClass = "error_message_narrative";
                break;
            case "narrative":
            default:
                baseClass = "text_narrative";
                break;
        }

        // Add historical vs live class
        if (isHistorical) {
            baseClass += " historical_narrative";
        } else {
            baseClass += " live_narrative";
        }

        return baseClass;
    };

    // The producer opts an inset into collapsing and supplies its summary title.
    const getCollapseTitle = (
        presentationHint?: string,
        eventMetadata?: EventMetadata,
    ): string | undefined => {
        if (presentationHint !== "inset") return undefined;
        const title = eventMetadata?.collapseTitle;
        return typeof title === "string" && title.trim() ? title : undefined;
    };

    const encodeEventValue = useCallback((value: unknown): string | null => {
        if (value === null || value === undefined) {
            return null;
        }
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
            return String(value);
        }
        if (typeof value === "object") {
            const objectValue = value as { oid?: unknown; uuid?: unknown };
            if (objectValue.oid !== undefined && objectValue.oid !== null) {
                return `oid:${String(objectValue.oid)}`;
            }
            if (objectValue.uuid !== undefined && objectValue.uuid !== null) {
                return `uuid:${String(objectValue.uuid)}`;
            }
            try {
                return JSON.stringify(value);
            } catch {
                return String(value);
            }
        }
        return String(value);
    }, []);

    const getMessageDebugAttrs = useCallback((
        message: NarrativeMessage,
    ): Record<string, string> => {
        const attrs: Record<string, string> = {
            "data-message-id": message.id,
            "data-message-type": message.type,
        };
        if (message.eventId) {
            attrs["data-event-id"] = message.eventId;
        }
        if (message.presentationHint) {
            attrs["data-presentation-hint"] = message.presentationHint;
        }
        if (message.groupId) {
            attrs["data-group-id"] = message.groupId;
        }
        if (message.eventMetadata?.verb) {
            attrs["data-event-verb"] = message.eventMetadata.verb;
        }
        const dobj = encodeEventValue(message.eventMetadata?.dobj);
        if (dobj) {
            attrs["data-event-dobj"] = dobj;
        }
        const thisObj = encodeEventValue(message.eventMetadata?.thisObj);
        if (thisObj) {
            attrs["data-event-this-obj"] = thisObj;
        }
        const roomLookKey = getRoomLookKeyFromMessage(message);
        if (roomLookKey) {
            attrs["data-room-look-key"] = roomLookKey;
        }
        if (message.eventMetadata) {
            try {
                attrs["data-event-metadata"] = JSON.stringify(message.eventMetadata);
            } catch {
                // Best effort only for debugging.
            }
        }
        return attrs;
    }, [encodeEventValue]);

    useEffect(() => {
        if (!onActiveRoomLookVisibilityChange) {
            return;
        }
        const container = outputRef.current;
        if (!container) {
            onActiveRoomLookVisibilityChange(null, false, null);
            return;
        }
        if (!currentRoomLookKey) {
            onActiveRoomLookVisibilityChange(null, false, null);
            return;
        }
        if (!latestCurrentRoomLookMessageId) {
            onActiveRoomLookVisibilityChange(currentRoomLookKey, false, null);
            return;
        }

        const candidates = container.querySelectorAll<HTMLElement>("[data-room-look-key]");
        const matching = Array.from(candidates).filter(
            (candidate) =>
                candidate.dataset.roomLookKey === currentRoomLookKey
                && candidate.dataset.messageId === latestCurrentRoomLookMessageId,
        );
        if (matching.length === 0) {
            onActiveRoomLookVisibilityChange(currentRoomLookKey, false, null);
            return;
        }
        const target = matching.reduce((latest, candidate) => {
            if (!latest) {
                return candidate;
            }
            if (candidate.offsetTop > latest.offsetTop) {
                return candidate;
            }
            if (candidate.offsetTop === latest.offsetTop && candidate.offsetHeight >= latest.offsetHeight) {
                return candidate;
            }
            return latest;
        }, matching[0]);
        const roomLookKey = target.dataset.roomLookKey || currentRoomLookKey;
        if (!roomLookKey) {
            onActiveRoomLookVisibilityChange(null, false, null);
            return;
        }
        const lookMessageId = target.dataset.messageId || null;

        // Track all visibility checks against the narrative scroll container, not viewport geometry.
        const getInContainerView = () => {
            const rootRect = container.getBoundingClientRect();
            const targetRect = target.getBoundingClientRect();
            const epsilon = 1;
            return targetRect.top >= (rootRect.top - epsilon) && targetRect.top < (rootRect.bottom + epsilon);
        };

        const reportVisibility = (isVisible: boolean) => {
            onActiveRoomLookVisibilityChange(roomLookKey, isVisible, lookMessageId);
        };

        reportVisibility(getInContainerView());

        if (typeof IntersectionObserver === "undefined") {
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                const entry = entries[0];
                if (!entry || !entry.isIntersecting) {
                    reportVisibility(false);
                    return;
                }
                reportVisibility(getInContainerView());
            },
            {
                root: container,
                threshold: [0, 0.01],
            },
        );
        observer.observe(target);

        return () => {
            observer.disconnect();
        };
    }, [
        currentRoomLookKey,
        latestCurrentRoomLookMessageId,
        onActiveRoomLookVisibilityChange,
        start,
        end,
        version,
        outputRef,
    ]);

    const resolvedFontSize = fontSize ?? 14;

    return (
        <div
            ref={outputRef}
            id="output_window"
            className="output_window"
            role="log"
            aria-live="off"
            aria-atomic="false"
            aria-relevant="additions"
            onScroll={handleScroll}
            style={{
                paddingBottom: "1rem",
                overflowAnchor: "none",
                fontSize: `${resolvedFontSize}px`,
            }}
        >
            <div className="transcript_navigation" aria-label="Transcript navigation">
                <button
                    onClick={() => {
                        if (hasOlder && !isLoadingHistory) older();
                    }}
                    aria-disabled={!hasOlder || isLoadingHistory}
                >
                    Older messages
                </button>
                <button
                    onClick={() => {
                        if (hasNewer) newer();
                    }}
                    aria-disabled={!hasNewer}
                >
                    Newer messages
                </button>
                <button onClick={jumpToNow} aria-disabled={!isViewingHistory} aria-label="Return to latest messages">
                    Jump to Now
                </button>
                <span className="sr-only">
                    Browser Find and Select All cover the displayed messages. Export includes full history.
                </span>
                {isLoadingHistory && <span role="status">Loading more history...</span>}
            </div>
            <div className="sr-only" aria-live="polite" aria-relevant="additions" aria-atomic="false">
                {omittedAnnouncements > 0 && (
                    <span key={`omitted-${transcript.liveRevision}`}>
                        {omittedAnnouncements} additional new messages.
                    </span>
                )}
                {announcements.map(message => (
                    <div key={message.id}>
                        {message.text}
                    </div>
                ))}
            </div>
            {visibleGroups.map(indexedGroup => {
                const group = indexedGroup.messages;
                const renderGroup = () => {
                    const firstMessage = group[0];
                    const result = [];

                    if (group.length === 1 && !firstMessage.presentationHint) {
                        const message = firstMessage;
                        // Regular message without presentationHint
                        const isMessageStale = staleMessageIds?.has(message.id) || message.isHistorical;
                        result.push(
                            <span
                                key={message.id}
                                className={`${
                                    getMessageClassName(
                                        message.type,
                                        message.isHistorical,
                                    )
                                } message-block`}
                                {...getMessageDebugAttrs(message)}
                            >
                                {renderContentWithTts(
                                    message.content,
                                    message.contentType,
                                    message.ttsText,
                                    message.thumbnail,
                                    message.linkPreview,
                                    message.id,
                                    isMessageStale,
                                    message.eventMetadata?.enableEmojis,
                                    message.eventMetadata,
                                )}
                            </span>,
                        );
                        return result;
                    } else {
                        // Multiple messages grouped together

                        // Check if this group is for presentationHint or noNewline
                        const isHintGroup = firstMessage.presentationHint
                            && (group.length === 1 || !!firstMessage.groupId)
                            && group.every(msg =>
                                msg.presentationHint === firstMessage.presentationHint
                                && msg.groupId === firstMessage.groupId
                            );

                        if (isHintGroup) {
                            // Hint group - render each on its own line
                            const baseClassName = getMessageClassName(
                                firstMessage.type,
                                firstMessage.isHistorical,
                            );
                            const collapseTitle = getCollapseTitle(
                                firstMessage.presentationHint,
                                firstMessage.eventMetadata,
                            );
                            // Group is stale if any message in it is stale or historical
                            const isGroupStale = group.some(msg => staleMessageIds?.has(msg.id) || msg.isHistorical);

                            const collapseKey = indexedGroup.id;
                            const isCollapsible = collapseTitle !== undefined;
                            const isThisCollapsed = isCollapsible && collapsedInsets.has(collapseKey);

                            const wrapperClassName = (() => {
                                const classes: string[] = [];
                                if (firstMessage.presentationHint === "inset") classes.push("presentation_inset");
                                if (firstMessage.presentationHint === "marker") classes.push("presentation_marker");
                                if (firstMessage.presentationHint === "processing") {
                                    classes.push("presentation_processing");
                                }
                                if (firstMessage.presentationHint === "expired") {
                                    classes.push("presentation_expired");
                                }
                                return classes.join(" ");
                            })();

                            result.push(
                                <div
                                    key={`hint_${indexedGroup.id}`}
                                    className={wrapperClassName}
                                    {...getMessageDebugAttrs(firstMessage)}
                                >
                                    {isCollapsible && isThisCollapsed && (
                                        <>
                                            {/* Visual collapsed state - hidden from screen readers */}
                                            <div className="inset_collapsed_summary" aria-hidden="true">
                                                <button
                                                    type="button"
                                                    className="inset_toggle_button"
                                                    onClick={() => toggleInsetCollapse(collapseKey)}
                                                    tabIndex={-1}
                                                >
                                                    <span className="inset_chevron collapsed">▼</span>
                                                </button>
                                                <span className="inset_collapsed_name">
                                                    {collapseTitle}
                                                </span>
                                            </div>
                                            {/* Full content for screen readers when visually collapsed */}
                                            <div className="sr-only">
                                                {group.map(msg => (
                                                    <div
                                                        key={msg.id}
                                                        className={baseClassName}
                                                        data-transcript-message={msg.id}
                                                    >
                                                        {renderContentWithTts(
                                                            msg.content,
                                                            msg.contentType,
                                                            msg.ttsText,
                                                            msg.thumbnail,
                                                            msg.linkPreview,
                                                            msg.id,
                                                            isGroupStale,
                                                            msg.eventMetadata?.enableEmojis,
                                                            msg.eventMetadata,
                                                        )}
                                                    </div>
                                                ))}
                                            </div>
                                        </>
                                    )}
                                    {!isThisCollapsed && isCollapsible && (
                                        <div className="inset_toggle_row">
                                            {/* Toggle button hidden from screen readers */}
                                            <button
                                                type="button"
                                                className="inset_toggle_button"
                                                onClick={() => toggleInsetCollapse(collapseKey)}
                                                aria-hidden="true"
                                                tabIndex={-1}
                                            >
                                                <span className="inset_chevron">▼</span>
                                            </button>
                                            <div>
                                                {group.map(msg => (
                                                    <div
                                                        key={msg.id}
                                                        className={baseClassName}
                                                        data-transcript-message={msg.id}
                                                    >
                                                        {renderContentWithTts(
                                                            msg.content,
                                                            msg.contentType,
                                                            msg.ttsText,
                                                            msg.thumbnail,
                                                            msg.linkPreview,
                                                            msg.id,
                                                            isGroupStale,
                                                            msg.eventMetadata?.enableEmojis,
                                                            msg.eventMetadata,
                                                        )}
                                                    </div>
                                                ))}
                                            </div>
                                        </div>
                                    )}
                                    {!isThisCollapsed && !isCollapsible && (
                                        <>
                                            {group.map(msg => (
                                                <div
                                                    key={msg.id}
                                                    className={baseClassName}
                                                    data-transcript-message={msg.id}
                                                >
                                                    {renderContentWithTts(
                                                        msg.content,
                                                        msg.contentType,
                                                        msg.ttsText,
                                                        msg.thumbnail,
                                                        msg.linkPreview,
                                                        msg.id,
                                                        isGroupStale,
                                                        msg.eventMetadata?.enableEmojis,
                                                        msg.eventMetadata,
                                                    )}
                                                </div>
                                            ))}
                                        </>
                                    )}
                                </div>,
                            );
                        } else {
                            // noNewline group - combine content on same line
                            const combinedHtml = group.map(msg => {
                                const content = typeof msg.content === "string"
                                    ? msg.content
                                    : Array.isArray(msg.content)
                                    ? msg.content.join("")
                                    : "";

                                // If it's HTML, use as-is; if it's plain text, escape it
                                if (msg.contentType === "text/html") {
                                    return content;
                                } else {
                                    // Escape HTML characters for non-HTML content
                                    return content.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(
                                        />/g,
                                        "&gt;",
                                    );
                                }
                            }).join("");

                            // Combine ttsText from all messages in the group
                            const combinedTtsText = group
                                .filter(msg => msg.ttsText)
                                .map(msg => msg.ttsText)
                                .join(" ");

                            // Get linkPreview from the last message in the group (if any)
                            const lastLinkPreview = group.find(msg => msg.linkPreview)?.linkPreview;

                            // Group is stale if any message in it is stale or historical
                            const isGroupStale = group.some(msg => staleMessageIds?.has(msg.id) || msg.isHistorical);

                            result.push(
                                <div
                                    key={`noline_${indexedGroup.id}`}
                                    className={getMessageClassName(
                                        firstMessage.type,
                                        firstMessage.isHistorical,
                                    )}
                                    {...getMessageDebugAttrs(firstMessage)}
                                >
                                    {renderContentWithTts(
                                        combinedHtml,
                                        "text/html",
                                        combinedTtsText || undefined,
                                        undefined,
                                        lastLinkPreview,
                                        firstMessage.id,
                                        isGroupStale,
                                        firstMessage.eventMetadata?.enableEmojis,
                                        firstMessage.eventMetadata,
                                    )}
                                </div>,
                            );
                        }

                        return result;
                    }
                };
                return <div key={indexedGroup.id} data-transcript-group={indexedGroup.id}>{renderGroup()}</div>;
            })}
        </div>
    );
};
