# Production Docker Compose — Design

**Date:** 2026-04-27
**Status:** Approved (awaiting written-spec review before implementation plan)

## Goal

Build a hardened production overlay for License Forge's self-hosted Supabase stack so that `docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod up -d` brings up a security-conscious deployment on a single VPS, fronted by nginx with Let's Encrypt TLS, with the frontend served as a built static bundle.

## Non-Goals

- Multi-host / cloud / Kubernetes deployments (single-VPS only).
- WAF / IDS / SIEM integration.
- Automated `pg_dump` backups (operator-driven, documented in runbook).
- Secret managers beyond a `chmod 600` `.env.prod` on the VPS (SOPS / Vault is a future follow-up).
- Modifying the frontend source — UI changes that follow from disabling email auth (e.g. hiding "forgot password") are flagged in the runbook but not made here.

## Architecture

### Topology

Single VPS, three subdomains, one TLS-terminating nginx as the only public surface:

```
Internet
   ↓ :80 (HTTP→HTTPS redirect, ACME challenge)
   ↓ :443 (TLS)
nginx (jonasal/nginx-certbot)
   ├── app.<PROXY_DOMAIN>     → web:8080         (built dist served by nginx-unprivileged)
   ├── api.<PROXY_DOMAIN>     → kong:8000        (REST/Auth/Realtime/Storage/Functions)
   └── studio.<PROXY_DOMAIN>  → studio:3000      (after IP allowlist + basic auth)
```

All other services (`db`, `auth`, `rest`, `realtime`, `storage`, `imgproxy`, `meta`, `functions`, `analytics`, `vector`, `supavisor`, `studio`) are reachable only on the docker bridge network. No host port mappings.

### Public ports

| Port | Service | Bound to |
|------|---------|----------|
| 80   | nginx (redirect + ACME) | `0.0.0.0` |
| 443  | nginx (TLS, three vhosts) | `0.0.0.0` |

Everything else is internal. SSH (22) is host-managed, outside compose scope.

## File Layout

```
infrastructure/docker/
├── docker-compose.prod.yml             [NEW] the overlay
├── volumes/proxy/nginx/
│   └── supabase-nginx.conf.tpl         [REWRITE] three vhosts, security headers, allowlist
├── .env.prod.example                   [NEW] prod env template (committed)
└── README-PROD.md                      [NEW] ops runbook

web/
├── Dockerfile.prod                     [NEW] multi-stage build → nginx-unprivileged
└── nginx.conf                          [NEW] static-serving config for the web container
```

`infrastructure/docker/.env.prod` is created on the VPS, `chmod 600`, and is **not** committed.

## Components

### `web` service (production)

**`web/Dockerfile.prod`** — two-stage build:

- Stage 1 `node:20-alpine`: installs workspace deps with frozen lockfile, copies `packages/` and `web/`, runs `yarn build` with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` passed as `ARG`s.
- Stage 2 `nginxinc/nginx-unprivileged:alpine`: copies `dist/` into `/usr/share/nginx/html`, copies `web/nginx.conf` into `/etc/nginx/conf.d/default.conf`, exposes 8080, has a `/healthz` healthcheck.

The unprivileged base image lets the container run as UID 101 with `read_only: true` and `cap_drop: [ALL]` without tmpfs gymnastics.

**`web/nginx.conf`** — serves static dist with:
- gzip for text-y types
- `/assets/*` → `Cache-Control: public, immutable, 1y`
- `/` → SPA fallback (`try_files ... /index.html`), `Cache-Control: no-store`
- `/healthz` → 200

Security headers (CSP, HSTS, X-Frame-Options, etc.) live on the **outer** nginx, not here.

**Build-time env, not runtime** — Vite bakes `VITE_*` into the JS bundle at build. Changing the API URL or anon key requires `docker compose build web` then `up -d web`. The anon key in the bundle is intentional (anon keys are public; RLS enforces actual security).

### Outer `nginx` (TLS termination)

**Image:** `jonasal/nginx-certbot:6.0.1-nginx1.29.5` (same as the existing nginx overlay).

**Vhosts** in `supabase-nginx.conf.tpl`:

#### Shared (top of file)

- TLS: TLSv1.2 + TLSv1.3 only, modern cipher list, OCSP stapling on, session tickets off.
- HSTS: `max-age=63072000; includeSubDomains; preload` — applied per-vhost (HTTPS only, never on the ACME redirect vhost).
- Three rate-limit zones:
  - `api_general`: 20 r/s per IP, burst 40
  - `api_auth`: 5 r/s per IP, burst 10 (signup/login/recover/otp/magiclink)
  - `studio`: 5 r/s per IP, burst 10

#### `app.<PROXY_DOMAIN>`

- HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (geolocation/microphone/camera/payment denied).
- CSP: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://api.<PROXY_DOMAIN> wss://api.<PROXY_DOMAIN>; frame-ancestors 'none'; base-uri 'self'; form-action 'self'`
- `'unsafe-inline'` on `style-src` is the one CSP relaxation (Vue/CSS toolchains).
- Proxies to `web:8080`.

#### `api.<PROXY_DOMAIN>`

- HSTS, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`.
- `client_max_body_size 50M` (storage uploads).
- Tighter rate limit on `^/auth/v1/(token|signup|recover|otp|magiclink)` via `api_auth` zone.
- `/realtime/v1/` block does WebSocket upgrade with 3600s read timeout.
- Default `/` block uses `api_general` zone.
- All blocks proxy to `kong:8000` and include a shared `proxy-common.conf` snippet that sets `Host`, `X-Forwarded-For`, `X-Forwarded-Proto`.

#### `studio.<PROXY_DOMAIN>`

- HSTS, `X-Frame-Options: DENY`.
- IP allowlist via included `studio-allowlist.conf` (generated at container start from `STUDIO_ALLOWED_CIDRS`), followed by `deny all;`.
- `auth_basic` using `dashboard-passwd` (existing pattern from nginx overlay, generated at container start with `openssl passwd -apr1`).
- `studio` rate-limit zone applied.
- Proxies to `studio:3000`.

#### Container start command

Replaces the existing `command:` in the nginx overlay:

```bash
# 1. Generate IP allowlist file from env
for cidr in $STUDIO_ALLOWED_CIDRS; do
  echo "allow $cidr;"
done > /etc/nginx/user_conf.d/studio-allowlist.conf

# 2. Generate htpasswd (existing pattern)
printf '%s:%s\n' "$DASHBOARD_USERNAME" "$(openssl passwd -apr1 "$DASHBOARD_PASSWORD")" \
  > /etc/nginx/user_conf.d/dashboard-passwd

# 3. Render template (existing pattern)
envsubst '${PROXY_DOMAIN}' < /etc/nginx/supabase-nginx.conf.tpl \
  > /etc/nginx/user_conf.d/nginx.conf

# 4. Start (existing pattern)
/scripts/start_nginx_certbot.sh
```

**Empty `STUDIO_ALLOWED_CIDRS` ⇒ empty allowlist file ⇒ `deny all;` matches everything ⇒ studio.* returns 403.** Safe default.

### `docker-compose.prod.yml` overlay

Defines:

#### Universal hardening (YAML anchor `&prod-defaults`)

```yaml
restart: unless-stopped
security_opt: [no-new-privileges:true]
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "5"
```

Applied to every service in the overlay.

#### Service-by-service

- **kong**: `ports: !reset []`, `KONG_PORT_MAPS: "443:8000,443:8443"` (matches existing caddy/nginx overlay pattern), inherits `&prod-defaults`, `read_only: true`, `tmpfs: /tmp`, `cap_drop: [ALL]`.
- **supavisor**: `ports: !reset []`, `cap_drop: [ALL]`, no read-only (writes to its own state).
- **db**: `cap_drop: [ALL]` (Postgres image runs as `postgres` user, image default is fine), no `read_only` (data volume).
- **storage**: same as db — writes to data volume, `cap_drop: [ALL]`.
- **auth**: `read_only: true`, `tmpfs: /tmp`, `cap_drop: [ALL]`. GoTrue env adds:
  - `GOTRUE_MAILER_AUTOCONFIRM=true`
  - `GOTRUE_EXTERNAL_EMAIL_ENABLED=${ENABLE_EMAIL_SIGNUP}`
  - `GOTRUE_DISABLE_SIGNUP=${ENABLE_EMAIL_SIGNUP:+false}`
  - `GOTRUE_SMTP_*=""`
- **rest, realtime, meta, imgproxy, vector**: inherit `&prod-defaults`, `read_only: true`, `tmpfs: /tmp`, `cap_drop: [ALL]`.
- **functions, analytics, studio**: inherit `&prod-defaults`, `cap_drop: [ALL]`. `read_only` is **not** applied by default — Studio is a Next.js app that may cache to `.next/`, Functions caches Deno modules to a named volume but the runtime may still touch other paths, Analytics writes Logflare state. The implementation plan will verify each at runtime and tighten where safe (likely `read_only` + `tmpfs` for Studio if it tolerates it).
- **vector**: docker socket mounted **read-only** (`/var/run/docker.sock:/var/run/docker.sock:ro`). This is the one notable security exception in the stack — accepted because the operator chose to keep Logflare for log visibility in Studio.
- **web**: `ports: !reset []`, `read_only: true`, `cap_drop: [ALL]`, `expose: ["8080"]`. Build args `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from env.
- **nginx** (new): image `jonasal/nginx-certbot`, `ports: ["80:80", "443:443"]`, `read_only: true` (cert vol is the writable spot), `cap_drop: [ALL]`, `cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]` (needed by the certbot+nginx process tree), `depends_on: { kong: healthy, studio: healthy, web: started }`.

#### Resource limits (Compose v2 `mem_limit` / `cpus`, NOT swarm-only `deploy.resources`)

| Service | mem_limit | cpus |
|---------|----------:|-----:|
| db | 2g | 2.0 |
| analytics | 512m | 0.5 |
| realtime | 512m | 0.5 |
| rest | 256m | 0.5 |
| auth | 256m | 0.5 |
| kong | 256m | 0.5 |
| storage | 256m | 0.5 |
| imgproxy | 256m | 0.5 |
| meta | 128m | 0.25 |
| supavisor | 256m | 0.5 |
| vector | 256m | 0.5 |
| functions | 512m | 1.0 |
| web | 64m | 0.25 |
| nginx | 128m | 0.5 |

Sized for a 4-vCPU / 8GB VPS. Adjustable via env if the host changes (env vars: `LIMIT_MEM_DB`, `LIMIT_CPU_DB`, etc. — sane defaults match the table).

#### Removed dev exposures

The dev overlay's `mail`, `meta:5555`, `storage:/var/lib/storage` tmpfs, fresh-db tmpfs, and seed data file do not apply (prod doesn't load that overlay).

### `.env.prod.example`

Template for prod env, committed. Operator copies to `.env.prod` on the VPS, fills in values, `chmod 600`. Required vars:

```
PROXY_DOMAIN=
CERTBOT_EMAIL=
DASHBOARD_USERNAME=
DASHBOARD_PASSWORD=                # generate: openssl rand -base64 32
STUDIO_ALLOWED_CIDRS=              # space-separated CIDRs; empty = 403 to all
VITE_SUPABASE_URL=                 # https://api.<PROXY_DOMAIN>
SITE_URL=                          # https://app.<PROXY_DOMAIN>
API_EXTERNAL_URL=                  # https://api.<PROXY_DOMAIN>
SUPABASE_PUBLIC_URL=               # https://api.<PROXY_DOMAIN>
ENABLE_EMAIL_SIGNUP=false
ENABLE_EMAIL_AUTOCONFIRM=true
ENABLE_ANONYMOUS_USERS=false
POSTGRES_PASSWORD=
JWT_SECRET=
ANON_KEY=
SERVICE_ROLE_KEY=
SECRET_KEY_BASE=
VAULT_ENC_KEY=
LOGFLARE_PUBLIC_ACCESS_TOKEN=
LOGFLARE_PRIVATE_ACCESS_TOKEN=
POOLER_TENANT_ID=
POOLER_DB_POOL_SIZE=5
KONG_HTTP_PORT=                    # left blank intentionally
KONG_HTTPS_PORT=
POSTGRES_PORT=
POOLER_PROXY_PORT_TRANSACTION=
```

`utils/generate-keys.sh --update-env` works against `.env.prod` if pointed at it.

### `README-PROD.md`

Short ops runbook covering:

- Prereqs: VPS with Docker + Compose v2, three DNS A records (`app.`, `api.`, `studio.`) → VPS IP.
- Host firewall: only `:22`, `:80`, `:443` open inbound.
- First deploy: clone, `cp .env.prod.example .env.prod`, fill, `chmod 600 .env.prod`, run `utils/generate-keys.sh --update-env --env-file .env.prod`, `docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod up -d --build`.
- Reaching Studio: ensure your IP is in `STUDIO_ALLOWED_CIDRS`, restart nginx, visit `https://studio.<domain>`.
- Migrations / DB access: `docker exec -it supabase-db psql -U postgres` or `ssh -L 5432:supabase-db:5432 vps`.
- Roll forward: `git pull`, `docker compose ... build web`, `docker compose ... up -d`.
- Frontend UX consequence of disabled email auth: hide "sign up with email" / "forgot password" / "magic link" UI in the SPA — those flows will hard-fail.
- Backups (NOT automated): `pg_dump -Fc` cron + off-site copy is essential for prod since storage data lives on the VPS.

## Security Posture Summary

| Concern | Mitigation |
|---------|-----------|
| Public attack surface | Only :80 + :443 reachable; everything else docker-internal |
| TLS | Let's Encrypt via certbot, TLSv1.2+, modern ciphers, HSTS preload, OCSP stapling |
| DB exposure | No host ports for Postgres or pooler; admin via `docker exec` / SSH tunnel |
| Studio access | IP allowlist + basic auth; empty allowlist fails closed |
| Email auth surface | Disabled; no SMTP creds in env, no email-driven account takeover paths |
| Container isolation | `read_only` + `cap_drop: [ALL]` + `no-new-privileges` on stateless services |
| DoS resistance | Per-zone rate limits, mem/CPU limits prevent one service starving the host |
| Log/disk safety | Json-file driver capped at 10MB × 5 files per service |
| Privilege escalation | No `privileged: true`, no docker socket mounts except Vector (read-only) |
| Header injection / XSS | Strict CSP, HSTS, X-Frame-Options, Referrer-Policy, Permissions-Policy |
| Secret leakage | `.env.prod` is `chmod 600`, not committed; service role key never reaches frontend bundle |

## Trade-offs Accepted

- **Vector docker-socket mount (read-only)** — kept for Logflare log visibility per Q8=A. Read-only mount limits the blast radius (can read events, can't `exec`) but it's still a privileged surface.
- **Local filesystem storage** (Q7=A) — VPS-snapshot-only durability. If the VPS is destroyed, file uploads are lost. Operator accepts this.
- **No automated backups** — operator-driven, documented but not built. A weekly `pg_dump` cron to off-site is strongly recommended.
- **`'unsafe-inline'` in CSP `style-src`** — required for Vue's runtime style injection. Scripts remain strict.
- **Basic auth + IP allowlist for Studio** rather than SSH-tunnel-only — chosen for ergonomics over maximum security per Q4=A.

## Open Items for Implementation Plan

- Confirm whether `cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID]` on the outer nginx is the minimum set or if `jonasal/nginx-certbot` works with fewer — needs runtime verification.
- Confirm Functions container can run with `read_only: true` (Deno cache is on a named volume — should be compatible).
- Confirm Studio container can run with `read_only: true` — Studio is a Next.js app and may write to `/tmp` or `.next/cache` on demand.
- Confirm exact list of GoTrue env vars to disable email — `GOTRUE_EXTERNAL_EMAIL_ENABLED` may not exist in this image version; fallback is leaving SMTP unset and `GOTRUE_MAILER_AUTOCONFIRM=true`.

These get verified during the implementation plan, not at design time.
