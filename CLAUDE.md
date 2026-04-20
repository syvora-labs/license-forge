# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

License Forge is a license management application built with a Vue 3 frontend and a self-hosted Supabase backend. The project uses Yarn workspaces as a monorepo.

## Commands

### Frontend Development

```bash
cd web && yarn dev              # Start Vite dev server at http://localhost:5173
cd web && yarn build            # Type-check then build for production
cd web && yarn vue-tsc -b --noEmit  # Type-check only (no build output)
```

### Backend (Self-hosted Supabase)

```bash
cd infrastructure/docker
cp .env.example .env
bash ./utils/generate-keys.sh --update-env   # Generate all secrets
docker compose up -d                          # Start all services
docker compose ps                             # Verify services are healthy
bash ./reset.sh && docker compose up -d       # Full reset
bash ./tests/test-self-hosted.sh              # Run smoke tests
```

### Workspace Management

```bash
yarn workspace web add <package>          # Add dependency to web app
yarn workspace @syvora/ui add <package>   # Add dependency to UI library
```

## Architecture

### Monorepo Structure

- **`web/`** — Vue 3 + TypeScript frontend (Vite). Imports the shared UI library via `@syvora/ui`. Path aliases in `tsconfig.app.json` point directly at the UI library source for development.
- **`packages/ui/`** — Shared component library (`@syvora/ui`). Exports Vue components prefixed `Syvora*` (Button, Card, Modal, Drawer, Tabs, CommandPalette, etc.) and composables (`useHotkey`, `useIsMobile`). Entry point: `src/index.ts`. Vite is configured to exclude it from `optimizeDeps` so changes are picked up live during dev.
- **`supabase/`** — Kong API gateway config (`kong.yml`), SQL migrations (`migrations/`), and Deno edge functions (`functions/`). Migrations run on container start in alphabetical order. Edge functions are live-mounted into the runtime container.
- **`infrastructure/docker/`** — Full self-hosted Supabase stack (13+ containers). Compose overlays for dev, S3 storage, and reverse proxies. Utility scripts for key generation and password rotation.

### Key Design Decisions

- The `@syvora/ui` package is consumed as **source** (not built artifacts) — `web/vite.config.ts` excludes it from optimizeDeps, and `web/tsconfig.app.json` has path aliases pointing to source files.
- API gateway routing is defined in `supabase/kong.yml`. All API calls go through Kong at `http://localhost:8000`.
- The `00_init.sh` migration is a bash script (not SQL) that bootstraps internal Supabase role passwords and schema ownership on fresh database initialization.

### Deployment

- Frontend deploys to Vercel on push to `master` via GitHub Actions (`.github/workflows/frontend-deployment-online.yml`).
- Dependabot runs daily for npm dependencies from the workspace root.

## Code Style

- **Indentation:** 4 spaces (all files, including YAML)
- **Line endings:** LF
- **Max line length:** 180 characters
- **TypeScript:** strict mode enabled, with `noUnusedLocals`, `noUnusedParameters`, `erasableSyntaxOnly`, `noFallthroughCasesInSwitch`
- **Vue:** `<script setup lang="ts">` with Composition API
