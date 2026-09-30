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

import React, { Component, lazy, ReactNode, Suspense, useState } from "react";

interface SurfaceProps {
    visible: boolean;
    onClose: () => void;
    splitMode?: boolean;
}

function SurfaceStatus(
    { name, onClose, splitMode, retry, visible }: SurfaceProps & { name: string; retry?: () => void },
) {
    if (!visible) return null;
    return (
        <div
            style={splitMode ? { padding: "1rem" } : {
                position: "fixed",
                bottom: "1rem",
                right: "1rem",
                zIndex: 2000,
                padding: "1rem",
                background: "var(--color-bg-secondary)",
                border: "1px solid var(--color-border-primary)",
                borderRadius: "8px",
            }}
        >
            <p role="status">{retry ? `Could not open ${name}.` : `Loading ${name}…`}</p>
            {retry && <button type="button" className="btn btn-secondary" onClick={retry}>Retry</button>}
            <button type="button" className="btn btn-secondary" onClick={onClose}>Close</button>
        </div>
    );
}

class SurfaceBoundary extends Component<{ children: ReactNode; fallback: ReactNode }, { failed: boolean }> {
    state = { failed: false };
    static getDerivedStateFromError() {
        return { failed: true };
    }
    render() {
        return this.state.failed ? this.props.fallback : this.props.children;
    }
}

/** Keep a pending or failed editor import local to that surface, preserving the transcript. */
export function lazySurface<P extends SurfaceProps>(name: string, load: () => Promise<{ default: React.FC<P> }>) {
    const Initial = lazy(load);
    return function LazySurface(props: P) {
        const [{ Surface, attempt }, setAttempt] = useState({ Surface: Initial, attempt: 0 });
        const [opened, setOpened] = useState(props.visible);
        if (props.visible && !opened) setOpened(true);
        if (!props.visible && !opened) return null;
        const retry = () => setAttempt(previous => ({ Surface: lazy(load), attempt: previous.attempt + 1 }));
        return (
            <SurfaceBoundary key={attempt} fallback={<SurfaceStatus {...props} name={name} retry={retry} />}>
                <Suspense fallback={<SurfaceStatus {...props} name={name} />}>
                    <Surface key="surface" {...(props as React.PropsWithRef<P>)} />
                </Suspense>
            </SurfaceBoundary>
        );
    };
}
