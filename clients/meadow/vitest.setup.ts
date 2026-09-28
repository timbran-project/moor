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

import type {} from "vitest/jsdom";

// Use the test window's storage, independent of Node's native web-storage globals.
Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    get: () => jsdom.window.localStorage,
});

// Polyfill ResizeObserver for jsdom
global.ResizeObserver = class ResizeObserver {
    callback: ResizeObserverCallback;

    constructor(callback: ResizeObserverCallback) {
        this.callback = callback;
    }

    observe() {
        // No-op in tests
    }

    unobserve() {
        // No-op in tests
    }

    disconnect() {
        // No-op in tests
    }
};

// Mock sessionStorage
const sessionStorageMock = (() => {
    let store: Record<string, string> = {};
    return {
        getItem: (key: string) => store[key] || null,
        setItem: (key: string, value: string) => {
            store[key] = value;
        },
        removeItem: (key: string) => {
            delete store[key];
        },
        clear: () => {
            store = {};
        },
    };
})();

Object.defineProperty(window, "sessionStorage", {
    value: sessionStorageMock,
});
