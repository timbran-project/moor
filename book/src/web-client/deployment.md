# Deployment

The web client is optional, but when enabled it typically sits behind a proxy that serves static
assets and forwards API/WebSocket traffic to the embedded web host in `moor` or to `moor-web-host`
in split deployments.

## Typical Topology

```
Browser → nginx (or other proxy) → moor web host → daemon runtime
            ↓
      Static assets
      (HTML/CSS/JS)
```

1. Browser loads static web client assets (HTML/CSS/JS) from the proxy
2. The proxy forwards `/v1/`, `/auth/`, `/ws/`, and `/webhooks/` traffic to the web host
3. The web host relays RPC and event traffic to the daemon runtime

## Deployment Options

### Docker Compose (Recommended)

The simplest way to deploy is using the provided Docker Compose configurations:

```bash
# Single-process web deployment
docker compose -f deploy/single-process/web/docker-compose.yml up -d

# Clustered HTTPS with Let's Encrypt
docker compose -f deploy/clustered/web-ssl/docker-compose.yml up -d
```

### Debian Packages

For a Debian or Ubuntu web deployment, build the server and web client packages from the same
checkout of the repository, so that they match, then configure a reverse proxy such as nginx:

```bash
# From the mooR repository root
./deploy/debian-packages/build-all-packages.sh

# Install the combined server and web client
sudo dpkg -i target/debian/moor_*.deb target/debian/moor-web-client_*.deb

# Or install the split web host:
sudo dpkg -i target/debian/moor-daemon_*.deb target/debian/moor-web-host_*.deb \
    target/debian/moor-web-client_*.deb
```

Web client files are installed to `/usr/share/moor/web-client/`. Adapt the nginx configuration below
to serve that directory and proxy requests to the installed web host.

### Kubernetes

See `deploy/clustered/kubernetes/` for Ingress and Deployment manifests.

## Proxy Configuration

### Required Routes

The proxy must forward these paths to `moor-web-host`:

| Path         | Purpose                  |
| ------------ | ------------------------ |
| `/v1/`       | Versioned REST API       |
| `/auth/`     | Authentication endpoints |
| `/ws/`       | WebSocket connections    |
| `/webhooks/` | External webhook ingress |
| `/health`    | Health check             |
| `/version`   | Version info             |

All other paths serve static web client assets.

### Minimal nginx Configuration

```nginx
upstream moor_api {
    server moor-web-host:8081;
}

server {
    listen 80;
    server_name your-moo.example.com;

    # Static files
    root /var/www/moor;
    index index.html;

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API routes
    location /v1/ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /auth/ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /webhooks/ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Health and version
    location ~ ^/(health|version)$ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://moor_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;
    }
}
```

### Limiting Logins

The web host does not limit how often someone can try to log in or create an account. Do that in the
proxy. The nginx configurations under `deploy/` allow each client address 5 requests a second to
those two endpoints, with bursts of 10, and answer 429 beyond that:

```nginx
# In the http block:
limit_req_zone $binary_remote_addr zone=moor_auth:10m rate=5r/s;
limit_req_status 429;

# In the server block, before the general /auth/ location:
location ~ ^/auth/(connect|create)$ {
    limit_req zone=moor_auth burst=10 nodelay;
    proxy_pass http://moor_api;
    # ...the same proxy_set_header lines as /auth/
}
```

If another proxy sits in front of this one, set the client address first with nginx's `realip`
module. Otherwise every visitor appears to come from that proxy and shares one limit. Webhooks are
not limited either; limit them here too if they are reachable from the internet.

### HTTPS Configuration

For HTTPS, see `deploy/clustered/web-ssl/nginx-ssl.conf` for an example with:

- TLS termination
- HTTP to HTTPS redirect
- Let's Encrypt certificate renewal
- Security headers

### WebSocket Timeouts

WebSocket connections are long-lived. Configure appropriate timeouts:

```nginx
proxy_read_timeout 3600s;  # 1 hour
proxy_send_timeout 3600s;
```

## Development Setup

During development, Vite serves the web client and proxies API/WebSocket requests:

```bash
npm run full:dev
```

This starts the Vite dev server and the single-process `moor` server. The `moor` process runs the
daemon, telnet host, and web host together for local development.

Vite's proxy configuration is in `clients/meadow/vite.config.ts`.

## Environment Variables

The web client reads these at build time:

| Variable            | Default | Description                                 |
| ------------------- | ------- | ------------------------------------------- |
| `VITE_API_BASE_URL` | (empty) | Base URL for API calls (usually not needed) |

## Static Asset Hosting

The web client build produces static files in `dist/`:

- `index.html` - Main entry point
- `assets/` - JavaScript, CSS, images

These can be served from any static hosting (nginx, S3, CDN, etc.). The only requirement is
SPA-style routing: all non-asset requests should return `index.html`.

## Health Checks

For load balancers and orchestrators:

| Endpoint  | Service       | Expected Response      |
| --------- | ------------- | ---------------------- |
| `/health` | moor-web-host | 200 OK                 |
| `/`       | Static assets | 200 OK with index.html |

## Related Docs

- [Server Architecture](../the-system/server-architecture.md)
- [Running a mooR Server](../the-system/running-the-server.md)
- [Server Configuration](../the-system/server-configuration.md)

## SSE event delivery

To select SSE, add `?transport=sse` to the Meadow URL. WebSocket remains the default transport.

Delivery mode applies to each connection. Telnet and WebSocket connections keep host-owned
acknowledgement and full event delivery. Only an explicit SSE session open enables browser-owned
acknowledgement. The daemon does not require a web-host for other connection types.

The daemon retains live event payloads until the browser acknowledges them. The SSE response carries
base64-encoded FlatBuffer payloads with generation and sequence IDs. Meadow decodes and processes
each payload without a separate HTTP retrieval request. It coalesces cumulative acknowledgements
over 100 milliseconds. Acknowledgement responses do not block event delivery or commands. Idle
clients repeat their acknowledgement every 10 seconds.

The web-host does not retain a delivery backlog. Attachment, streaming, and acknowledgement requests
can reach different web-host instances connected to the same daemon. No sticky routing is required.
An open SSE response occupies one HTTP connection and holds at most one bounded daemon batch. The
browser resumes from its last processed sequence; this cursor does not acknowledge delivery.

Ephemeral data events are not retained. The SSE response carries them as `ephemeral` events with no
id, and the browser does not acknowledge them. One that arrives while a connection is down is lost.

The daemon limits retained events to 8,192 events and 16 MiB per connection, with a 256 MiB global
payload limit. Browser-owned payloads expire after five minutes. A backlog that exceeds a limit
disconnects the connection. Connections without liveness updates expire after 30 seconds, which can
shorten the reconnect window.

An expired connection or delivery gap requires a fresh session. Meadow then uses history and current
presentation snapshots for recovery. This recovery depends on the existing event-log configuration
and encryption key. Connection-specific events cannot be recovered after expiry or a daemon restart.
The stream generation prevents an old acknowledgement from removing events in a new stream.

The SSE endpoint sends `X-Accel-Buffering: no` and `Cache-Control: no-store`. The proxy must
preserve streaming responses and pass the client credential headers. Meadow uses streaming fetch
because its authentication headers do not fit the native EventSource constructor.

The [HTTP API reference](http-api-reference.md#eventdelivery) describes the session, streaming, and
acknowledgement endpoints. SSE delivery does not establish a WebRTC data channel.

## WebRTC data channels

A web client can open a WebRTC data channel beside its WebSocket. Ephemeral data events then reach
it with the lowest latency the network allows, and it can send client data on the same channel. See
[Structured Client Data](../the-moo-programming-language/client-data.md#the-data-channel) for the
protocol. WebRTC is off by default, and nothing else depends on it: without a channel, the same
events use the WebSocket.

The web host runs one WebRTC endpoint on one UDP port for every client. It answers as an ICE-lite
peer and lists its own addresses in its answer, so it needs no STUN or TURN server. Clients that
cannot reach the UDP port keep using the WebSocket.

| Setting                 | Default        | Meaning                                                                    |
| ----------------------- | -------------- | -------------------------------------------------------------------------- |
| `webrtc.enabled`        | `false`        | Accept data channel offers. `moor-web-host` also takes `--webrtc-enabled`. |
| `webrtc.udp_listen`     | `0.0.0.0:7882` | The endpoint's UDP address.                                                |
| `webrtc.advertised_ips` | none           | Addresses clients reach the endpoint on, with the endpoint's port.         |

For the combined `moor` server, these settings go under `services.web.webrtc`:

```yaml
services:
  web:
    webrtc:
      enabled: true
      udp_listen: 0.0.0.0:7882
      advertised_ips: [203.0.113.10]
```

Set `advertised_ips` whenever clients see the host on a different address from the one it listens
on, such as behind NAT or in a container. Without it, the host advertises a concrete `udp_listen`
address as it is, or, for a wildcard address, its address on the default route.

The UDP port does not pass through the HTTP proxy. Open it in the firewall, and publish it from a
container (for example `7882:7882/udp`).
