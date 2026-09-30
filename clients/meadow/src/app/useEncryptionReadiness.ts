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

import { useCallback, useEffect, useRef, useState } from "react";
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
    const { authState, takePendingEncryptionPassword } = useAuthContext();
    const player = authState.player;
    const autoSetupRequest = useRef<AbortController | null>(null);
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

    // An old setup result must not change prompts or reload another session's history.
    useEffect(() => () => {
        autoSetupRequest.current?.abort();
        autoSetupRequest.current = null;
    }, [player?.authToken, player?.historyOid]);

    useEffect(() => {
        if (!player || eventLogEnabled === null) return;

        if (eventLogEnabled === false || userSkippedEncryption || encryptionState.statusError) {
            takePendingEncryptionPassword(player.authToken, player.historyOid);
            autoSetupRequest.current?.abort();
            autoSetupRequest.current = null;
            if (eventLogEnabled === false) {
                setShowEncryptionSetup(false);
                setShowPasswordPrompt(false);
            }
            return;
        }

        if (encryptionState.isChecking || !encryptionState.hasCheckedOnce || autoSetupRequest.current) return;

        const hasLocalKey = !!encryptionState.ageIdentity;
        const backendHasPubkey = encryptionState.hasEncryption;
        // Consume once, including when a registered/local key makes automatic setup unnecessary.
        const pendingPassword = takePendingEncryptionPassword(player.authToken, player.historyOid);

        if (!hasLocalKey && backendHasPubkey) {
            setShowPasswordPrompt(true);
            setShowEncryptionSetup(false);
            return;
        }

        if (!hasLocalKey && !backendHasPubkey) {
            setShowPasswordPrompt(false);
            if (!pendingPassword) {
                setShowEncryptionSetup(true);
                return;
            }

            const request = new AbortController();
            autoSetupRequest.current = request;
            setShowEncryptionSetup(false);
            void setupEncryption(pendingPassword, { signal: request.signal }).then(result => {
                if (autoSetupRequest.current !== request) return;
                autoSetupRequest.current = null;
                if (!result.success) {
                    setShowEncryptionSetup(true);
                    return;
                }
                setShowEncryptionSetup(false);
                setUserSkippedEncryption(false);
                markHistoryForReload();
            }).catch(() => {
                if (autoSetupRequest.current !== request) return;
                autoSetupRequest.current = null;
                console.error("Failed to auto-setup encryption");
                setShowEncryptionSetup(true);
            });
            return;
        }

        if (hasLocalKey && !backendHasPubkey) {
            forgetKey();
            setUserSkippedEncryption(false);
            setShowEncryptionSetup(true);
            setShowPasswordPrompt(false);
            return;
        }

        setShowEncryptionSetup(false);
        setShowPasswordPrompt(false);
    }, [
        player,
        encryptionState.hasEncryption,
        encryptionState.ageIdentity,
        encryptionState.isChecking,
        encryptionState.hasCheckedOnce,
        encryptionState.statusError,
        forgetKey,
        setUserSkippedEncryption,
        userSkippedEncryption,
        eventLogEnabled,
        setupEncryption,
        takePendingEncryptionPassword,
        markHistoryForReload,
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
