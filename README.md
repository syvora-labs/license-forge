# License Forge

## Prerequisites

- [Node.js](https://nodejs.org/) 20+
- [Yarn](https://yarnpkg.com/) (`npm install -g yarn`)
- [Docker](https://www.docker.com/) with Compose v2

## Getting started

### 1. Install dependencies

```bash
yarn install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Open `.env` and update at minimum:

| Variable | What to set |
|---|---|
| `JWT_SECRET` | Run `openssl rand -base64 32` and paste the output |
| `ANON_KEY` | Generate at https://supabase.com/docs/guides/self-hosting#api-keys |
| `SERVICE_ROLE_KEY` | Generate alongside `ANON_KEY` (same tool) |
| `POSTGRES_PASSWORD` | Any strong password |
| `DASHBOARD_PASSWORD` | Any strong password |

The placeholder tokens in `.env.example` work for local dev but must be replaced before deploying.

### 3. Start the backend

```bash
docker compose up -d
```

Wait until all services are healthy — this takes ~30 seconds on first run while images are pulled:

```bash
docker compose ps   # all should show "running (healthy)" or "running"
```

### 4. Start the frontend

```bash
cd web
yarn dev
```

The app is now running at **http://localhost:5173**.

## Services

| Service | URL | Notes |
|---|---|---|
| Web app | http://localhost:5173 | Vite dev server with HMR |
| Supabase API | http://localhost:8000 | Kong gateway — all API calls go here |
| Supabase Studio | http://localhost:3000 | Database UI and query editor |
| Postgres | localhost:54322 | Direct DB access (`postgres` / `$POSTGRES_PASSWORD`) |
| Inbucket (email) | http://localhost:54324 | Catches all outgoing emails in local dev |

## Repository structure

```
license-forge/
├── web/                  # Vue 3 + TypeScript frontend (Vite)
├── packages/
│   └── ui/               # Shared Vue component library (@syvora/ui)
├── supabase/
│   ├── kong.yml          # Kong API gateway routing config
│   ├── migrations/       # SQL migrations (run on DB startup)
│   └── functions/        # Deno edge functions
├── deployments/          # Production deployment configs
├── docker-compose.yml    # Local Supabase stack
└── .env.example          # Environment variable template
```

## Common tasks

**Reset the local database**

```bash
docker compose down -v   # removes db-data and storage-data volumes
docker compose up -d
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
