#!/usr/bin/env bash
# cleanup_remote_processes.sh
# Stops any recursive RAID install processes and removes temporary files.

set -euo pipefail

SSH_USER="pi"
SSH_PORT=22
TARGETS=("$@")

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target1> [target2 ...]"
    exit 1
fi

echo "[INFO] Cleaning up RAID install processes and temp files on ${#TARGETS[@]} target(s)..."

for target in "${TARGETS[@]}"; do
    echo "[${target}] Cleaning up..."
    ssh -p "$SSH_PORT" "${SSH_USER}@${target}" '
        echo "[INFO] Killing any active RAID install-related processes..."
        sudo pkill -f "/tmp/install-raid-server.sh|/tmp/install_raid_target.sh|/tmp/device_updater.sh|/tmp/firewall_setup.sh|/tmp/raid_checks.sh" 2>/dev/null || true

        echo "[INFO] Removing temporary installer files..."
        sudo rm -f /tmp/install-raid-server.sh /tmp/install_raid_target.sh /tmp/device_updater.sh /tmp/firewall_setup.sh /tmp/raid_checks.sh 2>/dev/null || true

        echo "[INFO] Verifying cleanup..."
        REMAINING=$(sudo ls /tmp | grep -E "install|raid|device|firewall" || true)
        if [[ -z "$REMAINING" ]]; then
            echo "[SUCCESS] No temporary RAID files remain."
        else
            echo "[WARN] Some temp files remain:"
            echo "$REMAINING"
        fi
    '
done

echo "[INFO] Remote cleanup completed on all targets."
