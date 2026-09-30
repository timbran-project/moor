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

import { Component, type ErrorInfo, type ReactNode, useEffect, useRef } from "react";
import { type RecoveryScope, reportUiFailure } from "../lib/ui-failure";

interface ErrorBoundaryProps {
    scope: RecoveryScope;
    surface?: string;
    children: ReactNode;
    fallback?: (retry: () => void) => ReactNode;
}

function RecoveryNotice({ scope, retry }: { scope: RecoveryScope; retry: () => void }) {
    const notice = useRef<HTMLElement>(null);
    useEffect(() => {
        notice.current?.focus({ preventScroll: true });
    }, []);
    const application = scope === "application";
    const transcript = scope === "transcript";
    return (
        <section ref={notice} className="recovery_notice" role="alert" tabIndex={-1}>
            <h2>
                {application
                    ? "Meadow could not continue"
                    : transcript
                    ? "The transcript could not be displayed"
                    : "The interface stopped working"}
            </h2>
            <p>
                {application
                    ? "Reload to restart Meadow and reconnect. Unsaved edits and the displayed transcript will be lost. Saved sign-in and encryption settings will be kept."
                    : transcript
                    ? "You can retry displaying the loaded messages. Command input is still available."
                    : "Retry the interface without signing out. Unsaved edits and the displayed transcript will reset. New messages received while this notice is open will be shown after retrying."}
            </p>
            <button
                type="button"
                className="btn btn-primary"
                onClick={application
                    ? () => window.location.reload()
                    : retry}
            >
                {application ? "Reload Meadow" : transcript ? "Retry transcript" : "Retry interface"}
            </button>
        </section>
    );
}

/** Contains render/lifecycle failures without clearing credentials or resetting providers above the boundary. */
export class ErrorBoundary extends Component<ErrorBoundaryProps, { failed: boolean }> {
    state = { failed: false };

    static getDerivedStateFromError() {
        return { failed: true };
    }

    componentDidCatch(error: unknown, info: ErrorInfo) {
        reportUiFailure(this.props.scope, error, info.componentStack, this.props.surface);
    }

    private retry = () => this.setState({ failed: false });

    render() {
        if (!this.state.failed) return this.props.children;
        if (this.props.fallback) return this.props.fallback(this.retry);
        return <RecoveryNotice scope={this.props.scope} retry={this.retry} />;
    }
}
