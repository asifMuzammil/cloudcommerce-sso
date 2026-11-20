#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Copy the runtime secrets that bootstrap.sh generated (forgerock/.env) and the
# OIDC client secret (medusa/.env) into SSM Parameter Store as SecureString.
# Run once on the dev box after bootstrap.sh. Safe to re-run (overwrites).
# Values are never printed.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/../.."

PREFIX=${SSM_PREFIX:-/cloudcommerce/forgerock}
REGION=${AWS_REGION:-us-east-1}
KEYS_FORGEROCK="AM_PASSWORDS_AMADMIN_CLEAR AM_ENCRYPTION_KEY AM_AUTHENTICATION_SHARED_SECRET AM_OIDC_CLIENT_SUBJECT_IDENTIFIER_HASH_SALT"
KEYS_CLIENT="FORGEROCK_CLIENT_SECRET"

put() { # name value
  aws ssm put-parameter --region "$REGION" --name "$PREFIX/$1" --type SecureString \
    --value "$2" --overwrite --query Version --output text >/dev/null
  echo "stored  $PREFIX/$1"
}
val() { grep -E "^$1=" "$2" | head -1 | cut -d= -f2-; }

for k in $KEYS_FORGEROCK; do
  v=$(val "$k" forgerock/.env); [ -n "$v" ] || { echo "missing $k in forgerock/.env"; exit 1; }
  put "$k" "$v"
done
for k in $KEYS_CLIENT; do
  v=$(val "$k" medusa/.env); [ -n "$v" ] || { echo "missing $k in medusa/.env"; exit 1; }
  put "$k" "$v"
done
echo "Done. List (names only): aws ssm get-parameters-by-path --path $PREFIX --query 'Parameters[].Name'"
