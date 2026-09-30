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

import { virtual } from "@guidepup/virtual-screen-reader";
import { act, fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { AnnotationContext } from "../context/AnnotationContext";
import { createTranscript } from "../lib/transcript";
import { OutputWindow } from "./OutputWindow";
import { ToastProvider } from "./Toast";

// Helper to create a message
function createMessage(id: string, content: string, opts: {
    type?: "narrative" | "input_echo" | "system" | "error";
    presentationHint?: string;
    groupId?: string;
    contentType?: "text/plain" | "text/djot" | "text/html";
    eventMetadata?: {
        verb?: string;
        dobjName?: string;
        collapseTitle?: string;
    };
} = {}) {
    return {
        id,
        content,
        type: opts.type || "narrative",
        timestamp: Date.now(),
        isHistorical: false,
        contentType: opts.contentType || "text/plain",
        presentationHint: opts.presentationHint,
        groupId: opts.groupId,
        eventMetadata: opts.eventMetadata,
    };
}

function renderOutputWindow(messages: ReturnType<typeof createMessage>[]) {
    const transcript = createTranscript();
    transcript.replace(messages);
    return { ...render(<OutputWindow transcript={transcript} />, { wrapper: ToastProvider }), transcript };
}

// Helper to collect announcements from virtual screen reader
async function collectAnnouncements(maxIterations = 50): Promise<string[]> {
    const announcements: string[] = [];
    let lastPhrase = "";
    let iterations = 0;

    while (iterations < maxIterations) {
        const phrase = await virtual.lastSpokenPhrase();
        if (phrase && phrase !== lastPhrase) {
            announcements.push(phrase);
            lastPhrase = phrase;
        }

        const beforeNext = await virtual.lastSpokenPhrase();
        await virtual.next();
        const afterNext = await virtual.lastSpokenPhrase();

        // If we're at the end (no change after next), break
        if (beforeNext === afterNext && iterations > 5) {
            break;
        }

        iterations++;
    }

    return announcements;
}

// Helper to get only aria-live announcements from spoken phrase log
function getLiveAnnouncements(log: string[]): string[] {
    return log.filter(p => p.startsWith("polite:"));
}

describe("OutputWindow screen reader announcements", () => {
    it("announces simple text messages", async () => {
        const messages = [
            createMessage("1", "You head north."),
        ];

        const { container } = renderOutputWindow(messages);
        const outputWindow = container.querySelector("#output_window");
        expect(outputWindow).not.toBeNull();

        await virtual.start({ container: outputWindow as Element });
        const announcements = await collectAnnouncements();
        await virtual.stop();

        expect(announcements.some(a => a.includes("north"))).toBe(true);
    });

    it("announces room descriptions with djot content", async () => {
        const messages = [
            createMessage("1", "You head north."),
            createMessage("2", "# The Anteroom\n\nAn empty room awaiting a description.", {
                presentationHint: "inset",
                groupId: "room-123",
                contentType: "text/djot",
                eventMetadata: {
                    verb: "look",
                    dobjName: "The Anteroom",
                    collapseTitle: "The Anteroom",
                },
            }),
            createMessage("3", "You arrive from the south."),
        ];

        const { container } = renderOutputWindow(messages);
        const outputWindow = container.querySelector("#output_window");

        await virtual.start({ container: outputWindow as Element });
        const announcements = await collectAnnouncements();
        await virtual.stop();

        const allText = announcements.join(" ").toLowerCase();
        expect(allText).toContain("north");
        expect(allText).toContain("anteroom");
        expect(allText).toContain("south");
    });

    it("announces all messages in a room transition sequence", async () => {
        const messages = [
            createMessage("1", "You head north."),
            createMessage("2", "# Anteroom\n\nAn empty room.", {
                presentationHint: "inset",
                groupId: "room-1",
                contentType: "text/djot",
                eventMetadata: { verb: "look", dobjName: "Anteroom", collapseTitle: "Anteroom" },
            }),
            createMessage("3", "You arrive from the south."),
            createMessage("4", "You head south."),
            createMessage("5", "# The First Room\n\nThe starting room.", {
                presentationHint: "inset",
                groupId: "room-2",
                contentType: "text/djot",
                eventMetadata: { verb: "look", dobjName: "The First Room", collapseTitle: "The First Room" },
            }),
            createMessage("6", "You arrive from the north."),
        ];

        const { container } = renderOutputWindow(messages);
        const outputWindow = container.querySelector("#output_window");

        await virtual.start({ container: outputWindow as Element });
        const announcements = await collectAnnouncements(100);
        await virtual.stop();

        const allText = announcements.join(" ").toLowerCase();
        expect(allText).toContain("head north");
        expect(allText).toContain("head south");
        expect(allText).toContain("arrive from the south");
        expect(allText).toContain("arrive from the north");
        expect(allText).toContain("anteroom");
        expect(allText).toContain("first room");
    });

    it("announces dynamically added messages via aria-live", async () => {
        const messages = [
            createMessage("1", "Initial message."),
        ];

        const { container, transcript } = renderOutputWindow([...messages]);
        const outputWindow = container.querySelector("#output_window");

        await virtual.start({ container: outputWindow as Element });
        await new Promise(r => setTimeout(r, 10));

        // Add messages one at a time with delays
        messages.push(createMessage("2", "Second message."));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 50));

        messages.push(createMessage("3", "Third message."));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 50));

        messages.push(createMessage("4", "Fourth message."));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 50));

        const liveAnnouncements = getLiveAnnouncements(await virtual.spokenPhraseLog());
        await virtual.stop();

        expect(liveAnnouncements.length).toBeGreaterThanOrEqual(3);
        expect(liveAnnouncements.some(a => a.includes("Second"))).toBe(true);
        expect(liveAnnouncements.some(a => a.includes("Third"))).toBe(true);
        expect(liveAnnouncements.some(a => a.includes("Fourth"))).toBe(true);
    });

    it("announces room transition messages added dynamically", async () => {
        const messages = [
            createMessage("initial", "You are in the starting room."),
        ];

        const { container, transcript } = renderOutputWindow([...messages]);
        const outputWindow = container.querySelector("#output_window");

        await virtual.start({ container: outputWindow as Element });
        await new Promise(r => setTimeout(r, 10));

        // Movement message
        messages.push(createMessage("move", "You head north."));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 30));

        // Room description
        messages.push(createMessage("room", "# Anteroom\n\nAn empty room.", {
            presentationHint: "inset",
            groupId: "room-1",
            contentType: "text/djot",
            eventMetadata: { verb: "look", dobjName: "Anteroom", collapseTitle: "Anteroom" },
        }));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 30));

        // Arrival message
        messages.push(createMessage("arrive", "You arrive from the south."));
        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 30));

        const liveAnnouncements = getLiveAnnouncements(await virtual.spokenPhraseLog());
        await virtual.stop();

        const announcedText = liveAnnouncements.join(" ").toLowerCase();
        expect(announcedText).toContain("north");
        expect(announcedText).toContain("anteroom");
        expect(announcedText).toContain("south");
    });

    it("announces batched messages added in single render", async () => {
        const messages = [
            createMessage("1", "Initial message."),
        ];

        const { container, transcript } = renderOutputWindow([...messages]);
        const outputWindow = container.querySelector("#output_window");

        await virtual.start({ container: outputWindow as Element });
        await new Promise(r => setTimeout(r, 10));

        // Add multiple messages in a single rerender
        messages.push(createMessage("2", "Batch message alpha."));
        messages.push(createMessage("3", "Batch message beta."));
        messages.push(createMessage("4", "Batch message gamma."));

        await act(async () => {
            messages.forEach(message => transcript.append(message));
        });
        await new Promise(r => setTimeout(r, 100));

        const liveAnnouncements = getLiveAnnouncements(await virtual.spokenPhraseLog());
        await virtual.stop();

        const announcedText = liveAnnouncements.join(" ").toLowerCase();
        expect(announcedText).toContain("alpha");
        expect(announcedText).toContain("beta");
        expect(announcedText).toContain("gamma");
    });
});

describe("OutputWindow exit annotations", () => {
    it("routes a historic occurrence with its own exact command for review", () => {
        const activate = vi.fn();
        const annotation = {
            kind: "command" as const,
            command: "go e",
            exit: { source: "oid:10", destination: "oid:20", passage: "id" },
        };
        const message = {
            ...createMessage("old-room", "<span data-moor-annotation=\"a1\">East</span>", { contentType: "text/html" }),
            isHistorical: true,
            eventMetadata: { annotations: { a1: annotation } },
        };
        const { container } = render(
            <AnnotationContext.Provider value={activate}>
                <OutputWindow
                    transcript={(() => {
                        const transcript = createTranscript();
                        transcript.replace([message]);
                        return transcript;
                    })()}
                />
            </AnnotationContext.Provider>,
            { wrapper: ToastProvider },
        );
        fireEvent.click(container.querySelector("[data-moor-annotation=\"a1\"]")!);
        expect(activate).toHaveBeenCalledWith(expect.objectContaining({ annotation }));
    });
});

describe("Metadata-driven inset collapse", () => {
    it.each([false, true])("collapses and expands help output (grouped: %s)", grouped => {
        sessionStorage.clear();
        const options = {
            presentationHint: "inset",
            groupId: "help:player",
            eventMetadata: { verb: "info", collapseTitle: "Help" },
        };
        const messages = [createMessage("help-summary", "Help topics and commands", options)];
        if (grouped) messages.push(createMessage("help-more", "More commands", options));
        const { container } = renderOutputWindow(messages);
        expect(container.querySelector(".inset_collapsed_summary")).toBeNull();
        fireEvent.click(container.querySelector(".inset_toggle_button")!);
        expect(container.querySelector(".inset_collapsed_name")?.textContent).toBe("Help");
        expect(container.querySelector(".presentation_inset .sr-only")?.textContent).toContain(
            "Help topics and commands",
        );
        fireEvent.click(container.querySelector(".inset_toggle_button")!);
        expect(container.querySelector(".inset_collapsed_summary")).toBeNull();
        expect(container.querySelector(".inset_toggle_row")?.textContent).toContain("Help topics and commands");
        sessionStorage.clear();
    });
});

it("requires explicit collapse metadata and does not require a group", () => {
    sessionStorage.clear();
    const { container } = renderOutputWindow([
        createMessage("plain-help", "Help without a collapse title", {
            presentationHint: "inset",
            eventMetadata: { verb: "help" },
        }),
        createMessage("plain-look", "Look without a collapse title", {
            presentationHint: "inset",
            eventMetadata: { verb: "look", dobjName: "Room" },
        }),
        createMessage("custom", "An authored report", {
            presentationHint: "inset",
            eventMetadata: { collapseTitle: "Report" },
        }),
    ]);
    expect(container.querySelectorAll(".inset_toggle_button")).toHaveLength(1);
    fireEvent.click(container.querySelector(".inset_toggle_button")!);
    expect(container.querySelector(".inset_collapsed_name")?.textContent).toBe("Report");
    sessionStorage.clear();
});

it("does not announce recycled or prepended history while continuing to announce live output", async () => {
    const messages = Array.from(
        { length: 500 },
        (_, i) => ({ ...createMessage(String(i), `Old message ${i}`), isHistorical: true }),
    );
    const { container, transcript, getByText } = renderOutputWindow(messages);
    await virtual.start({ container: container.querySelector("#output_window")! });
    await act(async () => {
        fireEvent.click(getByText("Older messages"));
    });
    await act(async () => transcript.prepend([{ ...createMessage("earlier", "Earlier history"), isHistorical: true }]));
    expect(getLiveAnnouncements(await virtual.spokenPhraseLog())).toEqual([]);
    await act(async () =>
        transcript.append({
            ...createMessage("live", "<b>New output</b>"),
            contentType: "text/html",
            ttsText: "Spoken new output",
        })
    );
    const live = getLiveAnnouncements(await virtual.spokenPhraseLog());
    await virtual.stop();
    expect(live.some(phrase => phrase.includes("Spoken new output"))).toBe(true);
    expect(live.some(phrase => /Old message|Earlier history/.test(phrase))).toBe(false);
    expect(container.querySelector("[data-message-id=\"live\"]")).toBeNull();
});

it("bounds burst announcements, provides plain text, and clears them with the transcript", async () => {
    const { container, transcript } = renderOutputWindow([]);
    await act(async () => {
        for (let i = 0; i < 250; i++) {
            transcript.append(
                createMessage(String(i), `[Link ${i}](https://example.com)`, { contentType: "text/djot" }),
            );
        }
    });
    const live = container.querySelector("[aria-live=\"polite\"]")!;
    expect(live.children).toHaveLength(201);
    expect(live.textContent).toContain("50 additional new messages");
    expect(live.textContent).toContain("Link 249");
    expect(live.querySelector("a, button, img")).toBeNull();
    await act(async () => transcript.replace([]));
    expect(live.textContent).toBe("");
    await act(async () => transcript.append(createMessage("new-session", "New session output")));
    expect(live.textContent).toBe("New session output");
});

it("reports an active room look as offscreen when its group leaves the window", async () => {
    const transcript = createTranscript();
    const report = vi.fn();
    transcript.replace(Array.from({ length: 500 }, (_, i) => createMessage(String(i), `Old ${i}`)));
    transcript.append({
        ...createMessage("room", "Current room"),
        presentationHint: "inset",
        eventMetadata: { verb: "look", lookRoom: { oid: 1 } },
    });
    const { getByText } = render(
        <OutputWindow transcript={transcript} currentRoomLookKey="oid:1" onActiveRoomLookVisibilityChange={report} />,
        { wrapper: ToastProvider },
    );
    expect(report).toHaveBeenLastCalledWith("oid:1", true, "room");
    fireEvent.click(getByText("Older messages"));
    expect(report).toHaveBeenLastCalledWith("oid:1", false, null);
    fireEvent.click(getByText("Jump to Now"));
    expect(report).toHaveBeenLastCalledWith("oid:1", true, "room");
});
