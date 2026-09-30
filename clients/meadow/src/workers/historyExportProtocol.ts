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

export const HISTORY_EXPORT_CHUNK_BYTES = 64 * 1024;
export const HISTORY_EXPORT_BLOB_LIMIT = 64 * 1024 * 1024;
export const HISTORY_EXPORT_PAGE_LIMIT = 16 * 1024 * 1024;
export const HISTORY_EXPORT_BATCH_SIZE = 250;

export interface StartExportMessage {
    type: "start";
    authToken: string;
    ageIdentity: string;
    systemTitle: string;
    playerOid: string;
}

export type WorkerRequest = StartExportMessage | { type: "ack" };
export type WorkerResponse =
    | { type: "progress"; processed: number }
    | { type: "chunk"; bytes: Uint8Array<ArrayBuffer> }
    | { type: "error"; error: string }
    | { type: "complete"; skipped: number };
