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
import { AddVerbFormValues } from "../types";

interface AddVerbDialogProps {
    objectLabel: string;
    defaultOwner: string;
    onCancel: () => void;
    onSubmit: (form: AddVerbFormValues) => void;
    isSubmitting: boolean;
    errorMessage: string | null;
}

export const AddVerbDialog: React.FC<AddVerbDialogProps> = ({
    objectLabel,
    defaultOwner,
    onCancel,
    onSubmit,
    isSubmitting,
    errorMessage,
}) => {
    const [verbType, setVerbType] = useState<"method" | "command">("method");
    const [names, setNames] = useState("");
    const [owner, setOwner] = useState(defaultOwner);
    const [perms, setPerms] = useState("rxd");
    const [dobj, setDobj] = useState("this");
    const [prep, setPrep] = useState("none");
    const [iobj, setIobj] = useState("this");

    useEffect(() => {
        setNames("");
        setOwner(defaultOwner);
        setVerbType("method");
        setPerms("rxd");
        setDobj("this");
        setPrep("none");
        setIobj("this");
    }, [defaultOwner]);

    // Update argspec and perms when verb type changes
    const handleVerbTypeChange = (type: "method" | "command") => {
        setVerbType(type);
        if (type === "method") {
            setPerms("rxd");
            setDobj("this");
            setPrep("none");
            setIobj("this");
        } else {
            setPerms("rd");
            setDobj("this");
            setPrep("none");
            setIobj("none");
        }
    };

    const handleSubmit = (event: React.FormEvent) => {
        event.preventDefault();
        onSubmit({ names, owner, perms, dobj, prep, iobj });
    };

    return (
        <DialogSheet title="Add Verb" titleId="add-verb-title" onCancel={onCancel}>
            <form onSubmit={handleSubmit} className="dialog-sheet-content form-stack">
                <p className="m-0 text-secondary">
                    Add a new verb to <strong>{objectLabel}</strong>.
                </p>
                <div className="form-group">
                    <span className="form-group-label">Verb type</span>
                    <div className="verb-type-selector">
                        <label className="verb-type-option">
                            <input
                                type="radio"
                                name="verbType"
                                checked={verbType === "method"}
                                onChange={() => handleVerbTypeChange("method")}
                            />
                            <div className="verb-type-description">
                                <span className="verb-type-title">Method</span>
                                <span className="verb-type-subtitle">
                                    Called from code (<code>this none this</code>, with <code>x</code>)
                                </span>
                            </div>
                        </label>
                        <label className="verb-type-option">
                            <input
                                type="radio"
                                name="verbType"
                                checked={verbType === "command"}
                                onChange={() => handleVerbTypeChange("command")}
                            />
                            <div className="verb-type-description">
                                <span className="verb-type-title">Command</span>
                                <span className="verb-type-subtitle">
                                    Player command (e.g. <code>this none none</code>, no <code>x</code>)
                                </span>
                            </div>
                        </label>
                    </div>
                </div>
                <label className="form-group">
                    <span className="form-group-label">Verb names (space-separated)</span>
                    <input
                        type="text"
                        value={names}
                        onChange={(e) => setNames(e.target.value)}
                        placeholder="get take grab"
                        autoFocus
                        required
                        className="form-input font-mono"
                    />
                    <span className="form-group-hint">
                        Example: <code>get take grab</code> creates aliases for the same verb
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
                        r=read, w=write, x=exec, d=raise errors (usually keep on)
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
                                checked={perms.includes("x")}
                                onChange={(e) => {
                                    if (e.target.checked) {
                                        setPerms(perms + "x");
                                    } else {
                                        setPerms(perms.replace("x", ""));
                                    }
                                }}
                            />
                            <span className="permission-checkbox-label">x</span>
                        </label>
                        <label className="permission-checkbox-item">
                            <input
                                type="checkbox"
                                checked={perms.includes("d")}
                                onChange={(e) => {
                                    if (e.target.checked) {
                                        setPerms(perms + "d");
                                    } else {
                                        setPerms(perms.replace("d", ""));
                                    }
                                }}
                            />
                            <span className="permission-checkbox-label">d</span>
                        </label>
                    </div>
                </div>
                <div className="form-group">
                    <span className="form-group-label">Verb argument specification</span>
                    <div className="verb-argspec-grid">
                        <label className="verb-argspec-column">
                            <span className="verb-argspec-label">dobj</span>
                            <select
                                value={dobj}
                                onChange={(e) => setDobj(e.target.value)}
                                className="verb-argspec-select"
                            >
                                <option value="none">none</option>
                                <option value="any">any</option>
                                <option value="this">this</option>
                            </select>
                        </label>
                        <label className="verb-argspec-column">
                            <span className="verb-argspec-label">prep</span>
                            <select
                                value={prep}
                                onChange={(e) => setPrep(e.target.value)}
                                className="verb-argspec-select"
                            >
                                <option value="none">none</option>
                                <option value="any">any</option>
                                <option value="with">with</option>
                                <option value="at">at</option>
                                <option value="in-front-of">in-front-of</option>
                                <option value="in">in</option>
                                <option value="on">on</option>
                                <option value="from">from (out of)</option>
                                <option value="over">over</option>
                                <option value="through">through</option>
                                <option value="under">under</option>
                                <option value="behind">behind</option>
                                <option value="beside">beside</option>
                                <option value="for">for</option>
                                <option value="is">is</option>
                                <option value="as">as</option>
                                <option value="off">off</option>
                                <option value="named">named</option>
                            </select>
                        </label>
                        <label className="verb-argspec-column">
                            <span className="verb-argspec-label">iobj</span>
                            <select
                                value={iobj}
                                onChange={(e) => setIobj(e.target.value)}
                                className="verb-argspec-select"
                            >
                                <option value="none">none</option>
                                <option value="any">any</option>
                                <option value="this">this</option>
                            </select>
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
                        {isSubmitting ? "Adding…" : "Add Verb"}
                    </button>
                </div>
            </form>
        </DialogSheet>
    );
};
