#!/usr/bin/env bash
#
# Puts a temporary Cloudflare Access gate (email one-time PIN) in front of
# stlucyhomecoming.com + www while the site is a stakeholder-only proposal.
# The signup API subdomain is deliberately NOT gated — the site's JS calls it
# cross-origin and Access would break those requests; the API keeps its own
# CORS/honeypot/capacity guards.
#
# Idempotent — safe to re-run (e.g. to update the stakeholder email list, it
# replaces the allow policy).
#
# Requires the hostnames to be PROXIED (orange cloud) to actually gate
# traffic: run setup-pages-dns.sh --proxy after this script.
#
# Secrets: reads ~/.config/stlucy-homecoming/cf.env, which must define
#   CLOUDFLARE_API_TOKEN  (Access: Apps and Policies Edit; Access: Orgs,
#                          Identity Providers and Groups Edit)
#   CF_ACCOUNT_ID
# Optional:
#   CF_TEAM_NAME          (only used if the account has no Zero Trust org yet)
#
# Usage: STAKEHOLDER_EMAILS="a@x.com,b@y.com" ./scripts/setup-access.sh
set -euo pipefail

ZONE_NAME=stlucyhomecoming.com
APP_NAME="stlucy-homecoming-staging-gate"
CF_ENV="$HOME/.config/stlucy-homecoming/cf.env"
APP_ID_FILE="$HOME/.config/stlucy-homecoming/access-app-id"
API=https://api.cloudflare.com/client/v4

# shellcheck source=/dev/null
source "$CF_ENV"
: "${CLOUDFLARE_API_TOKEN:?missing in $CF_ENV}"
: "${CF_ACCOUNT_ID:?missing in $CF_ENV}"
: "${STAKEHOLDER_EMAILS:?set STAKEHOLDER_EMAILS=comma,separated,list}"

cfapi() {
  local method=$1 path=$2; shift 2
  curl -fsS -X "$method" "$API$path" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" "$@"
}

# 1. Zero Trust org (team domain) — required before any Access resources.
ORG_DOMAIN=$(cfapi GET "/accounts/$CF_ACCOUNT_ID/access/organizations" | jq -r '.result.auth_domain // empty')
if [ -z "$ORG_DOMAIN" ]; then
  : "${CF_TEAM_NAME:?no Zero Trust org on the account — set CF_TEAM_NAME in $CF_ENV (e.g. stlucy)}"
  echo "==> Creating Zero Trust org ${CF_TEAM_NAME}.cloudflareaccess.com"
  cfapi POST "/accounts/$CF_ACCOUNT_ID/access/organizations" \
    --data "{\"name\":\"St Lucy Homecoming\",\"auth_domain\":\"${CF_TEAM_NAME}.cloudflareaccess.com\"}" > /dev/null \
    || { echo "Org creation failed — do the one-minute Zero Trust onboarding in the dashboard (one.dash.cloudflare.com), then re-run." >&2; exit 1; }
  ORG_DOMAIN="${CF_TEAM_NAME}.cloudflareaccess.com"
fi
echo "==> Zero Trust org: $ORG_DOMAIN"

# 2. One-time PIN identity provider.
OTP_ID=$(cfapi GET "/accounts/$CF_ACCOUNT_ID/access/identity_providers" \
  | jq -r '.result[]? | select(.type=="onetimepin") | .id')
if [ -z "$OTP_ID" ]; then
  echo "==> Creating one-time PIN identity provider"
  OTP_ID=$(cfapi POST "/accounts/$CF_ACCOUNT_ID/access/identity_providers" \
    --data '{"name":"One-time PIN","type":"onetimepin","config":{}}' | jq -r '.result.id')
fi

# 3. Access application covering apex + www.
APP_ID=$(cfapi GET "/accounts/$CF_ACCOUNT_ID/access/apps" \
  | jq -r --arg n "$APP_NAME" '.result[]? | select(.name==$n) | .id')
APP_PAYLOAD=$(jq -n --arg name "$APP_NAME" --arg zone "$ZONE_NAME" --arg otp "$OTP_ID" '{
  name: $name,
  type: "self_hosted",
  domain: $zone,
  self_hosted_domains: [$zone, ("www." + $zone)],
  session_duration: "24h",
  app_launcher_visible: false,
  allowed_idps: [$otp],
  auto_redirect_to_identity: true
}')
if [ -z "$APP_ID" ]; then
  echo "==> Creating Access app $APP_NAME"
  APP_ID=$(cfapi POST "/accounts/$CF_ACCOUNT_ID/access/apps" --data "$APP_PAYLOAD" | jq -r '.result.id')
else
  echo "==> Updating Access app $APP_NAME"
  cfapi PUT "/accounts/$CF_ACCOUNT_ID/access/apps/$APP_ID" --data "$APP_PAYLOAD" > /dev/null
fi
echo "$APP_ID" > "$APP_ID_FILE"

# 4. Allow policy from the stakeholder email list (replaces existing).
INCLUDE=$(jq -nc --arg emails "$STAKEHOLDER_EMAILS" \
  '[$emails | split(",") | .[] | gsub("^\\s+|\\s+$";"") | select(length>0) | {email:{email:.}}]')
POLICY_ID=$(cfapi GET "/accounts/$CF_ACCOUNT_ID/access/apps/$APP_ID/policies" \
  | jq -r '.result[]? | select(.name=="Stakeholders") | .id')
POLICY_PAYLOAD=$(jq -nc --argjson inc "$INCLUDE" \
  '{name:"Stakeholders", decision:"allow", precedence:1, include:$inc}')
if [ -z "$POLICY_ID" ]; then
  echo "==> Creating allow policy for: $STAKEHOLDER_EMAILS"
  cfapi POST "/accounts/$CF_ACCOUNT_ID/access/apps/$APP_ID/policies" --data "$POLICY_PAYLOAD" > /dev/null
else
  echo "==> Updating allow policy for: $STAKEHOLDER_EMAILS"
  cfapi PUT "/accounts/$CF_ACCOUNT_ID/access/apps/$APP_ID/policies/$POLICY_ID" --data "$POLICY_PAYLOAD" > /dev/null
fi

echo
echo "Done. Gate is configured (app id saved to $APP_ID_FILE)."
echo "It takes effect once apex+www are proxied:  ./scripts/setup-pages-dns.sh --proxy"
echo "To remove the gate when the site goes public:  ./scripts/teardown-access.sh"
