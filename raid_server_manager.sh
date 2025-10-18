#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/var/log/raid_setup.log"

echo "[MANAGER] [INFO] RAID server setup initiated at $(date)" | tee -a "$LOG_FILE"

for script in device_updater.sh firewall_setup.sh raid_checks.sh; do
    if [[ -x "$script" ]]; then
        echo "[MANAGER] [INFO] Running $script..." | tee -a "$LOG_FILE"
        bash "$script"
    else
        echo "[MANAGER] [WARN] $script not found or not executable." | tee -a "$LOG_FILE"
    fi
done

# Extract disks from raid_checks.sh output (for automation)
mapfile -t disks < <(bash raid_checks.sh | grep '^/dev/')
if (( ${#disks[@]} >= 2 )); then
    echo "[MANAGER] [INFO] Running raid_install.sh ${disks[0]} ${disks[1]}" | tee -a "$LOG_FILE"
    bash raid_install.sh "${disks[0]}" "${disks[1]}"
else
    echo "[MANAGER] [ERROR] Not enough disks for RAID installation." | tee -a "$LOG_FILE"
    exit 1
fi

echo "[MANAGER] [INFO] RAID setup completed successfully." | tee -a "$LOG_FILE"
