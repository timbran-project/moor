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

import { describe, expect, it, vi } from "vitest";
import { decryptEventBlob, publicKeyFromIdentity } from "./age-decrypt";

vi.mock("age-encryption", () => ({
    Decrypter: class {
        addIdentity(identity: string) {
            throw new Error(`Invalid identity: ${identity}`);
        }
    },
    identityToRecipient: async (identity: string) => {
        throw new Error(`Invalid identity: ${identity}`);
    },
}));

describe("cryptographic error redaction", () => {
    it("does not propagate the private identity from a decryption error", async () => {
        await expect(decryptEventBlob(new Uint8Array(), "AGE-SECRET-KEY-sensitive"))
            .rejects.toThrow(/^Failed to decrypt event blob$/);
    });

    it("does not propagate the private identity from a public-key conversion error", async () => {
        await expect(publicKeyFromIdentity("AGE-SECRET-KEY-sensitive"))
            .rejects.toThrow(/^Failed to derive public key from identity$/);
    });
});
