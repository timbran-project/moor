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

interface DeletePropertyDialogProps {
    propertyName: string;
    objectLabel: string;
    onCancel: () => void;
    onConfirm: () => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const DeletePropertyDialog: React.FC<DeletePropertyDialogProps> = ({
    propertyName,
    objectLabel,
    onCancel,
    onConfirm,
    isSubmitting,
    errorMessage,
}) => {
    return (
        <DialogSheet
            title="Delete Property?"
            titleId="delete-property-title"
            maxWidth="480px"
            role="alertdialog"
            onCancel={onCancel}
        >
            <div className="dialog-sheet-content form-stack">
                <div
                    style={{
                        padding: "0.75em",
                        borderRadius: "var(--radius-sm)",
                        border: "1px solid var(--color-text-error)",
                        backgroundColor: "color-mix(in srgb, var(--color-text-error) 15%, transparent)",
                        color: "var(--color-text-primary)",
                        fontFamily: "inherit",
                    }}
                >
                    <p className="m-0">
                        Delete property <code>{propertyName}</code> from{" "}
                        <strong>{objectLabel}</strong>? This action cannot be undone.
                    </p>
                </div>
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
                        type="button"
                        onClick={onConfirm}
                        disabled={isSubmitting}
                        className="btn btn-danger"
                        style={{
                            opacity: isSubmitting ? 0.6 : 1,
                            cursor: isSubmitting ? "not-allowed" : "pointer",
                        }}
                    >
                        {isSubmitting ? "Deleting…" : "Delete Property"}
                    </button>
                </div>
            </div>
        </DialogSheet>
    );
};
