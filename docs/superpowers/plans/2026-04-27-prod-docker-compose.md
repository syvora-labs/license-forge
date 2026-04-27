# Production Docker Compose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hardened production overlay (`docker-compose.prod.yml`) for the License Forge self-hosted Supabase stack — TLS-fronted nginx, three subdomain layout (app/api/studio), built-static frontend, IP-allowlisted Studio, no public DB ports, container hardening defaults.

**Architecture:** Layered compose overlay (`docker-compose.yml` + `docker-compose.prod.yml` + `--env-file .env.prod`). Reuses the existing self-hosted Supabase services with `ports: !reset []` to internalize them; adds two new services (`web` for built static, `nginx` for TLS termination via `jonasal/nginx-certbot`); applies hardening (`read_only`, `cap_drop: [ALL]`, `no-new-privileges`, resource limits, log limits) via YAML anchor.

**Tech Stack:** Docker Compose v2, nginx 1.29 (jonasal/nginx-certbot), nginxinc/nginx-unprivileged:alpine for static serving, node:20-alpine for Vite build, existing Supabase stack (Kong, GoTrue, PostgREST, Realtime, Storage, Postgres, Supavisor, Studio, Vector, Logflare, Imgproxy, Edge Functions).

**Spec:** [`docs/superpowers/specs/2026-04-27-prod-docker-compose-design.md`](../specs/2026-04-27-prod-docker-compose-design.md)

---

## Context the engineer needs

- **The repo is a Yarn workspaces monorepo** but the dev Dockerfile (`web/Dockerfile.dev`) uses `npm install` (not yarn) because the macOS-generated `package-lock.json` contains platform-specific Rollup deps that break in Linux containers. **Match this in the prod Dockerfile** — use `npm install` without copying the lockfile.
- **Compose layering quirk:** override files use paths relative to *their own* directory, not the working directory. The dev overlay at `infrastructure/docker/dev/docker-compose.dev.yml` uses `../..` for the repo root; the prod overlay at `infrastructure/docker/docker-compose.prod.yml` uses `..`.
- **Compose `!reset []`** clears a list field from the base file. Used to strip host port mappings on `kong`, `supavisor`, `web` so only the `nginx` service has public ports.
- **The frontend uses Vite** which bakes `VITE_*` env vars at *build time*. Must be passed as Dockerfile `ARG`s and supplied via `build.args` in the overlay.
- **`jonasal/nginx-certbot`** auto-issues Let's Encrypt certs for any `ssl_certificate` path it finds in the rendered config, using HTTP-01 on `:80`. No manual cert work needed beyond exposing :80 and pointing DNS at the host.
- **Resource limits use Compose v2 top-level keys** (`mem_limit:`, `cpus:`) — NOT the swarm-only `deploy.resources.limits` block (silently ignored without swarm).
- **YAML anchors require `x-` prefix** at the top of the compose file (extension fields ignored by compose, allowed by YAML parser).
- **Existing nginx overlay** at `infrastructure/docker/docker-compose.nginx.yml` references `volumes/proxy/nginx/supabase-nginx.conf.tpl` (single-vhost). **Do NOT modify that file** — create a *new* template alongside it for prod (three vhosts).

---

## File Plan

**Files to create:**

| File | Responsibility |
|------|---------------|
| `web/Dockerfile.prod` | Multi-stage build → nginx-unprivileged static serving |
| `web/nginx.conf` | Static-serving config used inside the web container |
| `infrastructure/docker/docker-compose.prod.yml` | The overlay — port stripping, hardening, nginx + web services |
| `infrastructure/docker/.env.prod.example` | Prod env template (committed) |
| `infrastructure/docker/volumes/proxy/nginx/supabase-nginx-prod.conf.tpl` | Outer nginx config — three vhosts, security headers, allowlist |
| `infrastructure/docker/README-PROD.md` | Operator runbook |

**Files NOT modified:** `docker-compose.yml`, `docker-compose.nginx.yml`, `docker-compose.caddy.yml`, `dev/docker-compose.dev.yml`, `volumes/proxy/nginx/supabase-nginx.conf.tpl`, `web/Dockerfile.dev`, web source, packages/ui source, supabase/ source.

---

## Task 1: Frontend production image — `web/Dockerfile.prod` + `web/nginx.conf`

**Files:**
- Create: `web/nginx.conf`
- Create: `web/Dockerfile.prod`

This task produces a buildable, runnable image that serves the Vite-built SPA on port 8080 with `/healthz`, SPA fallback, and asset caching. No outer-nginx integration yet.

- [ ] **Step 1: Create `web/nginx.conf`**

```nginx
server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    server_tokens off;
    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1024;

    # Hashed asset bundles — long cache
    location /assets/ {
        try_files $uri =404;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback — index.html is never cached
    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-store" always;
    }

    location = /healthz {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
```

- [ ] **Step 2: Create `web/Dockerfile.prod`**

```dockerfile
# Stage 1 — build the Vite SPA
FROM node:20-alpine AS build
WORKDIR /repo

COPY package.json ./
COPY packages/ui/package.json ./packages/ui/
COPY web/package.json ./web/

# Match Dockerfile.dev: do NOT copy package-lock.json — it is generated on
# macOS and contains platform-specific optional deps (e.g. @rollup/rollup-darwin-arm64)
# that cause npm to skip the linux-musl equivalents needed in this container.
RUN npm install

COPY packages ./packages
COPY web ./web

ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_ANON_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY

RUN cd web && npm run build

# Stage 2 — serve the built dist with unprivileged nginx
FROM nginxinc/nginx-unprivileged:alpine AS serve
COPY --from=build /repo/web/dist /usr/share/nginx/html
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
```

- [ ] **Step 3: Build the image**

Run from repo root:

```bash
docker build \
  -f web/Dockerfile.prod \
  --build-arg VITE_SUPABASE_URL=https://api.example.test \
  --build-arg VITE_SUPABASE_ANON_KEY=test-anon-key \
  -t license-forge-web:test \
  .
```

Expected: build succeeds. Note `vue-tsc` runs as part of `npm run build` — if it fails on type errors, fix them first; the prod build must pass type check.

- [ ] **Step 4: Run the container and verify it serves**

```bash
docker run --rm -d -p 18080:8080 --name lf-web-test license-forge-web:test
sleep 2
curl -fsS http://localhost:18080/healthz                    # expect: ok
curl -fsSI http://localhost:18080/                          # expect: HTTP/1.1 200, Cache-Control: no-store
curl -fsSI http://localhost:18080/some-spa-route            # expect: HTTP/1.1 200 (SPA fallback)
curl -fsSI http://localhost:18080/this-is-not-a-thing.png   # expect: HTTP/1.1 200 (also falls back to index.html)
docker stop lf-web-test
```

Expected: all four curls succeed. Asset URLs (anything under `/assets/...`) only return 200 if the file exists.

- [ ] **Step 5: Commit**

```bash
git add web/Dockerfile.prod web/nginx.conf
git commit -m "feat(web): add production Dockerfile and static-serving nginx config"
```

---

## Task 2: Prod env template — `.env.prod.example`

**Files:**
- Create: `infrastructure/docker/.env.prod.example`

The template documents every var the prod overlay reads. Operators copy this to `.env.prod` on the VPS, fill values, `chmod 600`.

- [ ] **Step 1: Create `infrastructure/docker/.env.prod.example`**

```bash
# ============================================================
# License Forge — Production Environment Template
# ============================================================
# Copy to .env.prod on the VPS, fill in values, chmod 600.
# Never commit .env.prod.
#
# To generate fresh secrets:
#   bash ./utils/generate-keys.sh --update-env
# (Point it at .env.prod after copying.)
# ============================================================

# --- Domain & TLS ---
PROXY_DOMAIN=example.com
CERTBOT_EMAIL=ops@example.com

# --- Studio dashboard access ---
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=                 # generate: openssl rand -base64 32
# Space-separated CIDRs allowed to reach studio.${PROXY_DOMAIN}
# EMPTY = studio.* returns 403 to everyone (safe default)
STUDIO_ALLOWED_CIDRS=

# --- Frontend build-time env (baked into JS bundle) ---
VITE_SUPABASE_URL=https://api.example.com

# --- Public URLs (GoTrue + Studio rely on these) ---
SITE_URL=https://app.example.com
API_EXTERNAL_URL=https://api.example.com
SUPABASE_PUBLIC_URL=https://api.example.com

# --- Email auth disabled (prod design = no SMTP) ---
ENABLE_EMAIL_SIGNUP=false
ENABLE_EMAIL_AUTOCONFIRM=true
ENABLE_ANONYMOUS_USERS=false

# --- Supabase secrets — generate fresh for prod, do NOT reuse dev ---
POSTGRES_PASSWORD=
JWT_SECRET=
ANON_KEY=
SERVICE_ROLE_KEY=
SECRET_KEY_BASE=
VAULT_ENC_KEY=
LOGFLARE_PUBLIC_ACCESS_TOKEN=
LOGFLARE_PRIVATE_ACCESS_TOKEN=

# --- Pooler ---
POOLER_TENANT_ID=local
POOLER_DB_POOL_SIZE=5

# --- Internal port values ---
# These are required for env interpolation in docker-compose.yml but
# are stripped at the host boundary by `ports: !reset []` in
# docker-compose.prod.yml. Don't change them; nginx fronts everything.
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443
POSTGRES_PORT=5432
POOLER_PROXY_PORT_TRANSACTION=6543
POOLER_PROXY_PORT_SESSION=5432

# --- Postgres / pgsodium ---
POSTGRES_HOST=db
POSTGRES_DB=postgres

# --- Studio config ---
STUDIO_DEFAULT_ORGANIZATION=License Forge
STUDIO_DEFAULT_PROJECT=Production
STUDIO_PORT=3000

# --- Functions ---
FUNCTIONS_VERIFY_JWT=false

# --- Logflare ---
LOGFLARE_LOGGER_BACKEND_API_KEY=

# --- Image proxy ---
IMGPROXY_ENABLE_WEBP_DETECTION=true

# --- Docker socket location (Vector) ---
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

# --- Optional: GoTrue redirect allowlist (comma-separated) ---
ADDITIONAL_REDIRECT_URLS=
```

- [ ] **Step 2: Diff against `.env.example` to confirm coverage**

```bash
diff <(grep -oE '^[A-Z_]+(=|$)' infrastructure/docker/.env.example | sort -u) \
     <(grep -oE '^[A-Z_]+(=|$)' infrastructure/docker/.env.prod.example | sort -u)
```

Expected: any var in `.env.example` that the *base* compose references should also appear in `.env.prod.example`. Vars only referenced by the dev overlay (e.g. `IMGPROXY_LOCAL_FILESYSTEM_ROOT`) can be absent.

If any var in `.env.example` that's referenced in `docker-compose.yml` is missing from `.env.prod.example`, add it.

- [ ] **Step 3: Add `.env.prod` to `.gitignore`**

Verify it's not currently covered:

```bash
git check-ignore infrastructure/docker/.env.prod && echo "already ignored" || echo "NOT IGNORED — adding"
```

If "NOT IGNORED", append to the docker-level gitignore:

```bash
printf '%s\n' '.env.prod' >> infrastructure/docker/.gitignore
```

Verify it now matches:

```bash
git check-ignore infrastructure/docker/.env.prod
# Expect: infrastructure/docker/.env.prod
```

- [ ] **Step 4: Commit**

```bash
git add infrastructure/docker/.env.prod.example infrastructure/docker/.gitignore
git commit -m "feat(docker): add production env template and gitignore .env.prod"
```

---

## Task 3: Outer nginx template — `supabase-nginx-prod.conf.tpl`

**Files:**
- Create: `infrastructure/docker/volumes/proxy/nginx/supabase-nginx-prod.conf.tpl`

Three vhosts (app/api/studio), shared TLS hardening, rate-limit zones, security headers, IP allowlist for studio.

- [ ] **Step 1: Create the template file**

```nginx
# ============================================================
# License Forge — Production Outer nginx
# Three vhosts: app.${PROXY_DOMAIN}, api.${PROXY_DOMAIN}, studio.${PROXY_DOMAIN}
# Rendered from this template at container start by envsubst.
# ============================================================

# ---- Rate-limit zones ----
limit_req_zone $binary_remote_addr zone=api_general:10m rate=20r/s;
limit_req_zone $binary_remote_addr zone=api_auth:10m    rate=5r/s;
limit_req_zone $binary_remote_addr zone=studio:10m      rate=5r/s;

# ---- TLS hardening ----
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;

# Optional Diffie-Hellman params (jonasal/nginx-certbot generates dhparams automatically)
ssl_dhparam /etc/letsencrypt/dhparams/dhparam.pem;

# Hide nginx version
server_tokens off;

# Buffers — Supabase auth cookies can be large (carried over from prior nginx config)
large_client_header_buffers 4 16k;
proxy_buffer_size 128k;
proxy_buffers 4 256k;
proxy_busy_buffers_size 256k;

# HSTS header value (mapped so we can apply it consistently)
map $sent_http_content_type $hsts_header {
    default "max-age=63072000; includeSubDomains; preload";
}

# ============================================================
# app.${PROXY_DOMAIN} — frontend SPA
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name app.${PROXY_DOMAIN};

    # Allow ACME HTTP-01 challenge (jonasal-managed); redirect everything else
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name app.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/app.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/app.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' https://api.${PROXY_DOMAIN} wss://api.${PROXY_DOMAIN}; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" always;

    location / {
        proxy_pass http://web:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# ============================================================
# api.${PROXY_DOMAIN} — Kong → Supabase services
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name api.${PROXY_DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name api.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/api.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/api.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $http_host;
    proxy_set_header X-Forwarded-Port $server_port;

    # Auth flow endpoints — strict rate limit (signup / login / password reset / OTP)
    location ~ ^/auth/v1/(token|signup|recover|otp|magiclink) {
        limit_req zone=api_auth burst=10 nodelay;
        proxy_pass http://kong:8000;
    }

    # Realtime — WebSocket upgrade + long timeout
    location /realtime/v1/ {
        proxy_pass http://kong:8000;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    # Storage uploads — disable buffering, allow large bodies
    location /storage/v1/ {
        proxy_pass http://kong:8000;
        proxy_buffering off;
        proxy_request_buffering off;
        chunked_transfer_encoding off;
        client_max_body_size 0;
    }

    # General API — moderate rate limit, 50M body cap
    location / {
        limit_req zone=api_general burst=40 nodelay;
        client_max_body_size 50M;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_pass http://kong:8000;
    }
}

# ============================================================
# studio.${PROXY_DOMAIN} — Studio dashboard (IP allowlist + basic auth)
# ============================================================
server {
    listen 80;
    listen [::]:80;
    server_name studio.${PROXY_DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name studio.${PROXY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/studio.${PROXY_DOMAIN}/chain.pem;

    add_header Strict-Transport-Security $hsts_header always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    # IP allowlist — studio-allowlist.conf is generated at container start
    # from STUDIO_ALLOWED_CIDRS (empty = empty file = `deny all` matches all = 403)
    include /etc/nginx/user_conf.d/studio-allowlist.conf;
    deny all;

    # Then basic auth on top of IP allowlist
    auth_basic           "License Forge Studio";
    auth_basic_user_file /etc/nginx/user_conf.d/dashboard-passwd;

    limit_req zone=studio burst=10 nodelay;

    location / {
        proxy_pass http://studio:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

- [ ] **Step 2: Validate the template syntax with a render+nginx-t roundtrip**

The template uses `${PROXY_DOMAIN}` placeholders that envsubst will replace. We can validate the rendered output:

```bash
cd /Users/dariokrieger/Documents/repositories/license-forge/infrastructure/docker

# Render with a dummy domain
PROXY_DOMAIN=example.com envsubst '${PROXY_DOMAIN}' \
    < volumes/proxy/nginx/supabase-nginx-prod.conf.tpl \
    > /tmp/nginx-prod-rendered.conf

# Run nginx -t against the rendered file
docker run --rm \
    -v /tmp/nginx-prod-rendered.conf:/etc/nginx/conf.d/test.conf:ro \
    nginx:alpine \
    nginx -t -c /etc/nginx/nginx.conf
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`. The cert file references will produce warnings about missing files at *runtime* (jonasal/nginx-certbot handles that), but `nginx -t` only validates syntax, not file existence at this layer.

If syntax errors appear, fix them in the template and re-run.

- [ ] **Step 3: Commit**

```bash
git add infrastructure/docker/volumes/proxy/nginx/supabase-nginx-prod.conf.tpl
git commit -m "feat(docker): add prod outer-nginx template with three vhosts"
```

---

## Task 4: The prod overlay — `docker-compose.prod.yml`

**Files:**
- Create: `infrastructure/docker/docker-compose.prod.yml`

The biggest task. Builds on everything above. Defines `nginx` and `web` services, strips host port mappings on `kong`/`supavisor`, applies hardening to all services.

- [ ] **Step 1: Create `infrastructure/docker/docker-compose.prod.yml`**

```yaml
# ============================================================
# License Forge — Production Overlay
# Run with:
#   docker compose -f docker-compose.yml -f docker-compose.prod.yml \
#                  --env-file .env.prod up -d --build
# ============================================================

# YAML anchor — applied to every service in the overlay
x-prod-defaults: &prod-defaults
    restart: unless-stopped
    security_opt:
        - no-new-privileges:true
    logging:
        driver: json-file
        options:
            max-size: "10m"
            max-file: "5"

services:

    # --------------------------------------------------------
    # Outer nginx — TLS termination, three vhosts, ACME
    # --------------------------------------------------------
    nginx:
        <<: *prod-defaults
        container_name: supabase-nginx
        image: jonasal/nginx-certbot:6.0.1-nginx1.29.5
        ports:
            - "80:80"
            - "443:443"
        depends_on:
            kong:
                condition: service_healthy
            studio:
                condition: service_healthy
            web:
                condition: service_started
        environment:
            PROXY_DOMAIN: ${PROXY_DOMAIN}
            CERTBOT_EMAIL: ${CERTBOT_EMAIL}
            PROXY_AUTH_USERNAME: ${DASHBOARD_USERNAME}
            PROXY_AUTH_PASSWORD: ${DASHBOARD_PASSWORD}
            STUDIO_ALLOWED_CIDRS: ${STUDIO_ALLOWED_CIDRS}
        command:
            - /bin/bash
            - -c
            - |
                set -eu
                # 1. Generate IP allowlist file from env (empty STUDIO_ALLOWED_CIDRS => empty file => deny all)
                : > /etc/nginx/user_conf.d/studio-allowlist.conf
                for cidr in $${STUDIO_ALLOWED_CIDRS}; do
                    echo "allow $${cidr};" >> /etc/nginx/user_conf.d/studio-allowlist.conf
                done

                # 2. Generate htpasswd for studio basic auth
                printf '%s:%s\n' "$${PROXY_AUTH_USERNAME}" "$$(openssl passwd -apr1 "$${PROXY_AUTH_PASSWORD}")" \
                    > /etc/nginx/user_conf.d/dashboard-passwd

                # 3. Render template (envsubst only the vars we want)
                envsubst '$${PROXY_DOMAIN}' \
                    < /etc/nginx/supabase-nginx-prod.conf.tpl \
                    > /etc/nginx/user_conf.d/nginx.conf

                # 4. Start nginx + certbot (image's existing entrypoint)
                /scripts/start_nginx_certbot.sh
        volumes:
            - ./volumes/proxy/nginx/supabase-nginx-prod.conf.tpl:/etc/nginx/supabase-nginx-prod.conf.tpl:ro
            - nginx_letsencrypt:/etc/letsencrypt
        cap_drop: [ALL]
        cap_add:
            - NET_BIND_SERVICE
            - CHOWN
            - SETUID
            - SETGID
            - DAC_OVERRIDE
        mem_limit: 128m
        cpus: 0.5

    # --------------------------------------------------------
    # Frontend — built static SPA served by nginx-unprivileged
    # --------------------------------------------------------
    web:
        <<: *prod-defaults
        container_name: supabase-web
        build:
            context: ../..
            dockerfile: web/Dockerfile.prod
            args:
                VITE_SUPABASE_URL: ${VITE_SUPABASE_URL}
                VITE_SUPABASE_ANON_KEY: ${ANON_KEY}
        ports: !reset []
        expose:
            - "8080"
        read_only: true
        cap_drop: [ALL]
        mem_limit: 64m
        cpus: 0.25

    # --------------------------------------------------------
    # Strip host ports on services that should be internal-only
    # --------------------------------------------------------
    kong:
        <<: *prod-defaults
        ports: !reset []
        environment:
            KONG_PORT_MAPS: "443:8000,443:8443"
        read_only: true
        tmpfs:
            - /tmp:size=64M,mode=1777
            - /usr/local/kong:size=32M,mode=0755
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    supavisor:
        <<: *prod-defaults
        ports: !reset []
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    # --------------------------------------------------------
    # Stateless services — read-only filesystem, dropped caps
    # --------------------------------------------------------
    auth:
        <<: *prod-defaults
        environment:
            GOTRUE_MAILER_AUTOCONFIRM: "${ENABLE_EMAIL_AUTOCONFIRM:-true}"
            GOTRUE_EXTERNAL_EMAIL_ENABLED: "${ENABLE_EMAIL_SIGNUP:-false}"
            GOTRUE_DISABLE_SIGNUP: "${ENABLE_EMAIL_SIGNUP:+false}"
            GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED: "${ENABLE_ANONYMOUS_USERS:-false}"
            GOTRUE_SMTP_HOST: ""
            GOTRUE_SMTP_USER: ""
            GOTRUE_SMTP_PASS: ""
            GOTRUE_SMTP_ADMIN_EMAIL: ""
        read_only: true
        tmpfs:
            - /tmp:size=32M,mode=1777
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    rest:
        <<: *prod-defaults
        read_only: true
        tmpfs:
            - /tmp:size=32M,mode=1777
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    realtime:
        <<: *prod-defaults
        read_only: true
        tmpfs:
            - /tmp:size=64M,mode=1777
        cap_drop: [ALL]
        mem_limit: 512m
        cpus: 0.5

    meta:
        <<: *prod-defaults
        read_only: true
        tmpfs:
            - /tmp:size=32M,mode=1777
        cap_drop: [ALL]
        mem_limit: 128m
        cpus: 0.25

    imgproxy:
        <<: *prod-defaults
        read_only: true
        tmpfs:
            - /tmp:size=64M,mode=1777
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    # --------------------------------------------------------
    # Stateful or runtime-write services — caps dropped, no read-only
    # --------------------------------------------------------
    db:
        <<: *prod-defaults
        cap_drop: [ALL]
        mem_limit: 2g
        cpus: 2.0

    storage:
        <<: *prod-defaults
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    # Logflare — writes Logflare state, not flipped read-only here
    analytics:
        <<: *prod-defaults
        cap_drop: [ALL]
        mem_limit: 512m
        cpus: 0.5

    # Studio — Next.js, may write to .next/cache; not flipped read-only here
    studio:
        <<: *prod-defaults
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

    # Edge functions — Deno cache lives on a volume, but the runtime may write elsewhere
    functions:
        <<: *prod-defaults
        cap_drop: [ALL]
        mem_limit: 512m
        cpus: 1.0

    # Vector — base already mounts the docker socket as :ro,z, no override needed
    vector:
        <<: *prod-defaults
        read_only: true
        tmpfs:
            - /tmp:size=64M,mode=1777
            - /var/lib/vector:size=128M,mode=0755
        cap_drop: [ALL]
        mem_limit: 256m
        cpus: 0.5

volumes:
    nginx_letsencrypt:
```

**Notes embedded in the overlay above:**
- `vector.volumes` re-declares the docker socket with `:ro` (read-only). This mirrors the existing dev compose's mount but adds the read-only flag — Vector reads container metadata, never invokes commands.
- `web.expose: ["8080"]` is documentation; the Dockerfile already declares it. Kept for auditability.
- `auth.GOTRUE_DISABLE_SIGNUP` uses `${ENABLE_EMAIL_SIGNUP:+false}` — sets to `false` only if `ENABLE_EMAIL_SIGNUP` is set; empty otherwise. Compose env interpolation supports this pattern.
- `kong.tmpfs` includes `/usr/local/kong` because Kong writes runtime state there; without it, `read_only: true` breaks startup.

- [ ] **Step 2: Create a throwaway `.env.prod.test` for local validation**

```bash
cd /Users/dariokrieger/Documents/repositories/license-forge/infrastructure/docker
cp .env.prod.example .env.prod.test
# Fill in just enough to validate config — fake values are fine
sed -i.bak \
    -e 's|^PROXY_DOMAIN=.*|PROXY_DOMAIN=example.test|' \
    -e 's|^CERTBOT_EMAIL=.*|CERTBOT_EMAIL=ops@example.test|' \
    -e 's|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=changeme|' \
    -e 's|^VITE_SUPABASE_URL=.*|VITE_SUPABASE_URL=https://api.example.test|' \
    -e 's|^SITE_URL=.*|SITE_URL=https://app.example.test|' \
    -e 's|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.example.test|' \
    -e 's|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.example.test|' \
    -e 's|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=test|' \
    -e 's|^JWT_SECRET=.*|JWT_SECRET=this-is-a-fake-secret-just-for-config-validation-not-real|' \
    -e 's|^ANON_KEY=.*|ANON_KEY=test-anon|' \
    -e 's|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=test-service|' \
    -e 's|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=this-is-a-fake-base-key-just-for-config-validation-not-real|' \
    -e 's|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=fake-vault-encryption-key-32ch|' \
    -e 's|^LOGFLARE_PUBLIC_ACCESS_TOKEN=.*|LOGFLARE_PUBLIC_ACCESS_TOKEN=test|' \
    -e 's|^LOGFLARE_PRIVATE_ACCESS_TOKEN=.*|LOGFLARE_PRIVATE_ACCESS_TOKEN=test|' \
    .env.prod.test
rm -f .env.prod.test.bak
```

- [ ] **Step 3: Validate the merged compose config**

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.test \
    config > /tmp/lf-prod-config.yml

echo "Exit code: $?"
echo "---"
echo "Services in merged config:"
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.test \
    config --services | sort
echo "---"
echo "Services with host ports (should ONLY be nginx):"
grep -B1 'published:' /tmp/lf-prod-config.yml | grep -oE '^  [a-z_-]+:' | sort -u
```

Expected:
- Exit code: `0`
- Services: `analytics auth db functions imgproxy kong meta nginx realtime rest storage studio supavisor vector web` (15 services)
- Services with host ports: `nginx:` and only `nginx:`

If `web`, `kong`, or `supavisor` appear in the host-ports list, the `!reset []` failed — fix and re-run.

- [ ] **Step 4: Verify the web service's build args resolve correctly**

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.test \
    config | sed -n '/^  web:/,/^  [a-z]/p' | grep -A4 'args:'
```

Expected output contains:
```
args:
  VITE_SUPABASE_ANON_KEY: test-anon
  VITE_SUPABASE_URL: https://api.example.test
```

- [ ] **Step 5: Verify auth's GoTrue email-disable env applied**

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.test \
    config | sed -n '/^  auth:/,/^  [a-z]/p' | grep -E 'GOTRUE_(MAILER|EXTERNAL_EMAIL|SMTP|DISABLE_SIGNUP)'
```

Expected: shows `GOTRUE_MAILER_AUTOCONFIRM: "true"`, `GOTRUE_EXTERNAL_EMAIL_ENABLED: "false"`, empty `GOTRUE_SMTP_*` values.

- [ ] **Step 6: Clean up the test env file (NEVER commit it)**

```bash
rm -f infrastructure/docker/.env.prod.test
```

- [ ] **Step 7: Commit**

```bash
git add infrastructure/docker/docker-compose.prod.yml
git commit -m "feat(docker): add hardened production compose overlay"
```

---

## Task 5: Operator runbook — `README-PROD.md`

**Files:**
- Create: `infrastructure/docker/README-PROD.md`

- [ ] **Step 1: Create `infrastructure/docker/README-PROD.md`**

```markdown
# License Forge — Production Deployment Runbook

This runbook covers operating License Forge in production using
`docker-compose.prod.yml` on a single VPS.

## Prerequisites

- VPS with Docker 24+ and Docker Compose v2
- Public IPv4 (or IPv6) address
- A domain you control (referred to as `<domain>` below; e.g. `example.com`)
- Three DNS A records, all pointing at the VPS IP:
    - `app.<domain>`
    - `api.<domain>`
    - `studio.<domain>`
- Host firewall (ufw / iptables / cloud security group) allowing inbound:
    - `:22/tcp`  — SSH
    - `:80/tcp`  — HTTP (ACME challenge + redirect to HTTPS)
    - `:443/tcp` — HTTPS
  Block everything else inbound.

## First-time deployment

```bash
# 1. Clone the repo on the VPS
git clone <repo-url> /opt/license-forge
cd /opt/license-forge/infrastructure/docker

# 2. Create the prod env file
cp .env.prod.example .env.prod
chmod 600 .env.prod

# 3. Generate fresh secrets into .env.prod
#    (The script reads/writes the file in the current dir.)
ENV_FILE=.env.prod bash ./utils/generate-keys.sh --update-env

# 4. Edit .env.prod by hand to set:
#      PROXY_DOMAIN
#      CERTBOT_EMAIL
#      DASHBOARD_USERNAME / DASHBOARD_PASSWORD
#      STUDIO_ALLOWED_CIDRS  (your office/VPN IPs)
#      VITE_SUPABASE_URL
#      SITE_URL / API_EXTERNAL_URL / SUPABASE_PUBLIC_URL
nano .env.prod

# 5. Bring up the stack (first build will take several minutes)
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod \
    up -d --build

# 6. Verify
docker compose ps
docker compose logs -f nginx     # watch certbot pick up Let's Encrypt certs
```

## Reaching Studio

1. Confirm your current IP is in `STUDIO_ALLOWED_CIDRS` in `.env.prod`.
2. If not, edit `.env.prod` and restart nginx:
    ```bash
    docker compose -f docker-compose.yml -f docker-compose.prod.yml \
        --env-file .env.prod up -d --no-deps nginx
    ```
3. Visit `https://studio.<domain>` and authenticate with `DASHBOARD_USERNAME` /
   `DASHBOARD_PASSWORD`.

If `STUDIO_ALLOWED_CIDRS` is empty, Studio returns 403 to *everyone*. This is
the intended fail-closed default.

## Database access

Postgres and the Supavisor pooler have no host ports in prod. Two ways in:

### Option A — `docker exec` (fastest)

```bash
docker exec -it supabase-db psql -U postgres
```

### Option B — SSH tunnel (when you want a local `psql` or GUI)

```bash
ssh -L 5432:supabase-db:5432 vps
# In another terminal:
psql postgresql://postgres:<POSTGRES_PASSWORD>@localhost:5432/postgres
```

## Migrations

```bash
# Apply a new SQL migration (assuming the file is in supabase/migrations/)
docker exec -i supabase-db psql -U postgres -f - < supabase/migrations/001_new_thing.sql

# Or copy a file in and run it inside:
docker cp supabase/migrations/001_new_thing.sql supabase-db:/tmp/
docker exec -it supabase-db psql -U postgres -f /tmp/001_new_thing.sql
```

## Rolling forward

```bash
cd /opt/license-forge
git pull

cd infrastructure/docker
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod \
    up -d --build
```

The frontend (`web` service) gets rebuilt because its source changed. Other
services pull new images only when their `image:` tag changes in the compose
file.

## Frontend UX with email auth disabled

Because prod sets `GOTRUE_EXTERNAL_EMAIL_ENABLED=false`, these flows will
hard-fail at runtime:

- Email + password signup
- Password reset
- Magic-link login

The frontend should not surface those options in its UI. If it does today,
hide them — that's a separate frontend change, not part of this runbook.

## Backups

This stack stores data in three places:

1. **Postgres** — named volume, contains all relational data.
2. **Storage filesystem** — named volume, contains all uploaded files.
3. **Logflare/analytics** — named volume, contains log history (low value).

There is no automated backup in this compose. **You must add one.** Minimal
suggested approach:

```bash
# /etc/cron.daily/license-forge-backup
#!/usr/bin/env bash
set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
DEST=/var/backups/license-forge

mkdir -p "$DEST"

# Postgres logical dump
docker exec supabase-db pg_dump -U postgres -Fc postgres \
    > "$DEST/db-$TS.dump"

# Storage filesystem
docker run --rm \
    -v supabase_storage:/data:ro \
    -v "$DEST:/backup" \
    alpine tar czf "/backup/storage-$TS.tar.gz" -C /data .

# Optional: rclone/aws-cli copy "$DEST" off-site
```

Verify periodically that you can restore from a backup. Untested backups are
not backups.

## Common ops tasks

### Rotate dashboard password

```bash
# Edit .env.prod, change DASHBOARD_PASSWORD, then:
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod up -d --no-deps nginx
```

### Rotate JWT secret + anon/service keys (logs everyone out)

```bash
ENV_FILE=.env.prod bash ./utils/rotate-new-api-keys.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod up -d
```

Frontend bundle has `ANON_KEY` baked in at build time, so this also requires
a frontend rebuild (`up -d --build web`).

### Add an IP to the Studio allowlist

Edit `.env.prod`, append to `STUDIO_ALLOWED_CIDRS` (space-separated), restart nginx:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod up -d --no-deps nginx
```

### Tail logs

```bash
docker compose logs -f                  # everything
docker compose logs -f nginx auth db    # specific services
```

### Stop / restart

```bash
# Graceful stop (data preserved)
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod stop

# Restart
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod up -d
```

## Troubleshooting

### Certbot can't issue certs

- Confirm DNS A records resolve to the VPS IP from a public resolver:
  `dig +short app.<domain> @1.1.1.1`
- Confirm port 80 is reachable from outside: `curl -I http://<vps-ip>/`
- Inspect: `docker compose logs nginx | grep -i certbot`
- Let's Encrypt has rate limits — if you hit them, wait or use the staging
  endpoint by setting `STAGING=1` in `.env.prod` for the nginx container
  (jonasal-supported flag).

### Studio shows 403 to everyone

`STUDIO_ALLOWED_CIDRS` is empty or doesn't include your IP. See "Reaching
Studio" above.

### Frontend bundle has wrong API URL

`VITE_SUPABASE_URL` is baked at build time. Edit `.env.prod`, then rebuild:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml \
    --env-file .env.prod up -d --build web
```

### Container restarts repeatedly with read-only fs error

A service we marked `read_only: true` is trying to write somewhere we didn't
expect. Inspect logs (`docker compose logs <service>`) for the path, add a
`tmpfs:` mount for it in `docker-compose.prod.yml`, redeploy.

## Security notes

This deployment hardens the stack but does NOT cover:

- Host-level patching (run `unattended-upgrades` or equivalent)
- SSH hardening (disable password auth, use keys)
- Intrusion detection / log shipping off-host
- A WAF in front of nginx (Cloudflare, etc.) — optional

See `docs/superpowers/specs/2026-04-27-prod-docker-compose-design.md` for
the full security posture table.
```

- [ ] **Step 2: Commit**

```bash
git add infrastructure/docker/README-PROD.md
git commit -m "docs: add prod deployment runbook"
```

---

## Task 6: End-to-end local verification

**Files:** none — this is a verification task that exercises the artifacts above on a local Docker host.

This task confirms the prod overlay actually starts services correctly. It runs **on a developer's machine** (Docker Desktop or similar), not on the VPS. We use a fake `example.test` domain wired through `/etc/hosts` and Let's Encrypt staging to avoid burning prod cert quota.

> **NOTE:** This requires a running Docker daemon. If `docker info` fails, skip this task and have it run during deploy verification on the VPS instead.

- [ ] **Step 1: Check Docker is available**

```bash
docker info > /dev/null 2>&1 && echo "Docker OK" || { echo "Docker not running — skip this task"; exit 0; }
```

- [ ] **Step 2: Set up `/etc/hosts` for the test domain**

```bash
sudo tee -a /etc/hosts <<'EOF'
# license-forge prod overlay verification
127.0.0.1 app.example.test api.example.test studio.example.test
EOF
```

- [ ] **Step 3: Create `.env.prod.local` (test env)**

Use the same fake-values approach as Task 4 Step 2, but enable Let's Encrypt staging by adding `STAGING=1` (jonasal/nginx-certbot reads this):

```bash
cd infrastructure/docker
cp .env.prod.example .env.prod.local
chmod 600 .env.prod.local
# (Edit .env.prod.local — set fake values for required fields, plus:)
# STAGING=1
# PROXY_DOMAIN=example.test
# STUDIO_ALLOWED_CIDRS=127.0.0.1/32 ::1/128
# VITE_SUPABASE_URL=https://api.example.test
# SITE_URL=https://app.example.test
# API_EXTERNAL_URL=https://api.example.test
# SUPABASE_PUBLIC_URL=https://api.example.test
# DASHBOARD_PASSWORD=localtest
# All other secrets: run `bash ./utils/generate-keys.sh --update-env` against
# .env.prod.local (set ENV_FILE=.env.prod.local).
ENV_FILE=.env.prod.local bash ./utils/generate-keys.sh --update-env
```

> Note: cert issuance against a domain that doesn't actually resolve publicly will fail. For a *fully local* test, you may need to skip nginx/certbot and run only the inner services, OR run nginx with self-signed certs. The simplest path: validate the compose config and the `web` build, but defer the full integration test to the VPS deploy.

- [ ] **Step 4: Bring up everything except nginx (which needs real DNS)**

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.local \
    up -d --build \
    db analytics auth realtime supavisor meta rest storage imgproxy kong studio vector functions web
```

Expected: all services start. Wait ~60 seconds for healthchecks to settle.

- [ ] **Step 5: Verify port exposure on the host**

```bash
# Only nginx (not started here) and the inner services should NOT be on host
docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod.local ps --format '{{.Name}} {{.Ports}}'
```

Expected: NO ports column shows `0.0.0.0:` for db, supavisor, kong, web, etc. (Without the nginx service running, no service has a host port.)

- [ ] **Step 6: Verify the web container serves**

```bash
# Get the web container's IP and curl it directly
docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod.local exec -T web wget -qO- http://127.0.0.1:8080/healthz
# Expect: ok
```

- [ ] **Step 7: Verify Kong is reachable on the docker network but not the host**

```bash
# From inside the docker network — should work
docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod.local exec -T web wget -qSO- http://kong:8000/ 2>&1 | head -5
# Expect: HTTP/1.1 ... (Kong responds)

# From the host — should fail (Kong has no host port)
curl -fsS --connect-timeout 2 http://localhost:8000/ && echo "FAIL: Kong is exposed on host" || echo "OK: Kong not on host"
```

- [ ] **Step 8: Verify Postgres has no host port**

```bash
nc -z localhost 5432 && echo "FAIL: Postgres is exposed" || echo "OK: Postgres not on host"
nc -z localhost 6543 && echo "FAIL: Pooler is exposed" || echo "OK: Pooler not on host"
```

- [ ] **Step 9: Tear down**

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    --env-file .env.prod.local \
    down -v

# Remove the test env file (NEVER commit)
rm -f .env.prod.local

# Remove the /etc/hosts entry
sudo sed -i.bak '/license-forge prod overlay verification/,+1d' /etc/hosts
sudo rm -f /etc/hosts.bak
```

- [ ] **Step 10: Note any deviations**

If any of Steps 5–8 produced a `FAIL:`, fix the relevant compose entry, re-run the affected step. If the `web` build failed, fix and re-run Task 1.

If everything passed: the prod overlay is ready for deployment. Final verification of TLS cert issuance + the three vhosts will happen during VPS deploy (Task 5's runbook step 6).

- [ ] **Step 11: Commit any fixes**

If steps 5–8 surfaced fixes, commit them:

```bash
git add infrastructure/docker/docker-compose.prod.yml
git commit -m "fix(docker): <specific fix>"
```

If no fixes were needed, this step is a no-op.

---

## Self-Review Checklist (engineer runs this before considering the work done)

Run this once after completing all six tasks:

- [ ] **Spec coverage:** every section of `docs/superpowers/specs/2026-04-27-prod-docker-compose-design.md` is implemented.
- [ ] **No host ports except nginx:** `docker compose ... config` shows `published:` only under nginx.
- [ ] **No SMTP env in auth:** `GOTRUE_SMTP_HOST`, `_USER`, `_PASS` all empty.
- [ ] **Studio fails closed:** with `STUDIO_ALLOWED_CIDRS=` (empty), `studio.<domain>` returns 403 (verify on VPS).
- [ ] **Web bundle has correct API URL:** `docker exec supabase-web grep -or "api\.<domain>" /usr/share/nginx/html | head` finds it (verify on VPS).
- [ ] **`.env.prod` is `chmod 600`** on the VPS.
- [ ] **`.env.prod` is in `.gitignore`** — verify with `git check-ignore infrastructure/docker/.env.prod` (should return the path with exit 0).
- [ ] **No `privileged: true`** anywhere in the merged config.
- [ ] **All `cap_drop: [ALL]`** confirmed for db, kong, auth, rest, realtime, storage, supavisor, meta, imgproxy, vector, functions, analytics, studio, web, nginx.

If any check fails, fix the underlying compose/template, commit, re-verify.

---

## Open Items (deferred to first VPS deploy, not blocking implementation)

These get resolved against a running deployment, not a local test:

1. **Confirm `cap_add` set for nginx is minimal.** Spec lists `[NET_BIND_SERVICE, CHOWN, SETUID, SETGID, DAC_OVERRIDE]`. Test by removing one at a time and watching for failures during cert renewal.
2. **Tighten `read_only` for studio/functions/analytics** if runtime allows — try flipping each to `read_only: true` + `tmpfs:` and watch logs for write-failures.
3. **Verify `GOTRUE_EXTERNAL_EMAIL_ENABLED` is the correct env var name** for the GoTrue version used in this stack. If the var is unrecognized, the GoTrue defaults will apply — verify by attempting an email signup against a deployed instance and confirming it's rejected. Alternative knobs if needed: `GOTRUE_DISABLE_SIGNUP=true` (blocks all signup), `GOTRUE_MAILER_AUTOCONFIRM=true` (no emails sent).
4. **Verify Vector log discovery works with the read-only docker socket mount.** If Vector logs show "permission denied" on the socket, the socket needs different perms or Vector's user needs adjustment.

These are followups, not part of the initial plan delivery. Track as TODOs in the runbook.
