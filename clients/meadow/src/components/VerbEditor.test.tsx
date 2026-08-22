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

import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { VerbEditor } from "./VerbEditor";

const monacoCommand = vi.hoisted(() => ({ callback: null as (() => void) | null }));

vi.mock("@monaco-editor/react", async () => {
    const { useEffect } = await import("react");
    const monacoInstance = {
        editor: { setTheme: vi.fn() },
    };
    const model = {
        uri: { toString: () => "inmemory://verb-test" },
    };
    const editor = {
        addCommand: vi.fn((_keybinding: number, callback: () => void) => {
            monacoCommand.callback = callback;
        }),
        createDecorationsCollection: vi.fn(() => ({ clear: vi.fn(), set: vi.fn() })),
        dispose: vi.fn(),
        focus: vi.fn(),
        getModel: vi.fn(() => model),
        layout: vi.fn(),
        updateOptions: vi.fn(),
    };

    const MockEditor = (props: {
        beforeMount?: (monaco: typeof monacoInstance) => void;
        onMount?: (editor: typeof editor, monaco: typeof monacoInstance) => void;
        onChange?: (value: string) => void;
        value?: string;
    }) => {
        const { beforeMount, onMount } = props;
        useEffect(() => {
            beforeMount?.(monacoInstance);
            onMount?.(editor, monacoInstance);
        }, [beforeMount, onMount]);
        return (
            <textarea
                aria-label="Mock Monaco editor"
                value={props.value}
                onChange={event => props.onChange?.(event.target.value)}
            />
        );
    };

    return {
        default: MockEditor,
    };
});

vi.mock("monaco-editor", () => ({
    KeyCode: { Enter: 3 },
    KeyMod: { CtrlCmd: 1 },
    MarkerSeverity: { Error: 8 },
    Range: class {},
    editor: {
        OverviewRulerLane: { Right: 4 },
        setModelMarkers: vi.fn(),
        setTheme: vi.fn(),
    },
}));

vi.mock("./EditorWindow", () => ({
    EditorWindow: ({ children }: { children: ReactNode }) => <div>{children}</div>,
    useTitleBarDrag: () => ({}),
}));

vi.mock("./ThemeProvider", () => ({
    useTheme: () => ({ theme: "light" }),
}));

vi.mock("../hooks/useMediaQuery", () => ({ useMediaQuery: () => false }));
vi.mock("../hooks/useTouchDevice", () => ({ useTouchDevice: () => false }));
vi.mock("../lib/monaco-moo", () => ({ registerMooLanguage: vi.fn() }));
vi.mock("../lib/monaco-moo-completions", () => ({
    mooCompletionManager: {
        register: vi.fn(),
        unregister: vi.fn(),
        updateContext: vi.fn(),
    },
}));
vi.mock("../lib/rpc-fb.js", () => ({
    getVerbCodeFlatBuffer: vi.fn(),
    performEvalFlatBuffer: vi.fn(),
}));

describe("VerbEditor compile shortcut", () => {
    beforeEach(() => {
        monacoCommand.callback = null;
    });

    it("compiles the current model content after editing", async () => {
        const onSendMessage = vi.fn(() => true);
        render(
            <VerbEditor
                visible
                onClose={vi.fn()}
                title="Test verb"
                objectCurie="oid:7"
                verbName="test"
                initialContent="return 1;"
                authToken="auth-token"
                uploadAction="@program #7:test"
                onSendMessage={onSendMessage}
            />,
        );

        await waitFor(() => expect(monacoCommand.callback).not.toBeNull());
        fireEvent.change(screen.getByLabelText("Mock Monaco editor"), {
            target: { value: "return 2;\nreturn 3;" },
        });
        monacoCommand.callback?.();

        await waitFor(() => {
            expect(onSendMessage.mock.calls.map(([message]) => message)).toEqual([
                "@program #7:test",
                "return 2;",
                "return 3;",
                ".",
            ]);
        });
    });
});
