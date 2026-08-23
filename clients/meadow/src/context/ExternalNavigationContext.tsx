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

import React, { createContext, useCallback, useContext, useMemo, useState } from "react";
import { ExternalLinkModal } from "../components/ExternalLinkModal";
import { addTrustedDomain, getHostname, isDomainTrusted } from "../lib/trusted-domains";

export interface ExternalLinkMetadata {
    actorName?: string;
    verb?: string;
}

interface PendingExternalLink {
    url: string;
    actorName?: string;
    verb?: string;
}

interface ExternalNavigationContextType {
    /**
     * Opens an external URL directly when its domain is trusted; otherwise
     * presents the confirmation modal and remembers the trust decision.
     */
    openExternalLink: (url: string, metadata?: ExternalLinkMetadata) => void;
}

const ExternalNavigationContext = createContext<ExternalNavigationContextType | undefined>(undefined);

/**
 * Owns the external-URL trust policy and the confirmation UI. All off-server
 * navigation must flow through `openExternalLink` so it cannot bypass the
 * trusted-domain gate.
 */
export const ExternalNavigationProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [pendingLink, setPendingLink] = useState<PendingExternalLink | null>(null);

    const openExternalLink = useCallback((url: string, metadata?: ExternalLinkMetadata) => {
        if (isDomainTrusted(url)) {
            window.open(url, "_blank", "noopener,noreferrer");
            return;
        }
        setPendingLink({
            url,
            actorName: metadata?.actorName,
            verb: metadata?.verb,
        });
    }, []);

    const handleConfirm = useCallback((trustDomain: boolean) => {
        if (!pendingLink) {
            return;
        }

        if (trustDomain) {
            const hostname = getHostname(pendingLink.url);
            if (hostname) {
                addTrustedDomain(hostname);
            }
        }

        window.open(pendingLink.url, "_blank", "noopener,noreferrer");
        setPendingLink(null);
    }, [pendingLink]);

    const handleCancel = useCallback(() => {
        setPendingLink(null);
    }, []);

    const value = useMemo(() => ({ openExternalLink }), [openExternalLink]);

    return (
        <ExternalNavigationContext.Provider value={value}>
            {children}
            {pendingLink && (
                <ExternalLinkModal
                    url={pendingLink.url}
                    actorName={pendingLink.actorName}
                    verb={pendingLink.verb}
                    onConfirm={handleConfirm}
                    onCancel={handleCancel}
                />
            )}
        </ExternalNavigationContext.Provider>
    );
};

export const useExternalNavigation = (): ExternalNavigationContextType => {
    const context = useContext(ExternalNavigationContext);
    if (context === undefined) {
        throw new Error("useExternalNavigation must be used within an ExternalNavigationProvider");
    }
    return context;
};
