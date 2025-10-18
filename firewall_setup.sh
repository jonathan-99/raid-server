#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/raid_setup.log"

log()  { printf '[FIREWALL] [INFO]  %s\n' "$*" | tee -a "$LOG_FILE"; }
warn() { printf '[FIREWALL] [WARN]  %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

log "Configuring UFW firewall..."
sudo ufw allow ssh || true
sudo ufw allow 80  || true
sudo ufw allow 443 || true
sudo ufw allow 3142 || true

if grep -qE '^IPV6=' /etc/default/ufw 2>/dev/null; then
    sudo sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
else
    echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
fi

sudo ufw --force enable >/dev/null 2>&1 || true
log "Firewall configured and enabled (IPv6 disabled)."
