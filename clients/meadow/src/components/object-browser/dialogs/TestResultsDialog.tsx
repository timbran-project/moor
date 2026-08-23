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

import React from "react";
import { DialogSheet } from "../../DialogSheet";
import { TestResult } from "../types";

interface TestResultsDialogProps {
    results: TestResult[];
    onClose: () => void;
}

export const TestResultsDialog: React.FC<TestResultsDialogProps> = ({
    results,
    onClose,
}) => {
    return (
        <DialogSheet
            title="Test Results"
            titleId="test-results-title"
            onCancel={onClose}
            maxWidth="800px"
        >
            <div className="dialog-sheet-content">
                <div style={{ maxHeight: "60vh", overflowY: "auto" }}>
                    <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "0.9em" }}>
                        <thead
                            style={{
                                position: "sticky",
                                top: 0,
                                backgroundColor: "var(--color-bg-secondary)",
                                zIndex: 1,
                            }}
                        >
                            <tr>
                                <th
                                    style={{
                                        textAlign: "left",
                                        padding: "8px",
                                        borderBottom: "2px solid var(--color-border-medium)",
                                    }}
                                >
                                    Status
                                </th>
                                <th
                                    style={{
                                        textAlign: "left",
                                        padding: "8px",
                                        borderBottom: "2px solid var(--color-border-medium)",
                                    }}
                                >
                                    Verb
                                </th>
                                <th
                                    style={{
                                        textAlign: "left",
                                        padding: "8px",
                                        borderBottom: "2px solid var(--color-border-medium)",
                                    }}
                                >
                                    Location
                                </th>
                                <th
                                    style={{
                                        textAlign: "left",
                                        padding: "8px",
                                        borderBottom: "2px solid var(--color-border-medium)",
                                    }}
                                >
                                    Result/Error
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {results.map((result, idx) => (
                                <tr key={idx} style={{ borderBottom: "1px solid var(--color-border-light)" }}>
                                    <td style={{ padding: "8px" }}>
                                        {result.success ? "✅" : "❌"}
                                    </td>
                                    <td style={{ padding: "8px", fontFamily: "var(--font-mono)" }}>
                                        {result.verb}
                                    </td>
                                    <td style={{ padding: "8px", fontFamily: "var(--font-mono)" }}>
                                        #{result.location}
                                    </td>
                                    <td
                                        style={{
                                            padding: "8px",
                                            fontFamily: "var(--font-mono)",
                                            whiteSpace: "pre-wrap",
                                        }}
                                    >
                                        {result.success
                                            ? result.result
                                            : <span style={{ color: "var(--color-text-error)" }}>{result.error}</span>}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
                <div className="button-group">
                    <button type="button" onClick={onClose} className="btn btn-primary">
                        Close
                    </button>
                </div>
            </div>
        </DialogSheet>
    );
};
