// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

// Vite dev server config that:
// - Proxies mooR HTTP/WS endpoints to the backend (default localhost:8080)
// - Proxies everything else to the Flutter web-server (default localhost:9010)
//
// This keeps the Flutter app same-origin with the API (no CORS issues in dev).

const apiTarget = process.env.MOOR_API_URL || "http://localhost:8080";
const wsTarget = process.env.MOOR_WS_URL || "ws://localhost:8080";
const flutterTarget = process.env.FLUTTER_WEB_TARGET || "http://localhost:9010";

export default {
  server: {
    port: 3001,
    // Avoid stale bootstrap/main.dart.js caching during rapid rebuild/reload.
    headers: {
      "Cache-Control": "no-store",
    },
    proxy: {
      "/v1": apiTarget,
      "/auth": apiTarget,
      "/health": apiTarget,
      "/version": apiTarget,
      "/webhooks": apiTarget,
      "/ws": {
        target: wsTarget,
        ws: true,
      },
      // Proxy everything else (Flutter app + assets) to the Flutter web-server.
      "^/(?!v1/|v1$|auth/|auth$|health/|health$|version/|version$|webhooks/|webhooks$|ws/|ws$).*":
        {
          target: flutterTarget,
          changeOrigin: true,
        },
    },
  },
};
