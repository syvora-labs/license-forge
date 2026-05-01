# Prod Self-Signed Overlay — Design

## Problem

The hardened production overlay (`docker-compose.prod.yml`) is built for a real VPS: outer nginx terminates TLS using Let's Encrypt certs fetched at startup by `jonasal/nginx-certbot` over the ACME HTTP-01 challenge. Locally, with `PROXY_DOMAIN=licenseforge.local`, ACME cannot work — Let's Encrypt refuses non-public TLDs and the `.local` host isn't reachable from the public internet anyway. The result is that no cert is ever written to `/etc/letsencrypt/live/`, the HTTPS server blocks fail to load a certificate, and the browser cannot reach the SPA, Studio, or the Kong API gateway through the prod nginx.

We want a way to bring the prod stack up locally with the **same** outer nginx template, vhost layout, and service hardening — but with self-signed certs instead of ACME — so the three production URLs (`https://app.<domain>`, `https://api.<domain>`, `https://studio.<domain>`) are reachable from a browser on the same host.

## Goals

- Browseable local deployment of the prod stack at all three vhosts.
- Reuses `volumes/proxy/nginx/supabase-nginx-prod.conf.tpl` unchanged.
- Preserves every hardening flag from `docker-compose.prod.yml` (caps, `read_only`, `security_opt`, mem/cpu limits, dropped host ports on internal services).
- Minimal new surface: one overlay file, one helper script, one cert directory.

## Non-goals

- Automating hosts-file edits or browser trust-store installation. The script prints the commands; the operator runs them once.
- A second env file. The overlay reads `.env.prod` as-is.
- Replacing or restructuring the prod overlay. Self-signed mode is a sibling, not a fork.
- Production use. This overlay is a local-only convenience; nothing prevents the operator from misusing it on a public host, but the runbook continues to point at the Let's Encrypt path.

## Architecture

### Invocation

```
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.prod.selfsigned.yml \
  --env-file .env.prod \
  up -d
```

The selfsigned overlay stacks on top of the prod overlay. Compose merges the two; only the `nginx` service changes.

### Files

| Path | Status | Purpose |
| --- | --- | --- |
| `infrastructure/docker/docker-compose.prod.selfsigned.yml` | new | Overrides only the `nginx` service: vanilla image, bind-mounted self-signed cert dir, simplified entrypoint command. |
| `infrastructure/docker/utils/gen-selfsigned-certs.sh` | new | One-shot generator: local CA + leaf cert with three SANs, materialized at the paths the existing nginx template expects. |
| `infrastructure/docker/volumes/proxy/letsencrypt-selfsigned/` | new (gitignored) | Output dir for the script; bind-mounted into the container at `/etc/letsencrypt`. |
| `infrastructure/docker/volumes/proxy/nginx/supabase-nginx-prod.conf.tpl` | unchanged | Same template, same cert paths. |
| `.gitignore` | edited | Add the self-signed cert output dir. |

### `nginx` service overrides (in `docker-compose.prod.selfsigned.yml`)

- `image: nginx:1.29-alpine` — drops `jonasal/nginx-certbot` and the ACME daemon entirely.
- `volumes: !reset []`, then explicitly:
    - `./volumes/proxy/nginx/supabase-nginx-prod.conf.tpl:/etc/nginx/supabase-nginx-prod.conf.tpl:ro`
    - `./volumes/proxy/letsencrypt-selfsigned:/etc/letsencrypt:ro`

  We `!reset` because Compose merges service `volumes` by appending, not by container target — without it, the prod overlay's named volume `nginx_letsencrypt:/etc/letsencrypt` would still appear in the merged config alongside our bind mount.
- `command:` — identical shell to prod for the htpasswd write, IP allowlist generation, and `envsubst` template render, but ends with `exec nginx -g 'daemon off;'` instead of `/scripts/start_nginx_certbot.sh`.
- Everything else (`cap_drop`, `cap_add`, `security_opt`, `ports`, `mem_limit`, `cpus`, env vars) inherits from `docker-compose.prod.yml` unchanged.

### `gen-selfsigned-certs.sh`

- Resolves `PROXY_DOMAIN` from `.env.prod` (or `ENV_FILE` override, matching the recent `cc00ee9` commit pattern); falls back to `licenseforge.local`.
- Output root: `volumes/proxy/letsencrypt-selfsigned/` relative to the script's compose dir.
- Steps:
    1. Generate a local CA (`ca.key` + `ca.crt`) with CN `License Forge Local CA`.
    2. Generate one leaf key + CSR with `subjectAltName = DNS:app.<d>, DNS:api.<d>, DNS:studio.<d>`.
    3. Sign the leaf with the CA (validity 825 days; long enough that local devs aren't regenerating frequently, short enough to encourage rotation hygiene).
    4. Materialize the leaf at all three of `live/{app,api,studio}.<d>/`:
        - `fullchain.pem` = leaf + CA
        - `privkey.pem` = leaf private key
        - `chain.pem` = CA cert (used by `ssl_trusted_certificate` for OCSP stapling — even though the template's `ssl_stapling on` won't actually staple for self-signed, the file must exist)
    5. Generate `dhparams/dhparam.pem` at 2048 bits (4096 takes 30+ seconds on Windows; not worth the wait for self-signed local use).
- Idempotent: existing files are kept unless `--force` is passed.
- Tail output: prints the absolute path to `ca.crt` and the one-line PowerShell command to install it into the Windows Trusted Root store, plus the hosts-file line to add.

### Operator flow

1. `bash ./utils/gen-selfsigned-certs.sh` (run once, or after rotating `PROXY_DOMAIN`).
2. Add to `C:\Windows\System32\drivers\etc\hosts`:
   `127.0.0.1 app.licenseforge.local api.licenseforge.local studio.licenseforge.local`
3. (Optional, removes browser warning) Install `ca.crt` into Windows Trusted Root via the printed command.
4. `docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.prod.selfsigned.yml --env-file .env.prod up -d`
5. Browse `https://app.licenseforge.local`, `https://studio.licenseforge.local` (basic-auth + IP allowlist gated), `https://api.licenseforge.local/...`.

## Trade-offs

- **Self-signed leaf, not mkcert.** Pure-bash + `openssl` works under Git Bash with no extra deps. Browser shows a warning until the CA is trusted; trusting it is one PowerShell command.
- **Vanilla `nginx:1.29-alpine` instead of jonasal.** We give up automatic dhparam generation and renewal hooks, but those are useless without ACME; the cost is one extra openssl call in our generator.
- **Same `.env.prod`.** Avoids a parallel env file. The `STUDIO_ALLOWED_CIDRS` value in `.env.prod` already includes `0.0.0.0/0` for local testing per the runbook.
- **Bind mount over named volume.** A bind mount is required to share generated certs from the host; the named volume `nginx_letsencrypt` defined in prod.yml stays defined but unused under this overlay.

## Risks / failure modes

- **Hosts file not edited.** Browser fails to resolve. Surface this clearly in script output.
- **Stale certs after `PROXY_DOMAIN` change.** `--force` regenerates. The script could detect the mismatch by reading the SAN of an existing leaf, but that's optimisation; the easier UX is "if you change the domain, run the script with `--force`".
- **Windows trust store bypass.** Even after installing the CA, browsers using their own trust store (Firefox) still warn. Document the limitation in the script tail.
- **Compose `volumes` merge surprise.** If we don't `!reset`, the named volume mount from prod.yml lingers; verified by `docker compose ... config nginx` during testing.

## Out of scope

- Automating Windows hosts-file edits.
- Adding a Linux/macOS-specific trust install path beyond a one-line hint.
- A separate make/just/npm target wrapping the whole flow.
