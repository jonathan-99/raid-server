#!/usr/bin/env bash
# Firewall setup script
# Configures UFW rules and disables IPv6

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }

log "Configuring UFW firewall rules..."
sudo ufw allow ssh || true
sudo ufw allow 80 || true
sudo ufw allow 443 || true
sudo ufw allow 3142 || true

# Disable IPv6
if grep -qE '^IPV6=' /etc/default/ufw 2>/dev/null; then
    sudo sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
else
    echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
fi

# Enable UFW
sudo ufw --force enable >/dev/null 2>&1 || warn "UFW enable failed; continue."

log "Firewall setup completed."
