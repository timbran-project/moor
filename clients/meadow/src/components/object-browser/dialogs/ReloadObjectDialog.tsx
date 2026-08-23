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

import React, { useState } from "react";
import { DialogSheet } from "../../DialogSheet";
import { ReloadObjectFormValues } from "../types";

interface ReloadObjectDialogProps {
    objectLabel: string;
    objectId: string;
    onCancel: () => void;
    onSubmit: (form: ReloadObjectFormValues) => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const ReloadObjectDialog: React.FC<ReloadObjectDialogProps> = ({
    objectLabel,
    objectId,
    onCancel,
    onSubmit,
    isSubmitting,
    errorMessage,
}) => {
    const [objdefFile, setObjdefFile] = useState<File | null>(null);
    const [constantsFile, setConstantsFile] = useState<File | null>(null);
    const [showConstants, setShowConstants] = useState(false);
    const [confirmation, setConfirmation] = useState("");

    const expectedConfirmation = `#${objectId}`;
    const canSubmit = objdefFile !== null && confirmation.trim() === expectedConfirmation;

    const handleSubmit = (event: React.FormEvent) => {
        event.preventDefault();
        if (!objdefFile) return;
        onSubmit({ objdefFile, constantsFile, confirmation });
    };

    return (
        <DialogSheet
            title="Reload Object From Objdef"
            titleId="reload-object-title"
            maxWidth="520px"
            role="alertdialog"
            onCancel={onCancel}
        >
            <form onSubmit={handleSubmit} className="dialog-sheet-content form-stack">
                <div
                    style={{
                        padding: "0.75em",
                        borderRadius: "var(--radius-sm)",
                        border: "1px solid var(--color-text-warning)",
                        backgroundColor: "color-mix(in srgb, var(--color-text-warning) 12%, transparent)",
                        color: "var(--color-text-primary)",
                        fontFamily: "inherit",
                        display: "grid",
                        gap: "0.5em",
                    }}
                >
                    <strong>Reloading replaces the current object.</strong>
                    <ul className="m-0" style={{ paddingLeft: "1.1em" }}>
                        <li>Properties and verbs not in the objdef will be deleted.</li>
                        <li>Flags, name, owner, parent, and location will be overwritten.</li>
                        <li>There is no undo for this action.</li>
                    </ul>
                </div>
                <p className="m-0 text-secondary">
                    Reload <strong>{objectLabel}</strong> from an objdef file.
                </p>
                <label className="form-group">
                    <span className="form-group-label">Objdef file (.moo)</span>
                    <input
                        type="file"
                        accept=".moo,text/plain"
                        onChange={(e) => setObjdefFile(e.target.files?.[0] ?? null)}
                        required
                        className="form-input"
                    />
                </label>
                <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => {
                        setShowConstants((prev) => {
                            if (prev) {
                                setConstantsFile(null);
                            }
                            return !prev;
                        });
                    }}
                    style={{ alignSelf: "flex-start" }}
                >
                    {showConstants ? "Hide constants file" : "Add constants file"}
                </button>
                {showConstants && (
                    <label className="form-group">
                        <span className="form-group-label">Constants file (constants.moo)</span>
                        <input
                            type="file"
                            accept=".moo,text/plain"
                            onChange={(e) => setConstantsFile(e.target.files?.[0] ?? null)}
                            className="form-input"
                        />
                    </label>
                )}
                <label className="form-group">
                    <span className="form-group-label">Type {expectedConfirmation} to confirm</span>
                    <input
                        type="text"
                        value={confirmation}
                        onChange={(e) => setConfirmation(e.target.value)}
                        placeholder={expectedConfirmation}
                        className="form-input font-mono"
                        required
                    />
                </label>
                {errorMessage && (
                    <div role="alert" className="dialog-error">
                        {errorMessage}
                    </div>
                )}
                <div className="button-group">
                    <button type="button" onClick={onCancel} className="btn btn-secondary">
                        Cancel
                    </button>
                    <button
                        type="submit"
                        disabled={!canSubmit || isSubmitting}
                        className="btn btn-danger"
                        style={{
                            opacity: !canSubmit || isSubmitting ? 0.6 : 1,
                            cursor: !canSubmit || isSubmitting ? "not-allowed" : "pointer",
                        }}
                    >
                        {isSubmitting ? "Reloading…" : "Reload"}
                    </button>
                </div>
            </form>
        </DialogSheet>
    );
};
