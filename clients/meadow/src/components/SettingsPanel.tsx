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

// ! Settings panel with theme toggle and other options

import React, { useEffect, useRef, useState } from "react";
import { CommandEchoToggle } from "./CommandEchoToggle";
import { EmojiToggle } from "./EmojiToggle";
import { FontSizeControl } from "./FontSizeControl";
import { FontToggle } from "./FontToggle";
import { SayModeToggle } from "./SayModeToggle";
import { ThemeToggle } from "./ThemeToggle";
import { useToast } from "./Toast";
import { VerbPaletteToggle } from "./VerbPaletteToggle";

interface ServerVersion {
    version: string;
    commit: string;
}

interface SettingsPanelProps {
    isOpen: boolean;
    onClose: () => void;
    narrativeFontSize: number;
    onDecreaseNarrativeFontSize: () => void;
    onIncreaseNarrativeFontSize: () => void;
    roomHudEnabled: boolean;
    onToggleRoomHud: () => void;
}

export const SettingsPanel: React.FC<SettingsPanelProps> = ({
    isOpen,
    onClose,
    narrativeFontSize,
    onDecreaseNarrativeFontSize,
    onIncreaseNarrativeFontSize,
    roomHudEnabled,
    onToggleRoomHud,
}) => {
    const closeButtonRef = useRef<HTMLButtonElement>(null);
    const panelRef = useRef<HTMLDivElement>(null);
    const previousActiveElementRef = useRef<HTMLElement | null>(null);
    const [copyAnnouncement, setCopyAnnouncement] = useState("");
    const [serverVersion, setServerVersion] = useState<ServerVersion | null>(null);
    const { showToast } = useToast();

    // Fetch server version on mount
    useEffect(() => {
        fetch("/version")
            .then((res) => (res.ok ? res.json() : null))
            .then((data) => setServerVersion(data))
            .catch(() => setServerVersion(null));
    }, []);

    // Store the previously focused element and focus the close button when opened
    useEffect(() => {
        if (isOpen) {
            previousActiveElementRef.current = document.activeElement as HTMLElement;
            // Small delay to ensure the panel is rendered
            requestAnimationFrame(() => {
                closeButtonRef.current?.focus();
            });
        }
    }, [isOpen]);

    // Return focus to the previous element when closed
    useEffect(() => {
        if (!isOpen && previousActiveElementRef.current) {
            previousActiveElementRef.current.focus();
            previousActiveElementRef.current = null;
        }
    }, [isOpen]);

    // Handle Escape key to close
    useEffect(() => {
        if (!isOpen) return;

        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === "Escape") {
                e.preventDefault();
                e.stopPropagation();
                onClose();
            }
        };

        document.addEventListener("keydown", handleKeyDown);
        return () => document.removeEventListener("keydown", handleKeyDown);
    }, [isOpen, onClose]);

    // Trap focus within the dialog
    useEffect(() => {
        if (!isOpen) return;

        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key !== "Tab" || !panelRef.current) return;

            const focusableElements = panelRef.current.querySelectorAll<HTMLElement>(
                "button, [href], input, select, textarea, [tabindex]:not([tabindex=\"-1\"])",
            );
            const firstElement = focusableElements[0];
            const lastElement = focusableElements[focusableElements.length - 1];

            if (e.shiftKey && document.activeElement === firstElement) {
                e.preventDefault();
                lastElement?.focus();
            } else if (!e.shiftKey && document.activeElement === lastElement) {
                e.preventDefault();
                firstElement?.focus();
            }
        };

        document.addEventListener("keydown", handleKeyDown);
        return () => document.removeEventListener("keydown", handleKeyDown);
    }, [isOpen]);

    const handleCopyVersion = async () => {
        const versionText = serverVersion
            ? `Client: ${__GIT_HASH__}\nServer: ${serverVersion.commit}`
            : `Client: ${__GIT_HASH__}`;
        try {
            if (navigator.clipboard && window.isSecureContext) {
                await navigator.clipboard.writeText(versionText);
                setCopyAnnouncement("Version info copied to clipboard");
                showToast("Copied to clipboard");
            } else {
                // Fallback for non-secure contexts or missing clipboard API
                const textArea = document.createElement("textarea");
                textArea.value = versionText;
                textArea.style.position = "fixed";
                textArea.style.left = "-9999px";
                textArea.style.top = "0";
                document.body.appendChild(textArea);
                textArea.focus();
                textArea.select();
                const successful = document.execCommand("copy");
                document.body.removeChild(textArea);
                if (successful) {
                    setCopyAnnouncement("Version info copied to clipboard");
                    showToast("Copied to clipboard");
                } else {
                    setCopyAnnouncement("Failed to copy version info");
                }
            }
        } catch (err) {
            console.error("Failed to copy:", err);
            setCopyAnnouncement("Failed to copy version info");
        } finally {
            // Clear announcement after it's been read
            setTimeout(() => setCopyAnnouncement(""), 2000);
        }
    };

    if (!isOpen) return null;

    return (
        <>
            {/* Backdrop */}
            <div
                className="settings-backdrop"
                onClick={onClose}
                aria-hidden="true"
            />

            {/* Settings panel - proper dialog */}
            <div
                ref={panelRef}
                className="settings-panel"
                role="dialog"
                aria-modal="true"
                aria-labelledby="settings-dialog-title"
            >
                <div className="settings-header">
                    <h2 id="settings-dialog-title">Settings</h2>
                    <button
                        ref={closeButtonRef}
                        type="button"
                        className="settings-close"
                        onClick={onClose}
                        aria-label="Close settings"
                    >
                        ×
                    </button>
                </div>

                <div className="settings-content">
                    <div className="settings-section">
                        <h3>Display</h3>
                        <ThemeToggle />
                        <FontToggle />
                        <div className="settings-item">
                            <span>Font size</span>
                            <FontSizeControl
                                fontSize={narrativeFontSize}
                                onDecrease={onDecreaseNarrativeFontSize}
                                onIncrease={onIncreaseNarrativeFontSize}
                            />
                        </div>
                        <EmojiToggle />
                    </div>

                    <div className="settings-section">
                        <h3>Interface</h3>
                        <CommandEchoToggle />
                        <SayModeToggle />
                        <VerbPaletteToggle />
                        <div className="settings-item">
                            <span>Room HUD</span>
                            <button
                                type="button"
                                className="settings-value-button"
                                onClick={onToggleRoomHud}
                                role="switch"
                                aria-checked={roomHudEnabled}
                                aria-label={`Room HUD ${roomHudEnabled ? "enabled" : "disabled"}`}
                                aria-describedby="room-hud-description"
                                title="Show a docked room summary panel at the top when room look is out of view"
                            >
                                {roomHudEnabled ? "✓ On" : "Off"}
                            </button>
                            <span id="room-hud-description" className="sr-only">
                                Shows a room summary panel at the top when your latest room look scrolls out of view.
                            </span>
                        </div>
                    </div>

                    <div className="settings-section">
                        <h3>About</h3>
                        <div className="settings-item">
                            <span>Client</span>
                            <button
                                type="button"
                                className="version-copy-button"
                                onClick={handleCopyVersion}
                                aria-label={`Client version ${__GIT_HASH__}. Click to copy version info`}
                            >
                                {__GIT_HASH__}
                            </button>
                        </div>
                        <div className="settings-item">
                            <span>Server</span>
                            <button
                                type="button"
                                className="version-copy-button"
                                onClick={handleCopyVersion}
                                aria-label={`Server version ${
                                    serverVersion?.commit ?? "unknown"
                                }. Click to copy version info`}
                            >
                                {serverVersion?.commit ?? "..."}
                            </button>
                        </div>
                    </div>
                </div>

                {/* Accessible announcement for copy action */}
                <div
                    role="status"
                    aria-live="polite"
                    aria-atomic="true"
                    className="sr-only"
                >
                    {copyAnnouncement}
                </div>
            </div>
        </>
    );
};
