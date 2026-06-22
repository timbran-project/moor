# Single-Process Web Deployment

Runs the combined `moor` backend in one container with the embedded curl worker enabled, and serves
the Meadow frontend from nginx. The browser UI is exposed on port 8080 and telnet is exposed on port
8888.

```bash
cp .env.example .env
docker compose up -d
```

Then visit `http://localhost:8080`.
