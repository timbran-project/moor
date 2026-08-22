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

// Argon2 key derivation for event log encryption
// Used to derive age keypairs from user passwords

/**
 * Derive 32 bytes from password using Argon2id KDF
 * The player OID is used as salt for domain separation: it is immutable and known to
 * both the creation and recovery paths, so (password, OID) reproduces the same key on
 * any device. Never derive with a mutable identifier such as the username.
 *
 * Same password + same identifier = same bytes (deterministic)
 */
export async function deriveKeyBytes(password: string, identifier: string): Promise<Uint8Array> {
    const saltString = `moor-event-log-v1-${identifier}`;

    // Load argon2-browser from local bundled version if not already loaded
    // @ts-expect-error - UMD module attaches to window
    if (!window.argon2) {
        // Set WASM path before loading argon2
        // @ts-expect-error - argon2WasmPath not in Window type
        window.argon2WasmPath = "/argon2.wasm";

        await new Promise<void>((resolve, reject) => {
            const script = document.createElement("script");
            script.src = "/argon2-bundled.min.js";
            script.onload = () => resolve();
            script.onerror = () => reject(new Error("Failed to load argon2-browser"));
            document.head.appendChild(script);
        });
    }

    // @ts-expect-error - UMD module attaches to window
    const argon2 = window.argon2;

    if (!argon2 || typeof argon2.hash !== "function") {
        throw new Error("argon2-browser failed to load");
    }

    const result = await argon2.hash({
        pass: password,
        salt: saltString,
        type: 2, // Argon2id
        time: 3,
        mem: 65536, // 64 MiB
        parallelism: 4,
        hashLen: 32,
    });

    return new Uint8Array(result.hash);
}

/**
 * Generate an age keypair from a password and identifier (the player OID)
 * Returns both the identity (private key) and public key
 */
export async function generateKeypairFromPassword(
    password: string,
    identifier: string,
): Promise<{ identity: string; publicKey: string }> {
    const { identityFromDerivedBytes, publicKeyFromIdentity } = await import("./age-decrypt");

    const bytes = await deriveKeyBytes(password, identifier);
    const identity = identityFromDerivedBytes(bytes);
    const publicKey = await publicKeyFromIdentity(identity);

    return { identity, publicKey };
}
