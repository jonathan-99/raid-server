#!/usr/bin/env bash
# ============================================================
# firewall_setup.sh
# ------------------------------------------------------------
# ROLE:
#   Configures UFW firewall rules and disables IPv6.
#   Logs all actions with host-specific info.
# ============================================================

set -euo pipefail

# --- Config ---
TARGET_HOSTNAME="${HOST:-$(hostname)}"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

# --- Logging functions ---
log()  { echo "[INFO]  [$TARGET_HOSTNAME] $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "\033[1;33m[WARN]  [$TARGET_HOSTNAME] $*\033[0m" | tee -a "$LOG_FILE" >&2; }

# --- Firewall rules ---
log "Configuring UFW firewall rules..."
sudo ufw allow ssh || true
sudo ufw allow 80 || true
sudo ufw allow 443 || true
sudo ufw allow 3142 || true

# --- Disable IPv6 ---
if grep -qE '^IPV6=' /etc/default/ufw 2>/dev/null; then
    sudo sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    log "Disabled IPv6 by modification"
else
    echo "IPV6=no" | sudo tee -a /etc/default/ufw >/dev/null
    log "Disabled IPv6 by insertion"
fi

# --- Enable UFW ---
sudo ufw --force enable >/dev/null 2>&1 || warn "Failed to enable UFW; continuing."

log "Firewall setup completed."
