# License Forge — Local Self-Signed Variant of the Prod Stack

This runbook covers running the production stack **on your local machine**
with self-signed TLS instead of Let's Encrypt — useful for browser-testing
the real prod nginx template, vhost layout, CSP headers, and basic-auth
flow without a public domain.

For a real VPS deployment, see [`README-PROD.md`](./README-PROD.md). This
file is a sibling — same compose base, same hardening, only the outer
`nginx` service is swapped to skip ACME and serve a locally generated cert.

---

## When to use this

- ✅ Browser-test the SPA, Studio, or Kong gateway as they'll behave
  behind the prod nginx (CSP, HSTS, rate-limit zones, basic-auth).
- ✅ Verify a CSP / cookie / cross-origin change against the real
  `app` ↔ `api` split, not against `localhost:5173` ↔ `localhost:8000`.
- ❌ **Don't use this for actual development.** Plain `docker compose up`
  + `cd web && yarn dev` is faster and has hot reload.
- ❌ **Don't use this on a public host.** It serves a self-signed cert
  and skips ACME. Real prod uses [`README-PROD.md`](./README-PROD.md).

---

## Prerequisites

- Docker Desktop on Windows / Docker on Linux/macOS
- Git Bash (Windows) or any POSIX shell — the cert script is portable
- Local admin rights, twice:
    1. To edit your `hosts` file (one line, one time)
    2. To install the local CA into your OS trust store (one-time, optional
       but removes browser warnings)
- An `.env.prod` already populated. If you don't have one yet:
    ```bash
    cd infrastructure/docker
    cp .env.prod.example .env.prod
    ENV_FILE=.env.prod bash ./utils/generate-keys.sh --update-env
    # then edit .env.prod and at minimum set:
    #   PROXY_DOMAIN=licenseforge.local      # or any *.local you like
    #   STUDIO_ALLOWED_CIDRS=0.0.0.0/0       # local-only, fine to allow all
    #   DASHBOARD_USERNAME / DASHBOARD_PASSWORD
    ```

---

## First-time setup (5 minutes)

All commands run from `infrastructure/docker/`.

### 1. Generate the self-signed CA + leaf cert

```bash
bash ./utils/gen-selfsigned-certs.sh
```

This creates a local CA and a single leaf cert with SANs for
`app.<PROXY_DOMAIN>`, `api.<PROXY_DOMAIN>`, and `studio.<PROXY_DOMAIN>`.
Output goes to `volumes/proxy/letsencrypt-selfsigned/` (gitignored).

The script is idempotent — re-running is a no-op. Pass `--force` to
regenerate (e.g. after changing `PROXY_DOMAIN`).

When done, the script prints the next-step commands tailored to your
machine. Follow steps 2–4 below or copy them from the script's output.

### 2. Add hosts-file entries

Add this one line so your three subdomains resolve to your local Docker.

**Windows** (open Notepad as Administrator, edit
`C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1 app.licenseforge.local api.licenseforge.local studio.licenseforge.local
```

**Linux / macOS** (`sudo nano /etc/hosts`):

```
127.0.0.1 app.licenseforge.local api.licenseforge.local studio.licenseforge.local
```

Replace `licenseforge.local` if you set a different `PROXY_DOMAIN`.

### 3. (Optional) Trust the local CA

Without this step, browsers warn on every page load. With it, `https://`
shows a normal padlock.

**Windows** (elevated PowerShell):

```powershell
Import-Certificate -FilePath 'C:\repositories\local\github\license-forge\infrastructure\docker\volumes\proxy\letsencrypt-selfsigned\ca.crt' -CertStoreLocation Cert:\LocalMachine\Root
```

**macOS:**

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \
    volumes/proxy/letsencrypt-selfsigned/ca.crt
```

**Linux** (Debian/Ubuntu):

```bash
sudo cp volumes/proxy/letsencrypt-selfsigned/ca.crt /usr/local/share/ca-certificates/license-forge-local-ca.crt
sudo update-ca-certificates
```

**Firefox** ignores the OS trust store. Add the CA manually:
Settings → Privacy & Security → Certificates → View Certificates →
Authorities → Import → select `ca.crt` → check "Trust this CA to identify
websites".

### 4. Bring up the stack

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.prod.selfsigned.yml \
    --env-file .env.prod \
    up -d
```

First boot rebuilds the `web` image (~30s) and pulls `nginx:1.29-alpine`
(~20 MB). Subsequent boots are seconds.

Verify:

```bash
docker compose ps           # all services healthy
docker logs supabase-nginx  # nginx workers started, no [emerg]
```

### 5. Browse

| URL | What's there |
| --- | --- |
| `https://app.licenseforge.local` | The SPA |
| `https://studio.licenseforge.local` | Supabase Studio (basic-auth: `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`) |
| `https://api.licenseforge.local/...` | Kong API gateway |

---

## What this overlay actually changes

Only the outer `nginx` service. Everything else (db, auth, kong, studio,
storage, realtime, edge functions, vector, web container, …) is identical
to the prod overlay, including all caps, `read_only` flags, `security_opt`,
mem/cpu limits, ports.

`docker-compose.prod.selfsigned.yml` overrides the `nginx` service to:

| Field | Prod (`docker-compose.prod.yml`) | Self-signed |
| --- | --- | --- |
| `image` | `jonasal/nginx-certbot:6.0.1-nginx1.29.5` | `nginx:1.29-alpine` |
| TLS certs | Fetched from Let's Encrypt at boot via ACME HTTP-01 | Read from a host bind-mount populated by `gen-selfsigned-certs.sh` |
| Entrypoint | jonasal default → `/scripts/start_nginx_certbot.sh` | `/bin/sh -c "<inline render + exec nginx>"` |
| `volumes` | Named volume `nginx_letsencrypt:/etc/letsencrypt` | Bind mount `./volumes/proxy/letsencrypt-selfsigned:/etc/letsencrypt:ro` |

Same nginx template
(`volumes/proxy/nginx/supabase-nginx-prod.conf.tpl`), same htpasswd /
allowlist / envsubst flow, same vhost layout, same CSP headers, same
rate-limit zones.

---

## Common operations

### Regenerate certs after changing `PROXY_DOMAIN`

```bash
bash ./utils/gen-selfsigned-certs.sh --force
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.prod.selfsigned.yml \
    --env-file .env.prod \
    up -d --no-deps --force-recreate nginx
```

Don't forget to update your hosts file with the new subdomains.

### Restart just nginx

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.prod.selfsigned.yml \
    --env-file .env.prod \
    up -d --no-deps --force-recreate nginx
```

### Tear down and start clean

```bash
docker compose \
    -f docker-compose.yml \
    -f docker-compose.prod.yml \
    -f docker-compose.prod.selfsigned.yml \
    --env-file .env.prod \
    down
```

The cert dir at `volumes/proxy/letsencrypt-selfsigned/` survives `down`.
Delete it manually if you want a fresh CA.

### Switch back to ACME prod mode

Drop the third `-f` from your compose invocation. The `nginx_letsencrypt`
named volume kicks back in and `jonasal/nginx-certbot` will try to fetch
real certs — which won't work for `*.local` domains. Useful only on a
real public domain.

---

## Known limitations and gotchas

- **Self-signed certs require manual trust, per machine.** This is a
  one-time install per dev machine. If teammates need to browse the
  same stack, each of them runs steps 1–3.

- **Firefox uses its own trust store.** Adding the CA to the OS trust
  store covers Chrome, Edge, Safari. Firefox needs the manual import in
  step 3 above.

- **Windows `curl --cacert ca.crt` returns error 60 unless you also
  pass `--ssl-no-revoke`.** This is because the curl shipped with Git
  Bash uses the SChannel TLS backend, which enforces CRL/OCSP revocation
  checks even for explicitly-trusted custom CAs, and the local CA has no
  CRL Distribution Point. Browsers don't have this problem after step 3
  because Windows' trust store marks locally-installed roots as
  revocation-exempt. To verify the chain from the command line on
  Windows, use one of:
    ```bash
    curl --cacert volumes/proxy/letsencrypt-selfsigned/ca.crt --ssl-no-revoke https://app.licenseforge.local/
    openssl s_client -connect 127.0.0.1:443 -servername app.licenseforge.local \
                     -CAfile volumes/proxy/letsencrypt-selfsigned/ca.crt < /dev/null
    ```

- **No automatic renewal.** The leaf cert is valid 825 days, the CA
  3650 days. If you somehow keep a single workstation alive that long,
  re-run `gen-selfsigned-certs.sh --force`.

- **`STUDIO_ALLOWED_CIDRS` parsing is whitespace-only.** Comma-separated
  values silently produce a broken nginx allow line. Use spaces between
  CIDRs (same constraint as the prod overlay — the loop is identical).

- **`apk add gettext` runs at every container start.** This overlay
  doesn't bake `envsubst` into a custom image — it installs it on boot
  to keep the change a single file. Failure mode if you're offline:
  the container exits non-zero immediately with a clear `apk` error.

---

## Troubleshooting

**Browser shows `ERR_CERT_AUTHORITY_INVALID` even after step 3.**
- Restart the browser fully (Chrome caches trust decisions per session).
- For Firefox, see step 3's Firefox notes — OS trust store doesn't apply.
- Verify the cert really chains:
  `openssl s_client -connect 127.0.0.1:443 -servername app.licenseforge.local -CAfile volumes/proxy/letsencrypt-selfsigned/ca.crt < /dev/null | head`
  Look for `Verify return code: 0 (ok)`.

**Browser shows `ERR_CONNECTION_REFUSED` or just hangs.**
- Hosts file not edited (step 2). Run
  `ping app.licenseforge.local` — should resolve to `127.0.0.1`. If it
  hits the public DNS instead, your hosts entry isn't loading.
- nginx isn't running. `docker logs supabase-nginx --tail 30` and look
  for `[emerg]` lines.

**`docker compose up` reports nginx restarting.**
- Most likely the cert dir is missing or empty. Run
  `ls volumes/proxy/letsencrypt-selfsigned/live/app.licenseforge.local/` —
  expect `chain.pem`, `fullchain.pem`, `privkey.pem`. If empty, run
  `bash ./utils/gen-selfsigned-certs.sh`.

**Cert script fails with `unable to load private key` or weird `/CN=`
errors on Windows.**
- The script uses `MSYS_NO_PATHCONV=1` + `cygpath -w` on the one
  openssl call that takes a `/CN=` subject, which Git Bash would
  otherwise rewrite as `C:\N=...`. If you've modified the script and
  removed that wrapper, restore it.

**Studio basic-auth not accepting the password.**
- The htpasswd is regenerated on every nginx start from
  `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` in `.env.prod`. If you
  changed those, restart nginx (see "Restart just nginx" above).

---

## Files involved

| Path | Role |
| --- | --- |
| `docker-compose.prod.selfsigned.yml` | Overlay; overrides only the `nginx` service |
| `utils/gen-selfsigned-certs.sh` | Generates the local CA + leaf cert |
| `volumes/proxy/letsencrypt-selfsigned/` | Generated certs (gitignored) |
| `volumes/proxy/nginx/supabase-nginx-prod.conf.tpl` | nginx config template (shared with prod, unchanged) |
| `.env.prod` | Same env file the prod overlay uses |
