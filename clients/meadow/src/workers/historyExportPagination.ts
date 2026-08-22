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

export function advanceHistoryExportCursor(
    previousCursor: string | undefined,
    candidateCursor: string | undefined,
): string {
    if (!candidateCursor) {
        throw new Error("History export cannot continue because the next page cursor is missing");
    }
    if (candidateCursor === previousCursor) {
        throw new Error("History export cannot continue because the page cursor did not advance");
    }
    return candidateCursor;
}
