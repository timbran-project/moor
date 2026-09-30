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

import { useState } from "react";
import { ExternalLinkMetadata, useExternalNavigation } from "../context/ExternalNavigationContext";
import { parseHttpUrl } from "../lib/url-policy";

export interface LinkPreview {
    url: string;
    title?: string;
    description?: string;
    image?: string;
    site_name?: string;
}

interface LinkPreviewCardProps {
    preview: LinkPreview;
    metadata?: ExternalLinkMetadata;
}

function PreviewImage({ image }: { image: URL }) {
    const [loaded, setLoaded] = useState(false);
    if (!loaded) {
        return (
            <button type="button" className="link-preview-load-image" onClick={() => setLoaded(true)}>
                Load image from {image.hostname}
            </button>
        );
    }
    return (
        <div className="link-preview-image" aria-hidden="true">
            <img src={image.href} alt="" loading="lazy" referrerPolicy="no-referrer" />
        </div>
    );
}

export function LinkPreviewCard({ preview, metadata }: LinkPreviewCardProps) {
    const { openExternalLink } = useExternalNavigation();
    const { url, title, description, image, site_name } = preview;
    const target = parseHttpUrl(url);
    if (!target) return null;

    const imageUrl = image ? parseHttpUrl(image) : null;
    const siteName = site_name || target.hostname;
    const accessibleLabel = `Open link preview: ${title || siteName} from ${target.hostname}`;

    return (
        <article className="link-preview-card" aria-label={`Link preview from ${target.hostname}`}>
            <button
                type="button"
                className="link-preview-link"
                onClick={() => openExternalLink(target.href, metadata)}
                aria-label={accessibleLabel}
            >
                <span className="link-preview-content">
                    <span className="link-preview-title">{title || url}</span>
                    {description && <span className="link-preview-description">{description}</span>}
                    <span className="link-preview-hostname">
                        {siteName === target.hostname ? siteName : `${siteName} · ${target.hostname}`}
                    </span>
                </span>
            </button>
            {imageUrl && (
                <PreviewImage
                    key={`${target.href}\n${imageUrl.href}`}
                    image={imageUrl}
                />
            )}
        </article>
    );
}
