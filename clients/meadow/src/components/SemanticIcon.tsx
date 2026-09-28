// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

import { semanticIconMarkup } from "../lib/semantic-icons";

/** Decorative icons accompany a visible label or an explicitly named control. */
export function SemanticIcon({ kind }: { kind?: string }) {
    const markup = semanticIconMarkup(kind);
    return markup
        ? <span className="semantic-icon-wrap" aria-hidden="true" dangerouslySetInnerHTML={{ __html: markup }} />
        : null;
}
