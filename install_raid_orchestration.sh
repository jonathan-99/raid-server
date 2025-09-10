#!/usr/bin/env bash
# raid_orchestrator.sh
# Orchestrates RAID setup script or returns USB devices only.

set -euo pipefail

# Path to your RAID setup script (the one that creates the array, formats, mounts, etc.)
RAID_SCRIPT="${RAID_SCRIPT:-./raid_setup.sh}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0")                 Run the full RAID setup script.
  $(basename "$0") --return-usb-devices
                                   Print registered USB disk devices (one per line).
  $(basename "$0") --help          Show this help message.

Env:
  RAID_SCRIPT=./raid_setup.sh      Path to the RAID setup script to run when no args are given.
EOF
}

# Returns a list of USB *disk* device paths (e.g., /dev/sda /dev/sdb), one per line.
list_usb_disks() {
  # Prefer lsblk transport metadata; fall back to sysfs if needed.
  if lsblk -ndo NAME,TYPE,TRAN >/dev/null 2>&1; then
    # Filter to devices where TYPE=disk and TRAN=usb
    lsblk -ndo NAME,TYPE,TRAN \
      | awk '$2=="disk" && $3=="usb"{print "/dev/"$1}'
  else
    # Fallback using sysfs (older systems)
    # Find disks under /sys/block whose parent path includes "usb"
    for d in /sys/block/*; do
      name="$(basename "$d")"
      # Skip loop and RAM devices
      [[ "$name" == loop* || "$name" == ram* ]] && continue
      if readlink -f "$d" | grep -qi '/usb'; then
        echo "/dev/$name"
      fi
    done
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    # Run the full RAID setup script
    if [[ ! -x "$RAID_SCRIPT" ]]; then
      echo "[ERROR] RAID script not found or not executable: $RAID_SCRIPT" >&2
      exit 1
    fi
    exec "$RAID_SCRIPT"
  fi

  case "${1:-}" in
    --return-usb-devices)
      list_usb_disks
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
