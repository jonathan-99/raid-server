#!/usr/bin/env bash
# Device updater script
# Updates OS packages and installs prerequisites

set -euo pipefail

TARGET_HOSTNAME="$(hostname)"
LOG_FILE="/tmp/raid_target_${TARGET_HOSTNAME}.log"

log()   { printf "[%s] [INFO]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "[%s] [WARN]  %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; }
error() { printf "[%s] [ERROR] %s\n" "$TARGET_HOSTNAME" "$*" | tee -a "$LOG_FILE" >&2; exit 1; }

log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y | stdbuf -oL tee -a "$LOG_FILE"
sudo apt-get full-upgrade -y | stdbuf -oL tee -a "$LOG_FILE"

log "Installing prerequisites: mdadm, ufw, python3-pip, python3-venv..."
sudo apt-get install -y mdadm ufw python3-pip python3-venv --no-install-recommends \
  | stdbuf -oL tee -a "$LOG_FILE"

log "Device updater completed."
