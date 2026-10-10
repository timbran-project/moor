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

import Editor, { DiffEditor } from "@monaco-editor/react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import {
    baselineText,
    changeLabels,
    ChangeReviewClient,
    ChangeRow,
    ChangeTarget,
    Choice,
    Classification,
    LocalItemPage,
    ReviewPage,
    ReviewStatus,
} from "../lib/change-review";
import "../lib/monaco";
import { registerMooLanguage } from "../lib/monaco-moo";
import { DialogSheet } from "./DialogSheet";
import { useTheme } from "./ThemeProvider";
import { monacoThemeFor } from "./themeSupport";
import "../styles/change-review.css";

interface Props {
    visible: boolean;
    target: ChangeTarget;
    authToken: string;
    onClose: () => void;
}
const choices: Record<Choice, string> = {
    incoming: "Use upstream",
    local: "Keep local",
    edited: "Use edited program",
    defer: "Skip",
    unresolved: "Choose a version",
};
const blockers: Record<string, string> = {
    untrusted_target_authority: "Ownership or permissions prevent updating this verb.",
    object_identity_mismatch: "The installed object and upstream object have different identities.",
    adoption_required: "Accept an upstream baseline before updating this verb.",
};
const categories: Classification[] = ["conflict", "upstream", "local", "unbased", "converged"];
type ReviewFilter = Classification | "unmatched";

export function ChangeReview({ target, authToken, onClose }: Props) {
    const id = useId();
    const { theme } = useTheme();
    const client = useMemo(() => new ChangeReviewClient(authToken, target), [authToken, target]);
    const [generation, setGeneration] = useState(target.generation);
    const [status, setStatus] = useState<ReviewStatus | null>(null);
    const [page, setPage] = useState<ReviewPage | null>(null);
    const [category, setCategory] = useState<ReviewFilter>("conflict");
    const [localItems, setLocalItems] = useState<LocalItemPage | null>(null);
    const [rows, setRows] = useState<ChangeRow[]>([]);
    const [row, setRow] = useState<ChangeRow | null>(null);
    const [busy, setBusy] = useState(true);
    const [error, setError] = useState("");
    const [notice, setNotice] = useState("");
    const [editing, setEditing] = useState(false);
    const [draft, setDraft] = useState("");
    const [initialDraft, setInitialDraft] = useState("");
    const [comparison, setComparison] = useState("local-upstream");
    const [confirmation, setConfirmation] = useState<"apply" | "discard" | null>(null);
    const pendingNavigation = useRef<(() => void) | null>(null);
    const sequence = useRef(0);
    const dirty = editing && draft !== initialDraft;

    const selectDetail = useCallback((detail: ChangeRow | null) => {
        setRow(detail);
        setEditing(false);
        setComparison("local-upstream");
        const saved = detail?.choice?.program ?? detail?.live_text ?? "";
        setDraft(saved);
        setInitialDraft(saved);
    }, []);
    const fail = useCallback(
        (failure: unknown) => setError(failure instanceof Error ? failure.message : "Could not load the review."),
        [],
    );

    const load = useCallback(async (version: number, selected?: string, filter?: ReviewFilter) => {
        const request = ++sequence.current;
        setBusy(true);
        setError("");
        selectDetail(null);
        try {
            const current = await client.status();
            if (request !== sequence.current) return;
            setStatus(current);
            if (!["ready", "partial", "rejected"].includes(current.status)) {
                setPage(null);
                return;
            }
            const [overview, local] = await Promise.all([client.page(version), client.localItems(version)]);
            const detail = selected ? await client.details(version, selected) : null;
            const nextCategory = filter ?? detail?.classification ?? categories.find(key => overview.counts[key])
                ?? (local.total ? "unmatched" : "upstream");
            const nextPage = nextCategory !== "unmatched" && overview.counts[nextCategory]
                ? await client.page(version, [], nextCategory)
                : { ...overview, rows: [], cursor: [] };
            const first = detail ?? (nextPage.rows[0] ? await client.details(version, nextPage.rows[0].id) : null);
            if (request !== sequence.current) return;
            setGeneration(version);
            setCategory(nextCategory);
            setPage(nextPage);
            setLocalItems(local);
            setRows(nextPage.rows);
            selectDetail(first);
        } catch (failure) {
            if (request === sequence.current) fail(failure);
        } finally {
            if (request === sequence.current) setBusy(false);
        }
    }, [client, selectDetail, fail]);
    const invalidate = useCallback(() => {
        sequence.current++;
    }, []);
    useEffect(() => {
        void load(target.generation, target.row);
        return invalidate;
    }, [load, target.generation, target.row, invalidate]);

    useEffect(() => {
        if (status?.status !== "applying") return;
        let cancelled = false;
        let timer: ReturnType<typeof setTimeout>;
        const poll = async () => {
            try {
                const current = await client.status();
                if (cancelled) return;
                setStatus(current);
                if (current.status === "applying") timer = setTimeout(poll, 1000);
                else if (["partial", "ready", "rejected"].includes(current.status)) await load(current.generation);
            } catch (failure) {
                if (!cancelled) fail(failure);
            }
        };
        timer = setTimeout(poll, 500);
        return () => {
            cancelled = true;
            clearTimeout(timer);
        };
    }, [status?.status, client, load, fail]);

    const navigate = (action: () => void) => {
        if (dirty) {
            pendingNavigation.current = action;
            setConfirmation("discard");
        } else action();
    };
    const select = async (selected: ChangeRow) => {
        const request = ++sequence.current;
        setBusy(true);
        setError("");
        try {
            const detail = await client.details(generation, selected.id);
            if (request === sequence.current) selectDetail(detail);
        } catch (failure) {
            if (request === sequence.current) fail(failure);
        } finally {
            if (request === sequence.current) setBusy(false);
        }
    };
    const more = async () => {
        if (!page?.cursor.length) return;
        const request = ++sequence.current;
        setBusy(true);
        try {
            const next = await client.page(generation, page.cursor, category === "unmatched" ? "" : category);
            if (request !== sequence.current) return;
            setRows(previous => [...previous, ...next.rows]);
            setPage(next);
        } catch (failure) {
            if (request === sequence.current) fail(failure);
        } finally {
            if (request === sequence.current) setBusy(false);
        }
    };
    const moreLocalItems = async () => {
        if (!localItems?.next) return;
        const request = ++sequence.current;
        setBusy(true);
        try {
            const next = await client.localItems(generation, localItems.next);
            if (request === sequence.current) {
                setLocalItems(previous => ({ ...next, items: [...(previous?.items ?? []), ...next.items] }));
            }
        } catch (failure) {
            if (request === sequence.current) fail(failure);
        } finally {
            if (request === sequence.current) setBusy(false);
        }
    };
    const resolve = async (selected: Choice) => {
        if (!row) return;
        const request = ++sequence.current;
        setBusy(true);
        setError("");
        try {
            const saved = await client.resolve(generation, row.id, selected, selected === "edited" ? draft : "");
            if (request !== sequence.current) return;
            setNotice(saved.errors.length ? saved.errors.join("\n") : "Choice saved. Live code has not changed.");
            await load(saved.generation, row.id, category);
        } catch (failure) {
            if (request === sequence.current) {
                fail(failure);
                setBusy(false);
            }
        }
    };
    const apply = async () => {
        setConfirmation(null);
        const request = ++sequence.current;
        setBusy(true);
        setError("");
        try {
            const result = await client.apply(generation);
            if (request !== sequence.current) return;
            setStatus(result);
            selectDetail(null);
            if (["partial", "ready", "rejected"].includes(result.status)) await load(result.generation);
            else setPage(null);
        } catch (failure) {
            if (request === sequence.current) fail(failure);
        } finally {
            if (request === sequence.current) setBusy(false);
        }
    };

    const baseline = row ? baselineText(row) : undefined;
    const original = comparison === "local-upstream" ? row?.live_text : baseline;
    const modified = comparison === "baseline-local" ? row?.live_text : row?.incoming_text;
    const selectedCount = page?.decision_counts.selected ?? 0;
    const applying = status?.status === "applying";
    const statusText = busy
        ? "Loading…"
        : applying
        ? "Applying updates…"
        : status?.status === "fetching"
        ? "Fetching upstream source…"
        : status?.status === "failed"
        ? "The upstream fetch failed."
        : status?.status === "complete"
        ? "Updates applied."
        : status?.status === "discarded"
        ? "This review was discarded."
        : "Save your choices, then apply them to the running MOO.";
    const canApply = Boolean(
        page && selectedCount && !page.decision_counts.unresolved && !busy && !dirty && !error && !applying,
    );

    return (
        <div className="change-review-shell" aria-busy={busy || applying}>
            <DialogSheet
                title={`${status?.package ?? "Changes"} · Review upstream changes`}
                titleId={id}
                onCancel={() => navigate(onClose)}
                maxWidth="1440px"
            >
                <div className="change-review-toolbar">
                    <span role="status">{statusText}</span>
                    <button type="button" onClick={() => navigate(onClose)}>Close</button>
                </div>
                {error && (
                    <div role="alert" className="change-review-error">
                        {error}
                        <button
                            type="button"
                            disabled={busy}
                            onClick={() =>
                                navigate(() => {
                                    void client.status().then(current => load(current.generation, row?.id, category))
                                        .catch(fail);
                                })}
                        >
                            Reload review
                        </button>
                    </div>
                )}
                {notice && <p role="status" className="change-review-notice">{notice}</p>}
                {status?.error?.message && <p role="alert">{status.error.message}</p>}
                {page && !applying && (
                    <div className="change-review-workspace" aria-busy={busy}>
                        <aside className="change-review-sidebar" aria-label="Program changes">
                            <label htmlFor={`${id}-filter`}>Show</label>
                            <select
                                id={`${id}-filter`}
                                value={category}
                                disabled={busy}
                                onChange={event =>
                                    navigate(() => {
                                        void load(generation, undefined, event.target.value as ReviewFilter);
                                    })}
                            >
                                {(category === "unchanged" ? [...categories, "unchanged" as const] : categories).map(
                                    key => (
                                        <option key={key} value={key}>
                                            {changeLabels[key]} ({page.counts[key] ?? 0})
                                        </option>
                                    ),
                                )}
                                {!!localItems?.total && (
                                    <option value="unmatched">Only in this MOO ({localItems.total})</option>
                                )}
                            </select>
                            <div className="change-review-programs">
                                {rows.map(item => (
                                    <button
                                        type="button"
                                        key={item.id}
                                        aria-current={row?.id === item.id ? "true" : undefined}
                                        disabled={busy}
                                        onClick={() =>
                                            navigate(() => {
                                                void select(item);
                                            })}
                                    >
                                        <code>{item.label}</code>
                                        {!item.eligible && <small>Blocked</small>}
                                    </button>
                                ))}
                                {!rows.length && category !== "unmatched" && (
                                    <p>No {changeLabels[category].toLowerCase()}.</p>
                                )}
                                {!!page.cursor.length && (
                                    <button
                                        type="button"
                                        disabled={busy}
                                        onClick={() => {
                                            void more();
                                        }}
                                    >
                                        Load more ({rows.length} shown)
                                    </button>
                                )}
                            </div>
                            <small>
                                {page.counts.unchanged ?? 0} unchanged programs.
                            </small>
                        </aside>
                        <main className="change-review-code">
                            {category === "unmatched" && localItems
                                ? (
                                    <>
                                        <h3>Only in this MOO</h3>
                                        <p>These objects and verbs are absent from upstream. They will be kept.</p>
                                        <ul className="change-review-local-items">
                                            {localItems.items.map(item => (
                                                <li key={`${item.kind}:${item.label}`}>
                                                    <code>{item.label}</code>
                                                    <span>{item.kind === "object" ? "Object" : "Verb"}</span>
                                                </li>
                                            ))}
                                        </ul>
                                        {!!localItems.next && (
                                            <button
                                                type="button"
                                                disabled={busy}
                                                onClick={() => void moreLocalItems()}
                                            >
                                                Load more ({localItems.items.length} of {localItems.total})
                                            </button>
                                        )}
                                    </>
                                )
                                : row
                                ? (
                                    <>
                                        <header>
                                            <h3>
                                                <code>{row.label}</code>
                                            </h3>
                                            <span>{changeLabels[row.classification]}</span>
                                        </header>
                                        {!row.eligible && (
                                            <p role="status">
                                                {row.blockers.map(reason => blockers[reason] ?? reason).join(" ")}
                                            </p>
                                        )}
                                        <div className="change-review-comparison">
                                            <label htmlFor={`${id}-comparison`}>Compare</label>
                                            <select
                                                id={`${id}-comparison`}
                                                value={comparison}
                                                onChange={event => setComparison(event.target.value)}
                                            >
                                                <option value="local-upstream">Local → Upstream</option>
                                                {baseline !== undefined && (
                                                    <>
                                                        <option value="baseline-local">
                                                            Accepted baseline → Local
                                                        </option>
                                                        <option value="baseline-upstream">
                                                            Accepted baseline → Upstream
                                                        </option>
                                                    </>
                                                )}
                                            </select>
                                            {baseline === undefined && (
                                                <small>
                                                    {row.base
                                                        ? "Accepted source wasn’t saved; only its hash is available."
                                                        : "This program has no accepted baseline."}
                                                </small>
                                            )}
                                        </div>
                                        <div className="change-review-pane-labels">
                                            <span>
                                                {comparison === "local-upstream" ? "Local" : "Accepted baseline"}
                                            </span>
                                            <span>{comparison === "baseline-local" ? "Local" : "Upstream"}</span>
                                        </div>
                                        <div className="change-review-diff">
                                            <DiffEditor
                                                key={row.id}
                                                original={original ?? ""}
                                                modified={modified ?? ""}
                                                language="moo"
                                                theme={monacoThemeFor(theme)}
                                                beforeMount={registerMooLanguage}
                                                options={{
                                                    readOnly: true,
                                                    originalEditable: false,
                                                    automaticLayout: true,
                                                    minimap: { enabled: false },
                                                    renderSideBySide: true,
                                                    diffWordWrap: "on",
                                                    scrollBeyondLastLine: false,
                                                }}
                                            />
                                        </div>
                                        {editing && (
                                            <section className="change-review-draft">
                                                <h4>Proposed program</h4>
                                                <Editor
                                                    language="moo"
                                                    theme={monacoThemeFor(theme)}
                                                    value={draft}
                                                    onChange={value => setDraft(value ?? "")}
                                                    beforeMount={registerMooLanguage}
                                                    options={{
                                                        readOnly: busy,
                                                        automaticLayout: true,
                                                        minimap: { enabled: false },
                                                        wordWrap: "on",
                                                        scrollBeyondLastLine: false,
                                                    }}
                                                />
                                            </section>
                                        )}
                                        <div className="change-review-resolution">
                                            <span>On apply: {choices[row.choice?.choice ?? row.default]}</span>
                                            {row.choices.filter(value => value !== "edited").map(value => (
                                                <button
                                                    type="button"
                                                    key={value}
                                                    disabled={busy || !!error || !row.eligible && value !== "defer"}
                                                    onClick={() =>
                                                        navigate(() => {
                                                            void resolve(value);
                                                        })}
                                                >
                                                    {value === "incoming" && page.operation === "adopt"
                                                        ? "Accept baseline"
                                                        : choices[value]}
                                                </button>
                                            ))}
                                            {row.eligible && row.choices.includes("edited") && (
                                                <button
                                                    type="button"
                                                    disabled={busy || !!error}
                                                    onClick={() => {
                                                        if (editing) void resolve("edited");
                                                        else setEditing(true);
                                                    }}
                                                >
                                                    {editing ? "Save proposed program" : "Edit resolution"}
                                                </button>
                                            )}
                                        </div>
                                    </>
                                )
                                : (
                                    <p>
                                        {busy
                                            ? "Loading program…"
                                            : categories.some(key => page.counts[key])
                                            ? "Select a program from the list."
                                            : "The compared programs haven’t changed."}
                                    </p>
                                )}
                        </main>
                    </div>
                )}
                {confirmation && (
                    <div className="change-review-confirmation" role="alert">
                        <p>
                            {confirmation === "discard"
                                ? "Discard the unsaved draft?"
                                : page?.operation === "adopt"
                                ? `Accept ${selectedCount} baselines? Live code will stay as it is.`
                                : `Apply ${selectedCount} program choices to the running MOO?`}
                        </p>
                        <button type="button" onClick={() => setConfirmation(null)}>Cancel</button>
                        <button
                            type="button"
                            onClick={() => {
                                if (confirmation === "apply") void apply();
                                else {
                                    setConfirmation(null);
                                    pendingNavigation.current?.();
                                    pendingNavigation.current = null;
                                }
                            }}
                        >
                            {confirmation === "apply" ? "Confirm apply" : "Discard draft"}
                        </button>
                    </div>
                )}
                {page && (
                    <footer className="change-review-footer">
                        <small>
                            {page.decision_counts.unresolved
                                ? `${page.decision_counts.unresolved} programs still need a choice. `
                                : ""}
                            {page.decision_counts.blocked
                                ? `${page.decision_counts.blocked} blocked programs will be kept. `
                                : ""}
                        </small>
                        <button
                            type="button"
                            className="btn-primary"
                            disabled={!canApply}
                            onClick={() => setConfirmation("apply")}
                        >
                            {page.operation === "adopt"
                                ? `Accept ${selectedCount} baselines`
                                : `Apply ${selectedCount} ${selectedCount === 1 ? "choice" : "choices"}`}
                        </button>
                    </footer>
                )}
            </DialogSheet>
        </div>
    );
}
