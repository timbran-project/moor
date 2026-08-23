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

import type { EventMetadata, LinkPreview } from "../lib/rpc-fb";

/**
 * A narrative message buffered before the transcript surface is mounted.
 */
export interface NarrativeMessageContent {
    content: string | string[];
    contentType?: string;
    noNewline?: boolean;
    presentationHint?: string;
    groupId?: string;
    ttsText?: string;
    thumbnail?: { contentType: string; data: string };
    linkPreview?: LinkPreview;
    eventMetadata?: EventMetadata;
    rewritable?: { id: string; owner: string; ttl: number; fallback?: string };
    rewriteTarget?: string;
    eventTimestampMs?: number;
}
