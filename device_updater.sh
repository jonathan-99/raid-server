#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/raid_setup.log"

log()   { printf '[UPDATE] [INFO]  %s\n' "$*" | tee -a "$LOG_FILE"; }
warn()  { printf '[UPDATE] [WARN]  %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf '[UPDATE] [ERROR] %s\n' "$*" | tee -a "$LOG_FILE" >&2; }

trap 'rc=$?; error "Failed at line $LINENO (exit $rc)"; exit $rc' ERR

log "Starting system update and prerequisite installation..."
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y | tee -a "$LOG_FILE"
sudo apt-get full-upgrade -y | tee -a "$LOG_FILE"
sudo apt-get install -y mdadm ufw python3-venv python3-pip --no-install-recommends | tee -a "$LOG_FILE"

if python3 -m venv /opt/raid-venv 2>/dev/null; then
    log "Created Python venv at /opt/raid-venv."
    source /opt/raid-venv/bin/activate
    python -m pip install --upgrade pip setuptools wheel >>"$LOG_FILE" 2>&1 || warn "pip upgrade failed."
    python -m pip install docker >>"$LOG_FILE" 2>&1 || warn "Optional pip installs failed."
    deactivate
else
    warn "Could not create Python venv; skipping optional pip installs."
fi

log "Device update complete."
