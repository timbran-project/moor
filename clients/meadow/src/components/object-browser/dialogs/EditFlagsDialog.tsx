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

import React, { useEffect, useState } from "react";
import { DialogSheet } from "../../DialogSheet";

interface EditFlagsDialogProps {
    objectLabel: string;
    currentFlags: number;
    onCancel: () => void;
    onSubmit: (flags: number) => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const EditFlagsDialog: React.FC<EditFlagsDialogProps> = ({
    objectLabel,
    currentFlags,
    onCancel,
    onSubmit,
    isSubmitting,
    errorMessage,
}) => {
    const [user, setUser] = useState((currentFlags & (1 << 0)) !== 0);
    const [programmer, setProgrammer] = useState((currentFlags & (1 << 1)) !== 0);
    const [wizard, setWizard] = useState((currentFlags & (1 << 2)) !== 0);
    const [readable, setReadable] = useState((currentFlags & (1 << 4)) !== 0);
    const [writable, setWritable] = useState((currentFlags & (1 << 5)) !== 0);
    const [fertile, setFertile] = useState((currentFlags & (1 << 7)) !== 0);

    useEffect(() => {
        setUser((currentFlags & (1 << 0)) !== 0);
        setProgrammer((currentFlags & (1 << 1)) !== 0);
        setWizard((currentFlags & (1 << 2)) !== 0);
        setReadable((currentFlags & (1 << 4)) !== 0);
        setWritable((currentFlags & (1 << 5)) !== 0);
        setFertile((currentFlags & (1 << 7)) !== 0);
    }, [currentFlags]);

    const handleSubmit = (event: React.FormEvent) => {
        event.preventDefault();
        let flags = 0;
        if (user) flags |= 1 << 0;
        if (programmer) flags |= 1 << 1;
        if (wizard) flags |= 1 << 2;
        if (readable) flags |= 1 << 4;
        if (writable) flags |= 1 << 5;
        if (fertile) flags |= 1 << 7;
        onSubmit(flags);
    };

    const renderCheckbox = (
        label: string,
        description: string,
        checked: boolean,
        onChange: (checked: boolean) => void,
        flagChar: string,
    ) => (
        <div className="flag-checkbox-item">
            <input
                type="checkbox"
                checked={checked}
                onChange={(e) => onChange(e.target.checked)}
                disabled={isSubmitting}
                className="flag-checkbox-input"
            />
            <div className="flag-checkbox-content">
                <div className="flag-checkbox-header">
                    <strong className="flag-checkbox-label">{label}</strong>
                    <code className="flag-char">{flagChar}</code>
                </div>
                <div className="flag-checkbox-description">{description}</div>
            </div>
        </div>
    );

    return (
        <DialogSheet title="Edit Object Flags" titleId="edit-flags-title" onCancel={onCancel}>
            <form onSubmit={handleSubmit} className="dialog-sheet-content form-stack">
                <p className="m-0 text-secondary">
                    Editing flags for <strong>{objectLabel}</strong>
                </p>

                {renderCheckbox(
                    "Player",
                    "Object is a player/user object",
                    user,
                    setUser,
                    "u",
                )}

                {renderCheckbox(
                    "Programmer",
                    "Object has programmer rights",
                    programmer,
                    setProgrammer,
                    "p",
                )}

                {renderCheckbox(
                    "Wizard",
                    "Object has wizard rights",
                    wizard,
                    setWizard,
                    "w",
                )}

                {renderCheckbox(
                    "Readable",
                    "Object is publicly readable",
                    readable,
                    setReadable,
                    "r",
                )}

                {renderCheckbox(
                    "Writable",
                    "Object is publicly writable",
                    writable,
                    setWritable,
                    "W",
                )}

                {renderCheckbox(
                    "Fertile",
                    "Object can be used as a parent for new objects",
                    fertile,
                    setFertile,
                    "f",
                )}

                {errorMessage && (
                    <div className="dialog-error">
                        {errorMessage}
                    </div>
                )}

                <div className="button-group" style={{ marginTop: "1em" }}>
                    <button
                        type="button"
                        onClick={onCancel}
                        disabled={isSubmitting}
                        className="btn btn-secondary"
                        style={{
                            opacity: isSubmitting ? 0.6 : 1,
                            cursor: isSubmitting ? "not-allowed" : "pointer",
                        }}
                    >
                        Cancel
                    </button>
                    <button
                        type="submit"
                        disabled={isSubmitting}
                        className="btn btn-primary"
                        style={{
                            opacity: isSubmitting ? 0.6 : 1,
                            cursor: isSubmitting ? "not-allowed" : "pointer",
                            fontWeight: 700,
                        }}
                    >
                        {isSubmitting ? "Saving…" : "Save Flags"}
                    </button>
                </div>
            </form>
        </DialogSheet>
    );
};
