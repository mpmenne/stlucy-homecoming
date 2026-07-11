#!/usr/bin/env bash
#
# Removes the temporary Cloudflare Access gate from stlucyhomecoming.com,
# making the site public. Run this when stakeholders sign off.
#
# Secrets: reads ~/.config/stlucy-homecoming/cf.env (CLOUDFLARE_API_TOKEN,
# CF_ACCOUNT_ID).
#
# Usage: ./scripts/teardown-access.sh
set -euo pipefail

APP_NAME="stlucy-homecoming-staging-gate"
CF_ENV="$HOME/.config/stlucy-homecoming/cf.env"
APP_ID_FILE="$HOME/.config/stlucy-homecoming/access-app-id"
API=https://api.cloudflare.com/client/v4

# shellcheck source=/dev/null
source "$CF_ENV"
: "${CLOUDFLARE_API_TOKEN:?missing in $CF_ENV}"
: "${CF_ACCOUNT_ID:?missing in $CF_ENV}"

cfapi() {
  local method=$1 path=$2; shift 2
  curl -fsS -X "$method" "$API$path" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" "$@"
}

APP_ID=""
[ -f "$APP_ID_FILE" ] && APP_ID=$(cat "$APP_ID_FILE")
if [ -z "$APP_ID" ]; then
  APP_ID=$(cfapi GET "/accounts/$CF_ACCOUNT_ID/access/apps" \
    | jq -r --arg n "$APP_NAME" '.result[]? | select(.name==$n) | .id')
fi
if [ -z "$APP_ID" ]; then
  echo "No Access app named $APP_NAME found — nothing to tear down."
  exit 0
fi

echo "==> Deleting Access app $APP_ID"
cfapi DELETE "/accounts/$CF_ACCOUNT_ID/access/apps/$APP_ID" > /dev/null
rm -f "$APP_ID_FILE"
echo "Gate removed. The site is now public."
