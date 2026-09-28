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

import React, { forwardRef, useEffect, useId, useRef, useState } from "react";
import { useArgumentCoordinator } from "../context/ArgumentContext";
import { Suggestion, SuggestionSource, useSuggestions } from "../hooks/useSuggestions";
import { SemanticIcon } from "./SemanticIcon";

interface SuggestionInputProps {
    id: string;
    value: string;
    placeholder?: string;
    source?: SuggestionSource;
    authToken: string | null;
    revision?: number;
    argumentLabel?: string;
    onChange: (text: string, selection?: Suggestion) => void;
}

/** A reusable combobox: choosing an option fills the field and never submits its enclosing form. */
export const SuggestionInput = forwardRef<HTMLInputElement, SuggestionInputProps>(function SuggestionInput({
    id,
    value,
    placeholder,
    source,
    authToken,
    revision = 0,
    argumentLabel,
    onChange,
}, ref) {
    const listId = useId();
    const coordinator = useArgumentCoordinator();
    const [notice, setNotice] = useState("");
    const input = useRef<HTMLInputElement | null>(null);
    const latest = useRef(onChange);
    latest.current = onChange;
    const sourceKey = JSON.stringify(source);
    const focusArgument = () => {
        if (!source) {
            coordinator?.focus();
            return;
        }
        coordinator?.focus({
            id: listId,
            label: argumentLabel ?? "this argument",
            source,
            choose: item => {
                latest.current(item.label, item);
                input.current?.focus({ preventScroll: true });
                setOpen(false);
            },
            feedback: setNotice,
        });
    };
    useEffect(() => {
        if (coordinator?.owns(listId)) focusArgument();
    }, [sourceKey, revision]); // eslint-disable-line react-hooks/exhaustive-deps
    useEffect(() => () => coordinator?.release(listId), [coordinator, listId]);
    const [open, setOpen] = useState(false);
    const [active, setActive] = useState(-1);
    const { items, more, loading, error } = useSuggestions(authToken, source, value, open, revision);
    useEffect(() => {
        setActive(-1);
    }, [items]);
    useEffect(() => {
        if (active >= 0) document.getElementById(`${listId}-${active}`)?.scrollIntoView?.({ block: "nearest" });
    }, [active, listId]);
    const choose = (item: Suggestion) => {
        onChange(item.label, item);
        setOpen(false);
        setActive(-1);
    };
    return (
        <div className="suggestion-input">
            <input
                ref={element => {
                    input.current = element;
                    if (typeof ref === "function") ref(element);
                    else if (ref) ref.current = element;
                }}
                id={id}
                value={value}
                placeholder={placeholder}
                autoComplete="off"
                maxLength={source ? 256 : undefined}
                role={source ? "combobox" : undefined}
                aria-autocomplete={source ? "list" : undefined}
                aria-expanded={source ? open : undefined}
                aria-controls={source && open ? listId : undefined}
                aria-activedescendant={open && active >= 0 && items[active] ? `${listId}-${active}` : undefined}
                onFocus={() => {
                    setOpen(Boolean(source));
                    focusArgument();
                }}
                onBlur={() => setOpen(false)}
                onChange={event => {
                    setNotice("");
                    onChange(event.target.value);
                    coordinator?.invalidate();
                    setOpen(Boolean(source));
                    setActive(-1);
                }}
                onKeyDown={event => {
                    if (!source) return;
                    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                        event.preventDefault();
                        setOpen(true);
                        if (items.length) {
                            setActive(index =>
                                event.key === "ArrowDown"
                                    ? (index + 1) % items.length
                                    : (index <= 0 ? items.length : index) - 1
                            );
                        }
                    } else if (open && (event.key === "Enter" || event.key === "Tab") && items[active]) {
                        if (event.key === "Enter") event.preventDefault();
                        choose(items[active]);
                    } else if (open && event.key === "Escape") {
                        event.preventDefault();
                        event.stopPropagation();
                        setOpen(false);
                        setActive(-1);
                    }
                }}
            />
            {notice && <small role="status">{notice}</small>}
            {source && open && (
                <div className="suggestion-input-menu">
                    <div id={listId} role="listbox" aria-label="Suggestions" aria-busy={loading}>
                        {items.map((item, index) => (
                            <button
                                key={item.id}
                                id={`${listId}-${index}`}
                                type="button"
                                role="option"
                                aria-selected={active === index}
                                tabIndex={-1}
                                onPointerDown={event => event.preventDefault()}
                                onClick={() => choose(item)}
                                onPointerMove={() => setActive(index)}
                            >
                                <span className="suggestion-label">
                                    <SemanticIcon kind={item.objectKind} />
                                    {item.label}
                                </span>
                                <small>{item.detail}</small>
                            </button>
                        ))}
                    </div>
                    <div className="suggestion-input-status" role="status">
                        {loading ? "Finding suggestions…" : error || (more
                            ? "Keep typing to narrow the choices."
                            : items.length
                            ? "↑ ↓ to choose · Enter to select"
                            : "No matching suggestions.")}
                    </div>
                </div>
            )}
        </div>
    );
});
