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

import { useCallback, useEffect, useRef, useState } from "react";
import { exchangeAuthCode, OAuth2UserInfo } from "../lib/oauth2";
import type { EstablishSession } from "./useAuth";

export interface OAuth2AccountChoice {
    mode: "oauth2_create" | "oauth2_connect";
    oauth2_code: string;
    player_name?: string;
    existing_email?: string;
    existing_password?: string;
    encrypt_password?: string;
}

interface OAuth2AccountResult {
    success: boolean;
    auth_token?: string;
    player?: string;
    player_flags?: number;
    client_token?: string;
    client_id?: string;
    error?: string;
}

type ShowMessage = (message: string, duration?: number) => void;

export function useOAuth2Session(establishSession: EstablishSession, showMessage: ShowMessage) {
    const [oauth2UserInfo, setOAuth2UserInfo] = useState<OAuth2UserInfo | null>(null);
    const accountRequest = useRef<AbortController | null>(null);

    const clearOAuth2UserInfo = useCallback(() => {
        accountRequest.current?.abort();
        accountRequest.current = null;
        setOAuth2UserInfo(null);
    }, []);

    useEffect(() => () => {
        accountRequest.current?.abort();
        accountRequest.current = null;
    }, []);

    useEffect(() => {
        const hashParams = new URLSearchParams(
            window.location.hash.startsWith("#")
                ? window.location.hash.slice(1)
                : window.location.hash,
        );
        const urlParams = new URLSearchParams(window.location.search);

        const clearOAuthHandoffParams = () => {
            const url = new URL(window.location.href);
            url.hash = "";
            url.searchParams.delete("oauth2_code");
            url.searchParams.delete("oauth2_display");
            url.searchParams.delete("auth_code");
            window.history.replaceState({}, document.title, `${url.pathname}${url.search}`);
        };

        const oauth2Code = hashParams.get("oauth2_code") ?? urlParams.get("oauth2_code");
        const oauth2Display = hashParams.get("oauth2_display") ?? urlParams.get("oauth2_display");
        if (oauth2Code) {
            clearOAuthHandoffParams();
            try {
                let display: { provider?: string; email?: string; name?: string; username?: string } = {};
                if (oauth2Display) {
                    try {
                        display = JSON.parse(oauth2Display);
                    } catch {
                        display = JSON.parse(decodeURIComponent(oauth2Display));
                    }
                }
                setOAuth2UserInfo({
                    provider: display.provider || "",
                    email: display.email,
                    name: display.name,
                    username: display.username,
                    oauth2_code: oauth2Code,
                });
                showMessage("OAuth2 login successful! Please choose how to proceed.", 5);
            } catch (error) {
                console.error("Failed to parse OAuth2 display info:", error);
                showMessage("OAuth2 callback error. Please try again.", 5);
            }
        }

        const authCode = hashParams.get("auth_code") ?? urlParams.get("auth_code");
        if (authCode) {
            clearOAuthHandoffParams();
            void exchangeAuthCode(authCode)
                .then((result) => {
                    establishSession({
                        authToken: result.auth_token,
                        playerOid: result.player,
                        historyAuthToken: result.auth_token,
                        historyPlayerOid: result.player,
                        playerFlags: result.player_flags,
                        reconnectCredentials: {
                            clientToken: result.client_token,
                            clientId: result.client_id,
                        },
                    });
                    showMessage("Logged in successfully via OAuth2!", 2);
                })
                .catch((error) => {
                    console.error("Auth code exchange failed:", error);
                    showMessage(
                        `OAuth2 login failed: ${error instanceof Error ? error.message : String(error)}`,
                        5,
                    );
                });
        }

        const error = urlParams.get("error");
        if (error) {
            const details = urlParams.get("details");
            showMessage(`OAuth2 error: ${error}${details ? ` - ${details}` : ""}`, 5);
            window.history.replaceState({}, document.title, window.location.pathname);
        }
    }, [establishSession, showMessage]);

    const handleOAuth2AccountChoice = useCallback(async (choice: OAuth2AccountChoice) => {
        accountRequest.current?.abort();
        const request = new AbortController();
        accountRequest.current = request;
        try {
            const response = await fetch("/auth/oauth2/account", {
                method: "POST",
                signal: request.signal,
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    mode: choice.mode,
                    oauth2_code: choice.oauth2_code,
                    player_name: choice.player_name,
                    existing_email: choice.existing_email,
                    existing_password: choice.existing_password,
                }),
            });

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({ error: "Unknown error" })) as { error?: string };
                if (accountRequest.current !== request) return;
                showMessage(`Failed: ${errorData.error || response.statusText}`, 5);
                return;
            }

            const result = await response.json() as OAuth2AccountResult;
            if (accountRequest.current !== request) return;
            if (!result.success || !result.auth_token || !result.player) {
                showMessage(result.error || "Failed to complete account setup. Please try again.", 5);
                return;
            }

            setOAuth2UserInfo(null);

            establishSession({
                authToken: result.auth_token,
                playerOid: result.player,
                historyAuthToken: result.auth_token,
                historyPlayerOid: result.player,
                playerFlags: result.player_flags ?? 0,
                reconnectCredentials: result.client_token && result.client_id
                    ? {
                        clientToken: result.client_token,
                        clientId: result.client_id,
                    }
                    : null,
            }, { encryptionPassword: choice.encrypt_password });
            showMessage(`Account ${choice.mode === "oauth2_create" ? "created" : "linked"}! Connecting...`, 2);
        } catch {
            if (accountRequest.current !== request) return;
            console.error("OAuth2 account choice failed");
            showMessage("Failed to complete account setup. Please try again.", 5);
        } finally {
            if (accountRequest.current === request) accountRequest.current = null;
        }
    }, [establishSession, showMessage]);

    return {
        oauth2UserInfo,
        clearOAuth2UserInfo,
        handleOAuth2AccountChoice,
    };
}
