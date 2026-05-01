#!/usr/bin/env bash
# Generate a local CA + leaf cert for the prod self-signed overlay.
# Materialises the leaf at the three Let's-Encrypt-shaped paths the
# existing nginx template expects (live/<host>/{fullchain,privkey,chain}.pem).
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env.prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$COMPOSE_DIR/volumes/proxy/letsencrypt-selfsigned"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        -h|--help)
            cat <<USAGE
Usage: ENV_FILE=.env.prod $0 [--force]

Generates a self-signed CA and leaf cert covering app/api/studio.<PROXY_DOMAIN>,
materialising the leaf at the LE-shaped paths the prod nginx template expects.

  --force, -f   Regenerate even if certs already exist.
USAGE
            exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

PROXY_DOMAIN=""
if [ -f "$COMPOSE_DIR/$ENV_FILE" ]; then
    PROXY_DOMAIN="$(grep -E '^PROXY_DOMAIN=' "$COMPOSE_DIR/$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '\r')"
fi
PROXY_DOMAIN="${PROXY_DOMAIN:-licenseforge.local}"

APP="app.${PROXY_DOMAIN}"
API="api.${PROXY_DOMAIN}"
STUDIO="studio.${PROXY_DOMAIN}"

CA_DIR="$OUT_DIR"
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
LEAF_KEY="$CA_DIR/leaf.key"
LEAF_CSR="$CA_DIR/leaf.csr"
LEAF_CRT="$CA_DIR/leaf.crt"
DH_DIR="$CA_DIR/dhparams"
DH_PEM="$DH_DIR/dhparam.pem"

mkdir -p "$CA_DIR" "$DH_DIR"

# Idempotency: skip if everything is already in place.
have_all=1
for d in "$APP" "$API" "$STUDIO"; do
    for f in fullchain.pem privkey.pem chain.pem; do
        [ -f "$CA_DIR/live/$d/$f" ] || have_all=0
    done
done
[ -f "$CA_CRT" ] || have_all=0
[ -f "$DH_PEM" ] || have_all=0

if [ "$have_all" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
    echo "Self-signed certs already present at: $CA_DIR"
    echo "Pass --force to regenerate."
    exit 0
fi

echo "==> Generating local CA"
openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
# MSYS_NO_PATHCONV=1 prevents Git Bash from mangling the /CN= subject as a path.
# File paths must be in native Windows format for the same reason (cygpath -w fallback).
_CA_KEY_ARG="$CA_KEY"; _CA_CRT_ARG="$CA_CRT"
if command -v cygpath >/dev/null 2>&1; then
    _CA_KEY_ARG="$(cygpath -w "$CA_KEY")"
    _CA_CRT_ARG="$(cygpath -w "$CA_CRT")"
fi
MSYS_NO_PATHCONV=1 openssl req -x509 -new -nodes -key "$_CA_KEY_ARG" -sha256 -days 3650 \
    -subj "/CN=License Forge Local CA" \
    -out "$_CA_CRT_ARG" 2>/dev/null

echo "==> Generating leaf cert with SANs ($APP, $API, $STUDIO)"
SAN_CNF="$(mktemp)"
trap 'rm -f "$SAN_CNF"' EXIT
cat >"$SAN_CNF" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $APP
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt
[alt]
DNS.1 = $APP
DNS.2 = $API
DNS.3 = $STUDIO
EOF

openssl genrsa -out "$LEAF_KEY" 2048 2>/dev/null
openssl req -new -key "$LEAF_KEY" -out "$LEAF_CSR" -config "$SAN_CNF" 2>/dev/null
openssl x509 -req -in "$LEAF_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$LEAF_CRT" -days 825 -sha256 \
    -extensions v3_req -extfile "$SAN_CNF" 2>/dev/null

echo "==> Materialising leaf at LE-shaped paths"
for d in "$APP" "$API" "$STUDIO"; do
    target="$CA_DIR/live/$d"
    mkdir -p "$target"
    cat "$LEAF_CRT" "$CA_CRT" >"$target/fullchain.pem"
    cp "$LEAF_KEY" "$target/privkey.pem"
    cp "$CA_CRT" "$target/chain.pem"
    chmod 644 "$target"/*.pem
done

if [ ! -f "$DH_PEM" ] || [ "$FORCE" -eq 1 ]; then
    echo "==> Generating dhparams (2048 bit)"
    openssl dhparam -out "$DH_PEM" 2048 2>/dev/null
fi

rm -f "$LEAF_CSR" "$CA_DIR/ca.srl"

CA_CRT_DISPLAY="$CA_CRT"
if command -v cygpath >/dev/null 2>&1; then
    CA_CRT_DISPLAY="$(cygpath -w "$CA_CRT")"
fi

cat <<EOF

============================================================
Self-signed certs ready for: $PROXY_DOMAIN
Cert dir: $CA_DIR
============================================================

NEXT STEPS

1. Add to C:\\Windows\\System32\\drivers\\etc\\hosts (admin):
   127.0.0.1 $APP $API $STUDIO

2. (Optional) Trust the local CA in Windows so browsers stop warning.
   Run in an elevated PowerShell:
   Import-Certificate -FilePath '$CA_CRT_DISPLAY' -CertStoreLocation Cert:\\LocalMachine\\Root

3. Bring up the stack with the self-signed overlay:
   docker compose -f docker-compose.yml \\
                  -f docker-compose.prod.yml \\
                  -f docker-compose.prod.selfsigned.yml \\
                  --env-file .env.prod up -d

4. Browse:
   https://$APP            # SPA
   https://$STUDIO         # Studio (basic-auth + IP allowlist)
   https://$API/           # Kong API gateway

Firefox uses its own trust store — add $CA_CRT_DISPLAY under
Settings → Privacy → Certificates → View Certificates → Authorities.
EOF
