# Getting Started: Local Supabase Dev Environment

This guide walks you through spinning up a local self-hosted Supabase stack using Docker Compose.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (v24+) with Docker Compose v2
- [Git Bash](https://git-scm.com/) or WSL2 (for running shell scripts on Windows)
- (Optional) [Node.js](https://nodejs.org/) >= 16 — only needed for asymmetric key generation

Verify your setup:

```bash
docker --version        # Docker 24+
docker compose version  # Docker Compose v2+
```

## Quick Start

### 1. Navigate to the docker directory

```bash
cd infrastructure/docker
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

### 3. Generate secrets

Run the key generation script to replace all default placeholder values:

```bash
sh ./utils/generate-keys.sh --update-env
```

This generates secure values for `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `DASHBOARD_PASSWORD`, and all other secrets.

> **Tip:** For development you can skip this and use the example defaults — but never use defaults outside of local dev.

### 4. Start the stack

**Standard dev mode** (all core services):

```bash
docker compose up -d
```

**Dev mode with hot-reload Studio + email testing:**

```bash
docker compose -f docker-compose.yml -f dev/docker-compose.dev.yml up -d
```

This adds:
- **Inbucket** email server at [http://localhost:9000](http://localhost:9000) — catches all outgoing emails
- **Studio hot-reload** — rebuilds on code changes
- **Fresh database** — uses an in-memory volume (no persisted data between restarts)
- **Seed data** — loads `dev/data.sql` with sample tables and storage buckets

### 5. Verify everything is running

```bash
docker compose ps
```

All services should show `healthy` or `running`.

## Accessing Services

| Service | URL | Notes |
|---------|-----|-------|
| **Studio Dashboard** | [http://localhost:8000](http://localhost:8000) | Login: `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` from `.env` |
| **REST API** | `http://localhost:8000/rest/v1/` | Pass `apikey` header with `ANON_KEY` |
| **Auth API** | `http://localhost:8000/auth/v1/` | Authentication endpoints |
| **Realtime** | `ws://localhost:8000/realtime/v1/websocket` | WebSocket connections |
| **Storage API** | `http://localhost:8000/storage/v1/` | File upload/download |
| **Edge Functions** | `http://localhost:8000/functions/v1/<name>` | Deno runtime |
| **Inbucket (dev)** | [http://localhost:9000](http://localhost:9000) | Email inbox (only with dev compose) |
| **Postgres Meta** | `http://localhost:5555` | Only exposed in dev compose |

### Connecting to the database

Supabase exposes Postgres through **Supavisor** (connection pooler):

| Mode | Port | Use case |
|------|------|----------|
| **Session** | `5432` | Migrations, admin tasks |
| **Transaction** | `6543` | Application queries |

```bash
# Session mode (via Supavisor)
psql postgresql://postgres:[POSTGRES_PASSWORD]@localhost:5432/postgres

# Transaction mode
psql postgresql://postgres.[POOLER_TENANT_ID]:[POSTGRES_PASSWORD]@localhost:6543/postgres
```

## Using the API

### With legacy keys (default)

```bash
# List tables via REST API
curl http://localhost:8000/rest/v1/ \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}"

# Sign up a user
curl -X POST http://localhost:8000/auth/v1/signup \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "test1234"}'
```

### With opaque API keys (optional)

Generate asymmetric keys for the newer `sb_` key format:

```bash
sh ./utils/add-new-auth-keys.sh --update-env
```

Then uncomment the relevant environment variables in `docker-compose.yml` as instructed by the script output, and restart.

## Optional: S3 Storage Backend

By default, storage uses the local filesystem. To use an S3-compatible backend:

**MinIO:**

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d
```

**RustFS (alternative):**

```bash
docker compose -f docker-compose.yml -f docker-compose.rustfs.yml up -d
```

## Running Tests

Smoke tests verify the stack is working end-to-end:

```bash
# Core services test
sh ./tests/test-self-hosted.sh

# Auth and API key tests
sh ./tests/test-auth-keys.sh

# S3 backend tests (if using S3)
sh ./tests/test-s3.sh
```

## Common Tasks

### Reset everything

Stops all containers, deletes volumes and data, restores `.env` from example:

```bash
sh ./reset.sh
```

Pass `-y` to skip confirmation prompts.

### Rotate database password

```bash
sh ./utils/db-passwd.sh
```

### Rotate opaque API keys

```bash
sh ./utils/rotate-new-api-keys.sh
```

### View logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f db
docker compose logs -f auth
docker compose logs -f rest
```

### Stop the stack

```bash
# Stop (preserves data)
docker compose stop

# Stop and remove containers + volumes
docker compose down -v
```

## Architecture Overview

```
Client App
    │
    ▼
  Kong (API Gateway) :8000/:8443
    ├── /rest/v1/     → PostgREST (REST API)
    ├── /auth/v1/     → GoTrue (Auth)
    ├── /realtime/    → Realtime (WebSockets)
    ├── /storage/v1/  → Storage API → imgproxy
    └── /functions/   → Edge Runtime (Deno)
                            │
                            ▼
                    Supavisor (Pooler) :5432/:6543
                            │
                            ▼
                    PostgreSQL (DB) :5432
                            │
                            ▼
                    Vector → Logflare (Analytics)
```

**Studio** connects to Postgres via **postgres-meta** for the dashboard UI.

## Troubleshooting

**Containers keep restarting:**
Check logs with `docker compose logs <service>`. Common causes: missing env vars, port conflicts, or unhealthy dependencies.

**Port conflicts:**
Default ports: `8000` (HTTP), `8443` (HTTPS), `5432` (Postgres), `6543` (Pooler). Change them in `.env` via `KONG_HTTP_PORT`, `KONG_HTTPS_PORT`, `POSTGRES_PORT`, `POOLER_PROXY_PORT_TRANSACTION`.

**Database not accessible:**
Ensure the `db` container is healthy: `docker compose ps db`. Supavisor must also be healthy for external connections to work.

**Windows-specific: Docker socket**
If analytics/logging fail, update `DOCKER_SOCKET_LOCATION` in `.env`. On Docker Desktop for Windows, use the default `/var/run/docker.sock` (Docker Desktop handles the translation).

## Further Reading

- [Supabase Self-Hosting Docs](https://supabase.com/docs/guides/self-hosting/docker)
- [CHANGELOG.md](./CHANGELOG.md) — release history and breaking changes
- [versions.md](./versions.md) — Docker image version tracking
