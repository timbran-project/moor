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

import type { NarrativeMessage } from "../components/Narrative";
import { extractRoomLookKey } from "./var";

export interface TranscriptGroup {
    id: string;
    messages: readonly NarrativeMessage[];
}

export function canGroupMessages(left: NarrativeMessage, right: NarrativeMessage): boolean {
    if (left.noNewline) return true;
    if (
        !left.presentationHint || !left.groupId || left.presentationHint !== right.presentationHint
        || left.groupId !== right.groupId || left.eventMetadata?.collapseTitle !== right.eventMetadata?.collapseTitle
    ) return false;
    const a = left.eventMetadata?.actor;
    const b = right.eventMetadata?.actor;
    if (!a || !b) return true;
    if (a.oid !== undefined && b.oid !== undefined) return a.oid === b.oid;
    if (a.uuid !== undefined && b.uuid !== undefined) return a.uuid === b.uuid;
    return false;
}

export function roomLookKey(message: NarrativeMessage): string | null {
    if (message.presentationHint !== "inset" || message.eventMetadata?.verb !== "look") return null;
    return extractRoomLookKey([
        message.eventMetadata.lookRoom,
        message.eventMetadata.look_room,
        message.eventMetadata.dobj,
        message.eventMetadata.thisObj,
    ]);
}

/** Indexed transcript with stable history groups and a separately paged live-message index. */
export function createTranscript() {
    let version = 0;
    let first = 0;
    let end = 0;
    const groups = new Map<number, { id: string; messages: NarrativeMessage[] }>();
    const records = new Map<string, { message: NarrativeMessage; group: number }>();
    const groupPositions = new Map<string, number>();
    const livePages: string[][] = [];
    const latestRoomLooks = new Map<string, string>();
    const latestLiveVerbs = new Map<string, string>();
    const stale = new Set<string>();
    const listeners = new Set<() => void>();
    let liveRevision = 0;
    let generation = 0;
    let announcements: { revision: number; message: NarrativeMessage }[] = [];

    const notify = () => {
        version++;
        listeners.forEach(listener => listener());
    };
    const saveRecord = (message: NarrativeMessage, group: number, prepending = false) => {
        records.set(message.id, { message, group });
        const key = roomLookKey(message);
        if (key && (!prepending || !latestRoomLooks.has(key))) latestRoomLooks.set(key, message.id);
        const verb = message.eventMetadata?.verb;
        if (!message.isHistorical && verb) {
            const previous = latestLiveVerbs.get(verb);
            if (verb === "look" && previous) stale.add(previous);
            latestLiveVerbs.set(verb, message.id);
        }
    };
    const appendInternal = (message: NarrativeMessage) => {
        const tail = groups.get(end - 1);
        if (tail && canGroupMessages(tail.messages[tail.messages.length - 1], message)) {
            tail.messages.push(message);
            groups.set(end - 1, { ...tail });
            saveRecord(message, end - 1);
        } else {
            groups.set(end, { id: message.id, messages: [message] });
            groupPositions.set(message.id, end);
            saveRecord(message, end++);
        }
        if (!message.isHistorical) {
            if (!livePages.length || livePages[livePages.length - 1].length >= 128) livePages.push([]);
            livePages[livePages.length - 1].push(message.id);
        }
    };
    const allMessages = () => {
        const result: NarrativeMessage[] = [];
        for (let index = first; index < end; index++) {
            for (const message of groups.get(index)!.messages) result.push(message);
        }
        return result;
    };
    const resetInternal = (messages: readonly NarrativeMessage[]) => {
        groups.clear();
        records.clear();
        groupPositions.clear();
        livePages.length = 0;
        latestRoomLooks.clear();
        latestLiveVerbs.clear();
        stale.clear();
        first = 0;
        end = 0;
        for (const message of messages) {
            if (!records.has(message.id)) appendInternal(message);
        }
    };
    return {
        subscribe(listener: () => void) {
            listeners.add(listener);
            return () => {
                listeners.delete(listener);
            };
        },
        getVersion: () => version,
        get first() {
            return first;
        },
        get end() {
            return end;
        },
        get size() {
            return records.size;
        },
        get stale() {
            return stale;
        },
        get generation() {
            return generation;
        },
        get liveRevision() {
            return liveRevision;
        },
        announcementsAfter: (revision: number) =>
            announcements.filter(entry => entry.revision > revision).map(entry => entry.message),
        get: (id: string) => records.get(id)?.message,
        group: (index: number): TranscriptGroup | undefined => groups.get(index),
        groupPosition: (id: string) => groupPositions.get(id) ?? records.get(id)?.group,
        latestRoomLook: (key: string) => latestRoomLooks.get(key) ?? null,
        liveMessages: () => livePages.flatMap(page => page.map(id => records.get(id)!.message)),
        allMessages,
        append(message: NarrativeMessage) {
            if (records.has(message.id)) return;
            appendInternal(message);
            if (!message.isHistorical) {
                liveRevision++;
                announcements.push({ revision: liveRevision, message });
                if (announcements.length > 200) announcements = announcements.slice(-200);
            }
            notify();
        },
        replace(messages: readonly NarrativeMessage[]) {
            resetInternal(messages);
            generation++;
            liveRevision = 0;
            announcements = [];
            notify();
        },
        prepend(messages: readonly NarrativeMessage[]) {
            const incoming: NarrativeMessage[][] = [];
            const seen = new Set<string>();
            for (const message of messages) {
                if (records.has(message.id) || seen.has(message.id)) continue;
                seen.add(message.id);
                const tail = incoming[incoming.length - 1];
                if (tail && canGroupMessages(tail[tail.length - 1], message)) tail.push(message);
                else incoming.push([message]);
            }
            if (!incoming.length) return;
            const head = groups.get(first);
            const tail = incoming[incoming.length - 1];
            if (head && canGroupMessages(tail[tail.length - 1], head.messages[0])) {
                groups.set(first, { id: head.id, messages: [...tail, ...head.messages] });
                for (let i = tail.length - 1; i >= 0; i--) saveRecord(tail[i], first, true);
                incoming.pop();
            }
            for (let i = incoming.length - 1; i >= 0; i--) {
                const messages = incoming[i];
                const group = { id: messages[0].id, messages };
                groups.set(--first, group);
                groupPositions.set(group.id, first);
                // Newer messages within an older page still win its room-look index.
                for (let j = messages.length - 1; j >= 0; j--) saveRecord(messages[j], first, true);
            }
            notify();
        },
        update(id: string, update: (message: NarrativeMessage) => NarrativeMessage) {
            const record = records.get(id);
            if (!record) return;
            const message = update(record.message);
            if (message === record.message) return;
            const group = groups.get(record.group)!;
            const offset = group.messages.findIndex(message => message.id === id);
            const previousGroup = groups.get(record.group - 1);
            const previous = group.messages[offset - 1] ?? previousGroup?.messages[previousGroup.messages.length - 1];
            const next = group.messages[offset + 1] ?? groups.get(record.group + 1)?.messages[0];
            const changedBoundary =
                (previous && canGroupMessages(previous, record.message) !== canGroupMessages(previous, message))
                || (next && canGroupMessages(record.message, next) !== canGroupMessages(message, next));
            if (
                changedBoundary || roomLookKey(record.message) !== roomLookKey(message)
                || record.message.eventMetadata?.verb !== message.eventMetadata?.verb
            ) {
                // Structural rewrites are uncommon; appends and ordinary content rewrites stay indexed.
                const savedStale = new Set(stale);
                resetInternal(allMessages().map(existing => existing.id === id ? message : existing));
                savedStale.forEach(id => stale.add(id));
            } else {
                records.set(id, { ...record, message });
                const messages = [...group.messages];
                messages[offset] = message;
                groups.set(record.group, { ...group, messages });
            }
            notify();
        },
        markStale(id: string) {
            if (stale.has(id)) return;
            stale.add(id);
            notify();
        },
    };
}

export type Transcript = ReturnType<typeof createTranscript>;
