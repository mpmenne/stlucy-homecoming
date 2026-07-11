#!/usr/bin/env bash
#
# Points stlucyhomecoming.com (apex + www) at GitHub Pages via the Cloudflare
# API, replacing whatever records exist (e.g. the old parking-page records).
# The signup.* record is never touched.
#
# GitHub can only issue the Pages Let's Encrypt certificate while the records
# are DNS-only (grey cloud), so records are created unproxied. Once the cert
# is issued and HTTPS is enforced on the Pages side, re-run with --proxy to
# flip both hostnames to proxied (orange cloud) — required for the Cloudflare
# Access gate — and set zone SSL to strict + always-use-HTTPS.
#
# Secrets: reads ~/.config/stlucy-homecoming/cf.env, which must define
#   CLOUDFLARE_API_TOKEN  (Zone:Read, DNS:Edit, Zone Settings:Edit)
# CF_ZONE_ID is looked up and cached back into cf.env.
#
# Usage: ./scripts/setup-pages-dns.sh [--proxy]
set -euo pipefail

ZONE_NAME=stlucyhomecoming.com
GH_PAGES_CNAME=mpmenne.github.io
GH_PAGES_A=(185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153)
CF_ENV="$HOME/.config/stlucy-homecoming/cf.env"
API=https://api.cloudflare.com/client/v4

# shellcheck source=/dev/null
source "$CF_ENV"
: "${CLOUDFLARE_API_TOKEN:?missing in $CF_ENV}"

cfapi() {
  local method=$1 path=$2; shift 2
  curl -fsS -X "$method" "$API$path" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" "$@"
}

if [ -z "${CF_ZONE_ID:-}" ]; then
  CF_ZONE_ID=$(cfapi GET "/zones?name=$ZONE_NAME" | jq -r '.result[0].id')
  [ "$CF_ZONE_ID" != null ] || { echo "Zone $ZONE_NAME not found for this token" >&2; exit 1; }
  echo "CF_ZONE_ID=$CF_ZONE_ID" >> "$CF_ENV"
  echo "==> Cached CF_ZONE_ID in $CF_ENV"
fi

set_proxied() { # name proxied
  local name=$1 proxied=$2 recs
  recs=$(cfapi GET "/zones/$CF_ZONE_ID/dns_records?name=$name" | jq -c '.result[]')
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    local id type content
    id=$(jq -r .id <<<"$rec"); type=$(jq -r .type <<<"$rec"); content=$(jq -r .content <<<"$rec")
    echo "==> $name $type $content -> proxied=$proxied"
    cfapi PATCH "/zones/$CF_ZONE_ID/dns_records/$id" \
      --data "{\"proxied\":$proxied}" > /dev/null
  done <<< "$recs"
}

if [ "${1:-}" = "--proxy" ]; then
  set_proxied "$ZONE_NAME" true
  set_proxied "www.$ZONE_NAME" true
  echo "==> Zone SSL mode: strict"
  cfapi PATCH "/zones/$CF_ZONE_ID/settings/ssl" --data '{"value":"strict"}' > /dev/null
  echo "==> Always use HTTPS: on"
  cfapi PATCH "/zones/$CF_ZONE_ID/settings/always_use_https" --data '{"value":"on"}' > /dev/null
  echo "Done. Apex + www now proxied through Cloudflare (Access gate can take effect)."
  exit 0
fi

delete_records() { # name
  local name=$1 ids
  ids=$(cfapi GET "/zones/$CF_ZONE_ID/dns_records?name=$name" \
    | jq -r '.result[] | select(.type=="A" or .type=="AAAA" or .type=="CNAME") | .id')
  for id in $ids; do
    echo "==> Deleting old record $id for $name"
    cfapi DELETE "/zones/$CF_ZONE_ID/dns_records/$id" > /dev/null
  done
}

delete_records "$ZONE_NAME"
delete_records "www.$ZONE_NAME"

for ip in "${GH_PAGES_A[@]}"; do
  echo "==> Creating A $ZONE_NAME -> $ip (DNS only)"
  cfapi POST "/zones/$CF_ZONE_ID/dns_records" \
    --data "{\"type\":\"A\",\"name\":\"$ZONE_NAME\",\"content\":\"$ip\",\"proxied\":false,\"ttl\":1}" > /dev/null
done

echo "==> Creating CNAME www.$ZONE_NAME -> $GH_PAGES_CNAME (DNS only)"
cfapi POST "/zones/$CF_ZONE_ID/dns_records" \
  --data "{\"type\":\"CNAME\",\"name\":\"www.$ZONE_NAME\",\"content\":\"$GH_PAGES_CNAME\",\"proxied\":false,\"ttl\":1}" > /dev/null

echo
echo "Done. Wait for GitHub Pages to issue the HTTPS certificate, then re-run:"
echo "  $0 --proxy"
