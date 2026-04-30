#!/bin/sh
#
# Rotate opaque API keys for a self-hosted Supabase installation.
#
# Regenerates SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY
# without touching the asymmetric key pair (JWKS) or JWT tokens.
#
# Usage:
#   sh rotate-new-api-keys.sh              # Interactive: prints keys, prompts to update $ENV_FILE
#   sh rotate-new-api-keys.sh --update-env # Prints keys and writes them to $ENV_FILE
#   sh rotate-new-api-keys.sh | tee keys   # Non-interactive: prints keys only
#
# ENV_FILE defaults to .env. Override with ENV_FILE=.env.prod ./rotate-new-api-keys.sh ...
#
# Prerequisites:
#   - $ENV_FILE file (run generate-keys.sh and add-new-auth-keys.sh first)
#   - node >= 16
#

set -e

ENV_FILE="${ENV_FILE:-.env}"

if ! command -v node >/dev/null 2>&1; then
    echo "Error: node (>= 16) is required but not found."
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found. Run generate-keys.sh first."
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

node -e '
const crypto = require("crypto");

const PROJECT_REF = "supabase-self-hosted";

function generateOpaqueKey(prefix) {
    const random = crypto.randomBytes(17).toString("base64url").slice(0, 22);
    const intermediate = prefix + random;
    const checksum = crypto.createHash("sha256")
        .update(PROJECT_REF + "|" + intermediate)
        .digest("base64url")
        .slice(0, 8);
    return intermediate + "_" + checksum;
}

const publishableKey = generateOpaqueKey("sb_publishable_");
const secretKey = generateOpaqueKey("sb_secret_");

console.log("SUPABASE_PUBLISHABLE_KEY=" + publishableKey);
console.log("SUPABASE_SECRET_KEY=" + secretKey);
' > "$tmpdir/output"

SUPABASE_PUBLISHABLE_KEY=$(grep '^SUPABASE_PUBLISHABLE_KEY=' "$tmpdir/output" | cut -d= -f2-)
SUPABASE_SECRET_KEY=$(grep '^SUPABASE_SECRET_KEY=' "$tmpdir/output" | cut -d= -f2-)

echo ""
echo "SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}"
echo "SUPABASE_SECRET_KEY=${SUPABASE_SECRET_KEY}"
echo ""

if [ "$1" = "--update-env" ]; then
    update_env=true
elif test -t 0; then
    printf "Update $ENV_FILE file? (y/N) "
    read -r REPLY
    case "$REPLY" in
        [Yy]) update_env=true ;;
        *) update_env=false ;;
    esac
else
    echo "Running non-interactively. Pass --update-env to write to $ENV_FILE."
    update_env=false
fi

if [ "$update_env" != "true" ]; then
    exit 0
fi

echo "Updating $ENV_FILE..."

for var in SUPABASE_PUBLISHABLE_KEY SUPABASE_SECRET_KEY; do
    eval "val=\$$var"
    if grep -q "^${var}=" "$ENV_FILE"; then
        sed -i.old -e "s|^${var}=.*$|${var}=${val}|" "$ENV_FILE"
    else
        echo "${var}=${val}" >> "$ENV_FILE"
    fi
done
