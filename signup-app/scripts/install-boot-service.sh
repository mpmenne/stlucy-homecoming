#!/usr/bin/env bash
#
# Installs a systemd unit that brings the signup-app docker compose stack up
# at boot. Docker's `restart: unless-stopped` already restarts the containers
# after most reboots; this unit makes startup explicit and guaranteed, and
# gives you `systemctl status stlucy-signup` visibility.
#
# Idempotent — safe to re-run after moving the repo or upgrading docker.
#
# Usage: sudo ./scripts/install-boot-service.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER="$(command -v docker)"
UNIT=/etc/systemd/system/stlucy-signup.service

cat > "$UNIT" <<EOF
[Unit]
Description=St. Lucy signup app (docker compose stack)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=$DOCKER compose up -d
ExecStop=$DOCKER compose stop

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable stlucy-signup.service

echo "Installed and enabled $UNIT (WorkingDirectory=$APP_DIR)."
echo "Start now with:  sudo systemctl start stlucy-signup"
