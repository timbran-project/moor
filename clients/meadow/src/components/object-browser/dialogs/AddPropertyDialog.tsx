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
import { AddPropertyFormValues } from "../types";

interface AddPropertyDialogProps {
    objectLabel: string;
    defaultOwner: string;
    onCancel: () => void;
    onSubmit: (form: AddPropertyFormValues) => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const AddPropertyDialog: React.FC<AddPropertyDialogProps> = ({
    objectLabel,
    defaultOwner,
    onCancel,
    onSubmit,
    isSubmitting,
    errorMessage,
}) => {
    const [name, setName] = useState("");
    const [value, setValue] = useState("0");
    const [owner, setOwner] = useState(defaultOwner);
    const [perms, setPerms] = useState("r");

    useEffect(() => {
        setName("");
        setValue("0");
        setOwner(defaultOwner);
        setPerms("r");
    }, [defaultOwner]);

    const handleSubmit = (event: React.FormEvent) => {
        event.preventDefault();
        onSubmit({ name, value, owner, perms });
    };

    return (
        <DialogSheet title="Add Property" titleId="add-property-title" onCancel={onCancel}>
            <form onSubmit={handleSubmit} className="dialog-sheet-content form-stack">
                <p className="m-0 text-secondary">
                    Add a new property to <strong>{objectLabel}</strong>.
                </p>
                <label className="form-group">
                    <span className="form-group-label">Property name</span>
                    <input
                        type="text"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="prop_name"
                        autoFocus
                        required
                        className="form-input font-mono"
                    />
                </label>
                <label className="form-group">
                    <span className="form-group-label">Initial value (MOO expression)</span>
                    <input
                        type="text"
                        value={value}
                        onChange={(e) => setValue(e.target.value)}
                        placeholder="0"
                        required
                        className="form-input font-mono"
                    />
                    <span className="form-group-hint">
                        Examples: <code>0</code>, <code>""</code>, <code>{"{}"}</code>, <code>player</code>
                    </span>
                </label>
                <label className="form-group">
                    <span className="form-group-label">Owner (MOO expression)</span>
                    <input
                        type="text"
                        value={owner}
                        onChange={(e) => setOwner(e.target.value)}
                        placeholder="player"
                        className="form-input font-mono"
                    />
                </label>
                <div className="form-group">
                    <span className="form-group-label">Permissions</span>
                    <span className="form-group-hint">
                        r=read, w=write, c=chown
                    </span>
                    <div className="permission-checkboxes">
                        <label className="permission-checkbox-item">
                            <input
                                type="checkbox"
                                checked={perms.includes("r")}
                                onChange={(e) => {
                                    if (e.target.checked) {
                                        setPerms(perms + "r");
                                    } else {
                                        setPerms(perms.replace("r", ""));
                                    }
                                }}
                            />
                            <span className="permission-checkbox-label">r</span>
                        </label>
                        <label className="permission-checkbox-item">
                            <input
                                type="checkbox"
                                checked={perms.includes("w")}
                                onChange={(e) => {
                                    if (e.target.checked) {
                                        setPerms(perms + "w");
                                    } else {
                                        setPerms(perms.replace("w", ""));
                                    }
                                }}
                            />
                            <span className="permission-checkbox-label">w</span>
                        </label>
                        <label className="permission-checkbox-item">
                            <input
                                type="checkbox"
                                checked={perms.includes("c")}
                                onChange={(e) => {
                                    if (e.target.checked) {
                                        setPerms(perms + "c");
                                    } else {
                                        setPerms(perms.replace("c", ""));
                                    }
                                }}
                            />
                            <span className="permission-checkbox-label">c</span>
                        </label>
                    </div>
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
                        type="submit"
                        disabled={isSubmitting}
                        className="btn btn-primary"
                        style={{
                            opacity: isSubmitting ? 0.6 : 1,
                            cursor: isSubmitting ? "not-allowed" : "pointer",
                        }}
                    >
                        {isSubmitting ? "Adding…" : "Add Property"}
                    </button>
                </div>
            </form>
        </DialogSheet>
    );
};
