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
2. The proxy forwards `/api`, `/auth`, `/fb`, and `/ws` traffic to the web host
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

For Debian/Ubuntu systems, install the packages and configure a reverse proxy (the examples use
nginx):

```bash
# Install from APT repository (recommended)
sudo apt install moor-daemon moor-web-host moor-web-client

# Or install from downloaded .deb files
sudo dpkg -i moor_*.deb moor-web-client_*.deb

# Or install the split web host:
sudo dpkg -i moor-daemon_*.deb moor-web-host_*.deb moor-web-client_*.deb

# Configure nginx (copy from deploy/debian-packages/)
sudo cp nginx-for-debian.conf /etc/nginx/sites-available/moor
sudo ln -s /etc/nginx/sites-available/moor /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Web client files are installed to `/usr/share/moor/web-client/`.

### Kubernetes

See `deploy/clustered/kubernetes/` for Ingress and Deployment manifests.

## Proxy Configuration

### Required Routes

The proxy must forward these paths to `moor-web-host`:

| Path     | Purpose                  |
| -------- | ------------------------ |
| `/api/`  | REST API endpoints       |
| `/auth/` | Authentication endpoints |
| `/fb/`   | FlatBuffer RPC endpoints |
| `/ws/`   | WebSocket connections    |

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
    location /api/ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /auth/ {
        proxy_pass http://moor_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /fb/ {
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

Vite's proxy configuration is in `vite.config.ts`.

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
