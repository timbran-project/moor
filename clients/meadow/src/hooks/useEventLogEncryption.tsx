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

// ! Hook for managing event log encryption (Argon2 key derivation + age keypair generation)
// ! Age keypairs are derived deterministically from (password, player OID); only the
// ! public key is sent to the server. Unlock and setup validate the derived public key
// ! against the registered key before storing anything or reporting success.

import { useCallback, useEffect, useState } from "react";
import { identityFromDerivedBytes, publicKeyFromIdentity } from "../lib/age-decrypt";
import { buildAuthHeaders } from "../lib/authHeaders";
import { deriveKeyBytes } from "../lib/keyDerivation";

interface EncryptionState {
    playerOid: string | null;
    hasEncryption: boolean;
    isChecking: boolean;
    hasCheckedOnce: boolean; // Track if we've checked at least once
    ageIdentity: string | null; // AGE-SECRET-KEY-1... private key string
    statusError: string | null;
}

function initialEncryptionState(playerOid: string | null): EncryptionState {
    const ageIdentity = playerOid
        ? localStorage.getItem(`moor_event_log_identity_${playerOid}`)
        : null;
    return {
        playerOid,
        hasEncryption: false,
        isChecking: false,
        hasCheckedOnce: false,
        ageIdentity,
        statusError: null,
    };
}

/// Fetch the age public key registered with the server for the authenticated player,
/// or null when the player has no event-log encryption registered.
async function fetchRegisteredPublicKey(authToken: string): Promise<string | null> {
    const response = await fetch("/v1/event-log/pubkey", {
        headers: buildAuthHeaders(authToken),
    });
    if (!response.ok) {
        throw new Error(`Unable to check encryption status (${response.status})`);
    }
    const data = await response.json();
    return data.public_key ?? null;
}

/// Persist the derived age identity locally, keyed by player OID. The server never
/// receives the private identity.
function storeIdentity(playerOid: string, identity: string): void {
    localStorage.setItem(`moor_event_log_identity_${playerOid}`, identity);
}

export const useEventLogEncryption = (
    authToken: string | null,
    playerOid: string | null,
) => {
    const [encryptionState, setEncryptionState] = useState<EncryptionState>(() => initialEncryptionState(playerOid));
    const scopedEncryptionState = encryptionState.playerOid === playerOid
        ? encryptionState
        : initialEncryptionState(playerOid);

    useEffect(() => {
        setEncryptionState(initialEncryptionState(playerOid));
    }, [playerOid]);

    const checkEncryptionStatus = useCallback(async () => {
        if (!authToken || !playerOid) return;

        setEncryptionState({
            ...initialEncryptionState(playerOid),
            isChecking: true,
        });

        try {
            const headers = buildAuthHeaders(authToken);
            const response = await fetch("/v1/event-log/pubkey", {
                headers,
            });

            if (!response.ok) {
                console.error("Failed to check encryption status:", response.status);
                setEncryptionState(prev => ({
                    ...prev,
                    playerOid,
                    isChecking: false,
                    hasCheckedOnce: true,
                    statusError: `Encryption status request failed with status ${response.status}`,
                }));
                return;
            }

            const data = await response.json();
            const hasEncryption = !!data.public_key;

            const storageKey = `moor_event_log_identity_${playerOid}`;
            const savedIdentity = localStorage.getItem(storageKey);

            setEncryptionState({
                playerOid,
                hasEncryption,
                isChecking: false,
                hasCheckedOnce: true,
                ageIdentity: savedIdentity,
                statusError: null,
            });
        } catch (error) {
            console.error("Error checking encryption status:", error);
            setEncryptionState(prev => ({
                ...prev,
                playerOid,
                isChecking: false,
                hasCheckedOnce: true,
                statusError: error instanceof Error
                    ? error.message
                    : "Unable to check encryption status",
            }));
        }
    }, [authToken, playerOid]);

    const setupEncryption = useCallback(async (
        password: string,
        options?: { allowRekey?: boolean },
    ): Promise<{ success: boolean; error?: string }> => {
        if (!authToken || !playerOid) {
            return { success: false, error: "Not authenticated" };
        }

        try {
            const registeredPublicKey = await fetchRegisteredPublicKey(authToken);

            const bytes = await deriveKeyBytes(password, playerOid);
            const identity = identityFromDerivedBytes(bytes);
            const publicKey = await publicKeyFromIdentity(identity);

            // A key is already registered: only overwrite it when the caller explicitly
            // requested a reset. Otherwise this is a validate-and-restore operation.
            if (registeredPublicKey && !options?.allowRekey) {
                if (publicKey !== registeredPublicKey) {
                    return { success: false, error: "Incorrect encryption password" };
                }
                storeIdentity(playerOid, identity);

                setEncryptionState({
                    playerOid,
                    hasEncryption: true,
                    isChecking: false,
                    hasCheckedOnce: true,
                    ageIdentity: identity,
                    statusError: null,
                });
                return { success: true };
            }

            const headers = buildAuthHeaders(authToken);
            headers["Content-Type"] = "application/json";
            const response = await fetch("/v1/event-log/pubkey", {
                method: "PUT",
                headers,
                body: JSON.stringify({ public_key: publicKey }),
            });

            if (!response.ok) {
                const errorText = await response.text();
                console.error("Pubkey setup failed:", errorText);
                return { success: false, error: `Server error: ${response.status}` };
            }

            storeIdentity(playerOid, identity);

            setEncryptionState({
                playerOid,
                hasEncryption: true,
                isChecking: false,
                hasCheckedOnce: true,
                ageIdentity: identity,
                statusError: null,
            });

            return { success: true };
        } catch (error) {
            console.error("Encryption setup failed:", error);
            return { success: false, error: error instanceof Error ? error.message : "Unknown error" };
        }
    }, [authToken, playerOid]);

    const unlockEncryption = useCallback(async (password: string): Promise<{ success: boolean; error?: string }> => {
        if (!authToken || !playerOid) {
            return { success: false, error: "Not authenticated" };
        }

        try {
            const registeredPublicKey = await fetchRegisteredPublicKey(authToken);
            if (!registeredPublicKey) {
                return { success: false, error: "Encryption is not set up for this account" };
            }

            const bytes = await deriveKeyBytes(password, playerOid);
            const identity = identityFromDerivedBytes(bytes);
            const publicKey = await publicKeyFromIdentity(identity);

            if (publicKey !== registeredPublicKey) {
                return { success: false, error: "Incorrect encryption password" };
            }

            storeIdentity(playerOid, identity);

            setEncryptionState(prev => ({
                ...prev,
                playerOid,
                ageIdentity: identity,
            }));

            return { success: true };
        } catch (error) {
            console.error("Failed to unlock encryption:", error);
            return { success: false, error: error instanceof Error ? error.message : "Unknown error" };
        }
    }, [authToken, playerOid]);

    const forgetKey = useCallback(() => {
        if (!playerOid) return;

        const storageKey = `moor_event_log_identity_${playerOid}`;
        localStorage.removeItem(storageKey);

        setEncryptionState(prev => ({
            ...prev,
            playerOid,
            ageIdentity: null,
        }));
    }, [playerOid]);

    const getKeyForHistoryRequest = useCallback((): string | null => {
        return scopedEncryptionState.ageIdentity;
    }, [scopedEncryptionState.ageIdentity]);

    return {
        encryptionState: scopedEncryptionState,
        checkEncryptionStatus,
        setupEncryption,
        unlockEncryption,
        forgetKey,
        getKeyForHistoryRequest,
    };
};
