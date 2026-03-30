# License Forge

## Prerequisites

- [Node.js](https://nodejs.org/) 20+
- [Yarn](https://yarnpkg.com/) (`npm install -g yarn`)
- [Docker Desktop](https://www.docker.com/) with Compose v2
- [Git Bash](https://git-scm.com/) or WSL2 (for utility scripts on Windows)

## Getting started

### 1. Install dependencies

```bash
yarn install
```

### 2. Start the Supabase backend

```bash
cd infrastructure/docker
cp .env.example .env
bash ./utils/generate-keys.sh --update-env
docker compose up -d
```

Wait until all services are healthy (~30s on first run):

```bash
docker compose ps
```

### 3. Start the frontend

```bash
cd web
yarn dev
```

The app is now running at **http://localhost:5173**.

## Services

| Service | URL | Notes |
|---|---|---|
| Web app | http://localhost:5173 | Vite dev server with HMR |
| Supabase API | http://localhost:8000 | Kong gateway — all API calls route through here |
| Supabase Studio | http://localhost:8000 | Dashboard UI (basic auth — use Firefox for best results) |
| Postgres | localhost:5432 | Session-mode pooling via Supavisor |
| Postgres (transaction) | localhost:6543 | Transaction-mode pooling via Supavisor |

> **Note:** Studio is served through Kong with basic auth. Chrome may not propagate credentials to static asset requests — use Firefox, or see the [Docker getting started guide](infrastructure/docker/GETTING_STARTED.md) for workarounds.

## Repository structure

```
license-forge/
├── web/                          # Vue 3 + TypeScript frontend (Vite)
├── packages/
│   └── ui/                       # Shared Vue component library (@syvora/ui)
├── supabase/
│   ├── kong.yml                  # Kong API gateway routing config
│   ├── migrations/               # SQL migrations (run on DB startup)
│   └── functions/                # Deno edge functions
├── infrastructure/
│   └── docker/                   # Self-hosted Supabase stack
│       ├── docker-compose.yml    # Core services (13 containers)
│       ├── docker-compose.s3.yml # Optional MinIO S3 backend
│       ├── dev/                  # Dev overrides (hot-reload, Inbucket, seed data)
│       ├── utils/                # Key generation, password rotation scripts
│       ├── tests/                # End-to-end smoke tests
│       └── GETTING_STARTED.md   # Full dev environment guide
├── deployments/                  # Production deployment configs
└── docs/                         # Documentation
```

## Docker infrastructure

All backend services live in `infrastructure/docker/`. The stack runs a complete self-hosted Supabase platform:

**Core services:** PostgreSQL, PostgREST (REST API), GoTrue (Auth), Realtime (WebSockets), Storage, Edge Functions (Deno), Kong (API gateway), Studio (Dashboard), Supavisor (connection pooler), Logflare (analytics), Vector (log aggregation), imgproxy.

**Compose overlays** can be combined with the base `docker-compose.yml`:

| Overlay | Purpose |
|---|---|
| `dev/docker-compose.dev.yml` | Hot-reload Studio, Inbucket email, fresh DB with seed data |
| `docker-compose.s3.yml` | MinIO S3 storage backend |
| `docker-compose.rustfs.yml` | RustFS S3 storage backend (alternative to MinIO) |
| `docker-compose.caddy.yml` | Caddy reverse proxy with automatic HTTPS |
| `docker-compose.nginx.yml` | Nginx reverse proxy with Let's Encrypt |

**Utility scripts** in `infrastructure/docker/utils/`:

| Script | Purpose |
|---|---|
| `generate-keys.sh` | Generate all secrets for a fresh install |
| `add-new-auth-keys.sh` | Generate asymmetric (ES256) keys and opaque API keys |
| `db-passwd.sh` | Rotate database passwords for all system roles |
| `rotate-new-api-keys.sh` | Rotate opaque API keys without touching JWT keys |

**Full details:** See [`infrastructure/docker/GETTING_STARTED.md`](infrastructure/docker/GETTING_STARTED.md) for the complete dev environment guide including API usage, database access, testing, and troubleshooting.

## Common tasks

**Reset the local Supabase stack**

```bash
cd infrastructure/docker
bash ./reset.sh
docker compose up -d
```

**Run smoke tests**

```bash
cd infrastructure/docker
bash ./tests/test-self-hosted.sh
```

**Add a database migration**

Drop a `.sql` file into `supabase/migrations/`. Files are executed in alphabetical order on container start.

**Add an edge function**

Create a new directory under `supabase/functions/` — it is mounted live into the edge runtime container.

**Run type-checking**

```bash
cd web && yarn vue-tsc -b --noEmit
```

## Monorepo workspaces

This repo uses Yarn workspaces. Run commands from the root to target all packages, or `cd` into a workspace first:

```bash
yarn workspace web add <package>          # add dep to web app
yarn workspace @syvora/ui add <package>   # add dep to UI library
```
