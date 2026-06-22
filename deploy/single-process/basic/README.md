# Single-Process Basic Deployment

Runs the combined `moor` binary in one container with the embedded curl worker enabled. Telnet is
exposed on port 8888 and the embedded web API is exposed on port 8080.

```bash
cp .env.example .env
docker compose up -d
telnet localhost 8888
curl http://localhost:8080/version
```
