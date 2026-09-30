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

import { act, render } from "@testing-library/react";
import { stdout } from "node:process";
import { expect, it } from "vitest";
import { createTranscript } from "../lib/transcript";
import { OutputWindow } from "./OutputWindow";
import { ToastProvider } from "./Toast";

it("measures a 10,000-message transcript and a live append", async () => {
    const messages = Array.from({ length: 10000 }, (_, index) => ({
        id: `message-${index}`,
        content: `Transcript message ${index}`,
        type: "narrative" as const,
        contentType: "text/plain" as const,
        isHistorical: true,
    }));
    const started = performance.now();
    const transcript = createTranscript();
    transcript.replace(messages);
    const { container } = render(<OutputWindow transcript={transcript} />, { wrapper: ToastProvider });
    const initialMs = performance.now() - started;
    const appended = performance.now();
    await act(async () =>
        transcript.append({
            id: "live-message",
            content: "Newest live message",
            type: "narrative",
            contentType: "text/plain",
            isHistorical: false,
        })
    );
    const appendMs = performance.now() - appended;
    const mountedMessages = container.querySelectorAll("[data-message-id]").length;
    stdout.write(
        JSON.stringify({ initialMs: Math.round(initialMs), appendMs: Math.round(appendMs), mountedMessages }) + "\n",
    );
    expect(mountedMessages).toBe(200);
    expect(transcript.size).toBe(10001);
    expect(container.textContent).toContain("Newest live message");
}, 60000);
