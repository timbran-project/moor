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

/**
 * OAuth2 authentication client functions
 */

export interface OAuth2AuthUrlResponse {
    auth_url: string;
    state: string;
}

/**
 * Display-only user info from the OAuth2 provider, shown in the account choice UI.
 * The actual verified identity is carried in the opaque server-side `oauth2_code`.
 */
export interface OAuth2UserInfo {
    provider: string;
    email?: string;
    name?: string;
    username?: string;
    /** One-time server-side code that resolves to the verified provider identity. */
    oauth2_code: string;
}

export interface OAuth2LoginResponse {
    success: boolean;
    auth_token?: string;
    player?: string;
    player_flags?: number;
    client_token?: string;
    client_id?: string;
    error?: string;
}

export interface OAuth2ConfigResponse {
    enabled: boolean;
    providers: string[];
}

/** Response from the auth code exchange endpoint (existing user flow) */
export interface AuthCodeExchangeResponse {
    auth_token: string;
    player: string;
    player_flags: number;
    client_token: string;
    client_id: string;
}

/**
 * Get OAuth2 configuration from the server
 */
export async function getOAuth2Config(): Promise<OAuth2ConfigResponse> {
    const response = await fetch("/v1/oauth2/config");

    if (!response.ok) {
        throw new Error(`Failed to get OAuth2 config: ${response.statusText}`);
    }

    return await response.json();
}

/**
 * Get the OAuth2 authorization URL for a provider
 */
export async function getOAuth2AuthUrl(provider: string): Promise<OAuth2AuthUrlResponse> {
    const response = await fetch(`/auth/oauth2/${provider}/authorize`);

    if (!response.ok) {
        throw new Error(`Failed to get OAuth2 auth URL: ${response.statusText}`);
    }

    return await response.json();
}

/**
 * Complete OAuth2 account creation or linking.
 * Sends the one-time server-side code (from the callback redirect) rather than raw identity fields.
 */
export async function completeOAuth2Login(
    mode: "oauth2_create" | "oauth2_connect",
    oauth2Code: string,
    playerName?: string,
    existingEmail?: string,
    existingPassword?: string,
): Promise<OAuth2LoginResponse> {
    const response = await fetch("/auth/oauth2/account", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            mode,
            oauth2_code: oauth2Code,
            player_name: playerName,
            existing_email: existingEmail,
            existing_password: existingPassword,
        }),
    });

    if (!response.ok) {
        throw new Error(`OAuth2 login failed: ${response.statusText}`);
    }

    return await response.json();
}

/**
 * Exchange a short-lived auth code for auth tokens (existing user OAuth2 flow).
 * The auth code was received via redirect URL and is single-use with ~60s TTL.
 */
export async function exchangeAuthCode(code: string): Promise<AuthCodeExchangeResponse> {
    const response = await fetch("/auth/oauth2/exchange", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ code }),
    });

    if (!response.ok) {
        const errorData = await response.json().catch(() => ({ error: "Unknown error" }));
        throw new Error(errorData.error || `Auth code exchange failed: ${response.statusText}`);
    }

    return await response.json();
}

/**
 * Start OAuth2 login flow by redirecting to provider
 */
export async function startOAuth2Login(provider: string, intent: "connect" | "create"): Promise<void> {
    const { auth_url, state } = await getOAuth2AuthUrl(provider);

    // Store state in sessionStorage for CSRF verification
    sessionStorage.setItem("oauth2_state", state);
    sessionStorage.setItem("oauth2_provider", provider);
    sessionStorage.setItem("oauth2_intent", intent);

    // Redirect to OAuth2 provider
    window.location.href = auth_url;
}

/**
 * Complete OAuth2 account choice (create or link).
 * The oauth2_code carries the server-verified identity.
 */
export async function oauth2AccountChoice(choice: {
    mode: "oauth2_create" | "oauth2_connect";
    oauth2_code: string;
    player_name?: string;
    existing_email?: string;
    existing_password?: string;
}): Promise<OAuth2LoginResponse> {
    return await completeOAuth2Login(
        choice.mode,
        choice.oauth2_code,
        choice.player_name,
        choice.existing_email,
        choice.existing_password,
    );
}
