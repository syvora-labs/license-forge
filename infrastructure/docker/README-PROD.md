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

Because prod sets `GOTRUE_EXTERNAL_EMAIL_ENABLED=false` and
`GOTRUE_DISABLE_SIGNUP=true`, these flows will hard-fail at runtime:

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
