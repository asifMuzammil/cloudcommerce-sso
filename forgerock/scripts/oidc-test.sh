#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Manual OIDC Authorization Code flow test against ForgeRock AM - no app needed.
#
#   1. Run this script: it prints an /authorize URL.
#   2. Open the URL in a browser, log in as a realm user.
#   3. The browser lands on REDIRECT_URI (nothing listens there yet, that's fine).
#      Copy the "code" value from the address bar and paste it here (it expires
#      in ~2 minutes and works only once).
#   4. The script exchanges the code for tokens and prints the ID token claims.
#
# Reads FORGEROCK_CLIENT_SECRET from ../medusa/.env (gitignored).
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/../.."

AM_HOST=${AM_HOST:-am.localtest.me:8080}
REALM_PATH=${REALM_PATH:-realms/root/realms/cloudcommerce}
CLIENT_ID=${CLIENT_ID:-medusa-storefront}
REDIRECT_URI=${REDIRECT_URI:-http://localhost:8000/auth/forgerock/callback}
BASE="http://${AM_HOST}/am/oauth2/${REALM_PATH}"

SECRET=$(grep -E '^FORGEROCK_CLIENT_SECRET=' medusa/.env | cut -d= -f2-)
[ -n "$SECRET" ] || { echo "FORGEROCK_CLIENT_SECRET missing in medusa/.env"; exit 1; }

STATE=$(openssl rand -hex 8)
NONCE=$(openssl rand -hex 8)
ENC_REDIRECT=$(jq -rn --arg u "$REDIRECT_URI" '$u|@uri')

echo
echo "1) Open this URL in the browser and log in:"
echo
echo "${BASE}/authorize?client_id=${CLIENT_ID}&response_type=code&scope=openid%20profile%20email&redirect_uri=${ENC_REDIRECT}&state=${STATE}&nonce=${NONCE}"
echo
echo "   Address bar must show ...?code=...&state=${STATE}"
echo "   If it shows ?error=... instead, fix that first (no code was issued)."
echo
read -r -p "2) Paste the code (or the WHOLE address-bar URL) here: " CODE
# Accept the full redirect URL too: pull out code= and check state= matches.
if [[ "$CODE" == *"code="* ]]; then
  GOT_STATE=$(sed -n 's/.*[?&]state=\([^&]*\).*/\1/p' <<<"$CODE")
  CODE=$(sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' <<<"$CODE")
  [ "$GOT_STATE" = "$STATE" ] || { echo "state mismatch (got '$GOT_STATE', expected '$STATE') - use the URL printed by THIS run."; exit 1; }
fi
[ -n "$CODE" ] || { echo "No code entered."; exit 1; }

TOK=$(curl -s -u "${CLIENT_ID}:${SECRET}" \
  -H "Host: ${AM_HOST}" \
  -d grant_type=authorization_code \
  -d "code=${CODE}" \
  --data-urlencode "redirect_uri=${REDIRECT_URI}" \
  "http://localhost:8080/am/oauth2/${REALM_PATH}/access_token")
unset CODE SECRET

if ! echo "$TOK" | jq -e '.id_token' >/dev/null; then
  echo "ERROR: $(echo "$TOK" | jq -r '"\(.error) - \(.error_description)"')"
  exit 1
fi

echo
echo "OK: tokens received (scope: $(echo "$TOK" | jq -r .scope))"
echo "ID token claims:"
echo "$TOK" | jq -r .id_token | cut -d. -f2 | python3 -c '
import sys, base64, json
p = sys.stdin.read().strip(); p += "=" * (-len(p) % 4)
c = json.loads(base64.urlsafe_b64decode(p))
keep = ("iss", "aud", "sub", "email", "given_name", "family_name", "nonce", "exp")
print(json.dumps({k: c.get(k) for k in keep}, indent=1))'
echo "(expected nonce: ${NONCE})"
