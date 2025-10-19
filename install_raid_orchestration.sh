#!/usr/bin/env bash
# ============================================================
# install_raid_orchestration.sh
# ------------------------------------------------------------
# ROLE:
#   Orchestrates RAID installations across multiple Raspberry Pi targets.
#   Handles SSH verification, script distribution, and parallel execution.
#
# EXECUTION:
#   ./install_raid_orchestration.sh one two three
#
# DEPENDENCIES:
#   - ssh_setup.sh  : Ensures passwordless SSH is configured
#   - install_raid_target.sh : Main per-target setup script
#   - install_raid_server.sh : Actual RAID creation logic
#   - device_updater.sh, firewall_setup.sh, raid_checks.sh : Helper scripts
#
# OUTPUT:
#   Logs in ./logs/install_<hostname>.log
#   Summary: ./logs/raid_install_summary.csv
# ============================================================

set -euo pipefail

# --- CONFIGURATION ---
SSH_USER="pi"
SSH_PORT=22
MAX_PARALLEL=3
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
SUMMARY_FILE="${LOG_DIR}/raid_install_summary.csv"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# --- LOGGING HELPERS ---
log()   { printf "[INFO]  %s\n" "$*" | tee -a "${LOG_DIR}/orchestration.log"; }
error() { printf "[ERROR] %s\n" "$*" | tee -a "${LOG_DIR}/orchestration.log" >&2; }

# --- CHECK ARGUMENTS ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target1> [target2] ..."
    exit 1
fi
TARGETS=("$@")

# --- STEP 1: SSH SETUP ---
log "Running SSH setup verification for all targets..."
bash "${SCRIPT_DIR}/ssh_setup.sh" "${TARGETS[@]}"

# --- STEP 2: COPY AND RUN INSTALL SCRIPTS ON TARGETS ---
log "Starting RAID installations on ${#TARGETS[@]} devices (max ${MAX_PARALLEL} parallel)..."

# Prepare summary CSV header
echo "HOSTNAME/IP,STATUS,LOG_FILE" > "$SUMMARY_FILE"

run_install() {
    local target="$1"
    local ip="$target"
    local target_log="${LOG_DIR}/install_${target}.log"

    echo "===== RAID INSTALL START: $(date) =====" > "$target_log"
    echo "Target: ${target}" >> "$target_log"

    log "[${target}] Copying orchestration and helper scripts..."

    # --- Copy all required scripts ---
    for script in \
        install_raid_target.sh \
        install_raid_server.sh \
        device_updater.sh \
        firewall_setup.sh \
        raid_checks.sh; do

        if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
            error "[${target}] Missing required file: ${SCRIPT_DIR}/${script}"
            echo "${target},FAILED,${target_log}" >> "$SUMMARY_FILE"
            return
        fi

        scp -q -P "$SSH_PORT" "${SCRIPT_DIR}/${script}" "${SSH_USER}@${ip}:/tmp/${script}" || {
            error "[${target}] Failed to copy ${script}"
            echo "${target},FAILED,${target_log}" >> "$SUMMARY_FILE"
            return
        }
    done

    # --- Set permissions remotely ---
    ssh -p "$SSH_PORT" "${SSH_USER}@${ip}" "chmod +x /tmp/*.sh" || {
        error "[${target}] chmod failed on remote host"
        echo "${target},FAILED,${target_log}" >> "$SUMMARY_FILE"
        return
    }

    log "[${target}] Running RAID setup..."

    # --- Run orchestration script on target ---
    if ssh -p "$SSH_PORT" "${SSH_USER}@${ip}" "sudo bash /tmp/install_raid_target.sh" \
        > >(tee -a "$target_log") 2>&1; then
        log "[${target}] Installation completed successfully."
        echo "${target},SUCCESS,${target_log}" >> "$SUMMARY_FILE"
    else
        error "[${target}] Installation failed. Check ${target_log}"
        echo "${target},FAILED,${target_log}" >> "$SUMMARY_FILE"
    fi
}

export -f run_install log error
export SCRIPT_DIR SSH_USER SSH_PORT LOG_DIR SUMMARY_FILE

# Parallel execution
printf "%s\n" "${TARGETS[@]}" | xargs -n1 -P "$MAX_PARALLEL" bash -c 'run_install "$@"' _

# --- STEP 3: PRINT SUMMARY ---
log ""
log "========= RAID INSTALL SUMMARY ========="
printf "%-15s | %-10s | %-40s\n" "HOSTNAME/IP" "STATUS" "LOG FILE"
printf -- "----------------------------------------\n"

if [[ -f "$SUMMARY_FILE" ]]; then
    tail -n +2 "$SUMMARY_FILE" | while IFS=, read -r host status logfile; do
        printf "%-15s | %-10s | %-40s\n" "$host" "$status" "$logfile"
    done
else
    echo "[WARN] Summary file not found."
fi

printf "========================================\n"
