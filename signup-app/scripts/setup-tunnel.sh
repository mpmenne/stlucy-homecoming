#!/usr/bin/env bash
#
# One-time Cloudflare Tunnel setup for the signup app.
#
# Uses the dockerized cloudflared CLI so nothing needs to be installed on the
# host. Credentials and config land in ./cloudflared/, which docker-compose
# mounts into the cloudflared sidecar container.
#
# Prereqs: the stlucyhomecoming.com zone must already be on your Cloudflare
# account (free plan is fine).
#
# Usage: ./scripts/setup-tunnel.sh
set -euo pipefail

TUNNEL_NAME="${TUNNEL_NAME:-stlucy-signup}"
HOSTNAME="${SIGNUP_HOSTNAME:-signup.stlucyhomecoming.com}"

cd "$(dirname "$0")/.."
mkdir -p cloudflared

if command -v cloudflared >/dev/null 2>&1; then
  # host binary: keep all state in ./cloudflared (credentials are written next
  # to the origin cert)
  cf() {
    TUNNEL_ORIGIN_CERT="$PWD/cloudflared/cert.pem" cloudflared "$@"
  }
else
  # dockerized fallback; the container runs as uid 65532, which must be able
  # to write credentials into the mounted dir
  chmod 777 cloudflared
  cf() {
    docker run --rm \
      -v "$PWD/cloudflared:/home/nonroot/.cloudflared" \
      cloudflare/cloudflared:latest "$@"
  }
fi

if [ ! -f cloudflared/cert.pem ]; then
  echo "==> Logging in to Cloudflare (a browser URL will be printed — open it and pick the stlucyhomecoming.com zone)"
  cf tunnel login
fi

if ! ls cloudflared/*.json >/dev/null 2>&1; then
  echo "==> Creating tunnel '$TUNNEL_NAME'"
  cf tunnel create "$TUNNEL_NAME"
fi

CRED_FILE=$(basename "$(ls cloudflared/*.json | head -n1)")
TUNNEL_ID="${CRED_FILE%.json}"

echo "==> Routing DNS: $HOSTNAME -> tunnel $TUNNEL_ID"
# --overwrite-dns takes over a record left behind by a previous tunnel
cf tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$HOSTNAME"

# the sidecar container reads these as uid 65532
chmod 644 "cloudflared/$CRED_FILE"

echo "==> Writing cloudflared/config.yml"
cat > cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$CRED_FILE
# QUIC is blocked on this network; without http2 Cloudflare serves error 1033
protocol: http2
ingress:
  - hostname: $HOSTNAME
    service: http://app:3000
  - service: http_status:404
EOF

echo
echo "Done. Start everything with:  docker compose up -d --build"
echo "The signup API will be live at https://$HOSTNAME"
