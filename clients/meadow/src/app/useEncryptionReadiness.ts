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

import { useCallback, useEffect, useState } from "react";
import { useAuthContext } from "../context/AuthContext";
import { useEncryptionContext } from "../context/EncryptionContext";
import { usePersistentState } from "../hooks/usePersistentState";

/**
 * Owns the encryption-readiness decision machine: comparing the local age
 * identity against the backend's registered pubkey and driving the
 * unlock/setup prompts accordingly, including the pending OAuth2 password
 * auto-setup path. Successful unlock or setup marks history for reload so the
 * history coordinator refetches with the new key.
 */
export const useEncryptionReadiness = (
    eventLogEnabled: boolean | null,
    markHistoryForReload: () => void,
) => {
    const { authState } = useAuthContext();
    const {
        encryptionState,
        setupEncryption,
        unlockEncryption,
        forgetKey,
    } = useEncryptionContext();

    const [showEncryptionSetup, setShowEncryptionSetup] = useState(false);
    const [showPasswordPrompt, setShowPasswordPrompt] = useState(false);
    const [userSkippedEncryption, setUserSkippedEncryption] = usePersistentState<boolean>(
        "moor-skip-encryption-setup",
        false,
    );

    // Encryption prompts are meaningless without the event log
    useEffect(() => {
        if (eventLogEnabled === false) {
            setShowEncryptionSetup(false);
            setShowPasswordPrompt(false);
        }
    }, [eventLogEnabled]);

    // Check encryption setup after login
    useEffect(() => {
        if (eventLogEnabled === false) {
            return;
        }

        // Wait until we've checked the backend at least once before making decisions
        // Otherwise we briefly show setup prompt before knowing actual backend state
        if (
            authState.player
            && !encryptionState.isChecking
            && encryptionState.hasCheckedOnce
            && !encryptionState.statusError
            && !userSkippedEncryption
        ) {
            const hasLocalKey = !!encryptionState.ageIdentity;
            const backendHasPubkey = encryptionState.hasEncryption;

            // Check for pending encryption password from OAuth2 flow
            const pendingEncryptPassword = sessionStorage.getItem("pending_encrypt_password");

            // If no local key but backend has pubkey, prompt for existing password (NOT setup!)
            if (!hasLocalKey && backendHasPubkey) {
                console.log("Backend has pubkey but no local key - prompting for existing password");
                if (!showPasswordPrompt) {
                    setShowPasswordPrompt(true);
                }
                // Make sure setup screen is NOT showing
                if (showEncryptionSetup) {
                    setShowEncryptionSetup(false);
                }
            } // If no local key and backend has no pubkey, check for pending password or prompt for new setup
            else if (!hasLocalKey && !backendHasPubkey) {
                // If we have a pending encryption password from OAuth2, auto-setup
                if (pendingEncryptPassword) {
                    console.log("Auto-setting up encryption with pending OAuth2 password");
                    sessionStorage.removeItem("pending_encrypt_password");
                    setupEncryption(pendingEncryptPassword).catch((err) => {
                        console.error("Failed to auto-setup encryption:", err);
                        // Fall back to showing setup prompt
                        setShowEncryptionSetup(true);
                    });
                } else {
                    console.log("No encryption key anywhere - prompting for new setup");
                    if (!showEncryptionSetup) {
                        setShowEncryptionSetup(true);
                    }
                    // Make sure password prompt is NOT showing
                    if (showPasswordPrompt) {
                        setShowPasswordPrompt(false);
                    }
                }
            } // If we have a local key but backend doesn't have our pubkey (DB was reset), clear and re-prompt
            else if (hasLocalKey && !backendHasPubkey) {
                console.log(
                    "Backend missing pubkey but localStorage has key - clearing stale key and prompting for fresh setup",
                );
                forgetKey();
                setUserSkippedEncryption(false);
                setShowEncryptionSetup(true);
                setShowPasswordPrompt(false);
            } // If we have both local key and backend has pubkey, we're good - hide prompts
            else if (hasLocalKey && backendHasPubkey) {
                setShowEncryptionSetup(false);
                setShowPasswordPrompt(false);
            }
        }
    }, [
        authState.player,
        encryptionState.hasEncryption,
        encryptionState.ageIdentity,
        encryptionState.isChecking,
        encryptionState.hasCheckedOnce,
        encryptionState.statusError,
        showEncryptionSetup,
        showPasswordPrompt,
        forgetKey,
        setUserSkippedEncryption,
        userSkippedEncryption,
        eventLogEnabled,
        setupEncryption,
    ]);

    const handleUnlock = useCallback(async (password: string) => {
        const result = await unlockEncryption(password);
        if (result.success) {
            setShowPasswordPrompt(false);
            setUserSkippedEncryption(false);
            markHistoryForReload();
        }
        return result;
    }, [markHistoryForReload, setUserSkippedEncryption, unlockEncryption]);

    // Reached via "forgot password" (after EncryptionResetConfirm) or a fresh account;
    // allow the registered key to be replaced in both cases.
    const handleSetup = useCallback(async (password: string) => {
        const result = await setupEncryption(password, { allowRekey: true });
        if (result.success) {
            setShowEncryptionSetup(false);
            setUserSkippedEncryption(false);
            markHistoryForReload();
        }
        return result;
    }, [markHistoryForReload, setUserSkippedEncryption, setupEncryption]);

    const handleForgotPassword = useCallback(() => {
        setShowPasswordPrompt(false);
        setShowEncryptionSetup(true);
    }, []);

    const skipUnlock = useCallback(() => {
        setShowPasswordPrompt(false);
        setUserSkippedEncryption(true);
    }, [setUserSkippedEncryption]);

    const skipSetup = useCallback(() => {
        setShowEncryptionSetup(false);
        setUserSkippedEncryption(true);
    }, [setUserSkippedEncryption]);

    /** Clears prompt/skip state after an identity change or logout. */
    const resetForIdentityChange = useCallback(() => {
        setShowEncryptionSetup(false);
        setShowPasswordPrompt(false);
        setUserSkippedEncryption(false);
    }, [setUserSkippedEncryption]);

    return {
        showEncryptionSetup,
        showPasswordPrompt,
        handleUnlock,
        handleSetup,
        handleForgotPassword,
        skipUnlock,
        skipSetup,
        resetForIdentityChange,
    };
};
