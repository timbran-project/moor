// Server URL configuration for Tauri desktop mode.
// When running in a browser, the server URL is empty (relative URLs work via same-origin or proxy).
// When running in Tauri with --server <url>, all fetch/WebSocket calls are prefixed with that URL.
//
// CORS is handled transparently by tauri-plugin-cors-fetch which hooks window.fetch
// and routes cross-origin requests through Tauri's HTTP client (Rust-side, no CORS).

let serverBaseUrl = "";

/** Race a promise against a timeout. */
function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
    return Promise.race([
        promise,
        new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)),
    ]);
}

/**
 * Initialize the server URL. Call once at app startup.
 * In Tauri, queries the Rust backend for the --server CLI arg.
 * In browser, this is a no-op (empty string = relative URLs).
 */
export async function initServerConfig(): Promise<void> {
    if (!window.__TAURI_INTERNALS__) return;

    try {
        const { invoke } = await withTimeout(
            import("@tauri-apps/api/core"),
            3000,
            "Tauri API import",
        );
        const url = await withTimeout(
            invoke<string>("get_server_url"),
            3000,
            "get_server_url invoke",
        );
        if (url) {
            serverBaseUrl = url;
            console.log(`[serverConfig] Using server: ${serverBaseUrl}`);
        }
    } catch (e) {
        console.warn("[serverConfig] Failed to get server URL from Tauri:", e);
    }
}

/** Returns the configured server base URL (empty string in browser mode). */
export function getServerBaseUrl(): string {
    return serverBaseUrl;
}

/**
 * Get the WebSocket base URL.
 * In Tauri with --server, derives ws(s):// from the server URL.
 * In browser, uses window.location as before.
 */
export function getWebSocketBaseUrl(): { host: string; secure: boolean } {
    if (serverBaseUrl) {
        try {
            const url = new URL(serverBaseUrl);
            return {
                host: url.host,
                secure: url.protocol === "https:",
            };
        } catch {
            // fall through to default
        }
    }
    return {
        host: window.location.host,
        secure: window.location.protocol === "https:",
    };
}

/**
 * Install a global fetch interceptor that rewrites relative URLs to point
 * at the configured server. CORS bypass is handled by tauri-plugin-cors-fetch.
 * Call once at startup after initServerConfig().
 */
export async function installFetchInterceptor(): Promise<void> {
    if (!serverBaseUrl) return;

    const originalFetch = window.fetch.bind(window);

    window.fetch = function(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
        if (typeof input === "string" && input.startsWith("/")) {
            input = `${serverBaseUrl}${input}`;
        } else if (input instanceof URL && input.origin === window.location.origin) {
            input = new URL(`${serverBaseUrl}${input.pathname}${input.search}`);
        } else if (input instanceof Request && input.url.startsWith(window.location.origin + "/")) {
            const newUrl = input.url.replace(window.location.origin, serverBaseUrl);
            input = new Request(newUrl, input);
        }
        return originalFetch(input, init);
    };

    console.log("[serverConfig] URL rewrite interceptor installed");
}
