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
import { CreateChildFormValues } from "../types";

interface CreateChildDialogProps {
    defaultParent: string;
    defaultOwner: string;
    objectTypeOptions: Array<{ value: string; label: string }>;
    onCancel: () => void;
    onSubmit: (form: CreateChildFormValues) => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const CreateChildDialog: React.FC<CreateChildDialogProps> = ({
    defaultParent,
    defaultOwner,
    objectTypeOptions,
    onCancel,
    onSubmit,
    isSubmitting,
    errorMessage,
}) => {
    const [parent, setParent] = useState(defaultParent);
    const [owner, setOwner] = useState(defaultOwner);
    const [objectType, setObjectType] = useState<string>("server-default");
    const [initArgs, setInitArgs] = useState<string>("");
    const [name, setName] = useState<string>("");
    const [programmer, setProgrammer] = useState(false);
    const [wizard, setWizard] = useState(false);
    const [readable, setReadable] = useState(false);
    const [writable, setWritable] = useState(false);
    const [fertile, setFertile] = useState(false);

    useEffect(() => {
        setParent(defaultParent);
        setOwner(defaultOwner);
        setObjectType("server-default");
        setInitArgs("");
        setName("");
        setProgrammer(false);
        setWizard(false);
        setReadable(false);
        setWritable(false);
        setFertile(false);
    }, [defaultParent, defaultOwner]);

    const handleSubmit = (event: React.FormEvent) => {
        event.preventDefault();
        let flags = 0;
        if (programmer) flags |= 1 << 1;
        if (wizard) flags |= 1 << 2;
        if (readable) flags |= 1 << 4;
        if (writable) flags |= 1 << 5;
        if (fertile) flags |= 1 << 7;
        onSubmit({ parent, owner, objectType, initArgs, name, flags });
    };

    return (
        <DialogSheet title="Create Object" titleId="create-object-title" onCancel={onCancel}>
            <form onSubmit={handleSubmit} className="dialog-sheet-content form-stack">
                <label className="form-group">
                    <span className="form-group-label">Parent (MOO expression)</span>
                    <input
                        type="text"
                        value={parent}
                        onChange={(e) => setParent(e.target.value)}
                        placeholder="#-1"
                        autoFocus
                        className="form-input font-mono"
                    />
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
                <label className="form-group">
                    <span className="form-group-label">Object type</span>
                    <select
                        value={objectType}
                        onChange={(e) => setObjectType(e.target.value)}
                        className="form-input font-mono"
                    >
                        {objectTypeOptions.map((option) => (
                            <option key={option.value} value={option.value}>
                                {option.label}
                            </option>
                        ))}
                    </select>
                </label>
                <label className="form-group">
                    <span className="form-group-label">Initialization arguments</span>
                    <textarea
                        value={initArgs}
                        onChange={(e) => setInitArgs(e.target.value)}
                        placeholder="{}"
                        rows={3}
                        className="form-input font-mono"
                    />
                    <span className="form-group-hint">
                        Provide a MOO list literal (for example <code>{"{}"}</code> or{" "}
                        <code>{"{"}player{"}"}</code>). These arguments are passed to the object's{" "}
                        <code>:initialize</code> verb if it has one. Leave blank to skip initialization.
                    </span>
                </label>
                <label className="form-group">
                    <span className="form-group-label">Name (optional)</span>
                    <input
                        type="text"
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="Unnamed Object"
                        className="form-input font-mono"
                    />
                </label>
                <div className="form-group">
                    <span className="form-group-label">Flags</span>
                    <div className="permission-flags">
                        <label className="permission-flag-item">
                            <input
                                type="checkbox"
                                checked={programmer}
                                onChange={(e) => setProgrammer(e.target.checked)}
                            />
                            <span className="permission-flag-icon">p</span>
                            <span className="permission-flag-text">Programmer</span>
                        </label>
                        <label className="permission-flag-item">
                            <input
                                type="checkbox"
                                checked={wizard}
                                onChange={(e) => setWizard(e.target.checked)}
                            />
                            <span className="permission-flag-icon">w</span>
                            <span className="permission-flag-text">Wizard</span>
                        </label>
                        <label className="permission-flag-item">
                            <input
                                type="checkbox"
                                checked={readable}
                                onChange={(e) => setReadable(e.target.checked)}
                            />
                            <span className="permission-flag-icon">r</span>
                            <span className="permission-flag-text">Readable</span>
                        </label>
                        <label className="permission-flag-item">
                            <input
                                type="checkbox"
                                checked={writable}
                                onChange={(e) => setWritable(e.target.checked)}
                            />
                            <span className="permission-flag-icon">W</span>
                            <span className="permission-flag-text">Writable</span>
                        </label>
                        <label className="permission-flag-item">
                            <input
                                type="checkbox"
                                checked={fertile}
                                onChange={(e) => setFertile(e.target.checked)}
                            />
                            <span className="permission-flag-icon">f</span>
                            <span className="permission-flag-text">Fertile</span>
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
                        {isSubmitting ? "Creating…" : "Create"}
                    </button>
                </div>
            </form>
        </DialogSheet>
    );
};
