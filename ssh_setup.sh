#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ssh_setup_$(date +%Y%m%d_%H%M%S).log"

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_USER="pi"

# --- Logging functions ---
info()  { echo -e "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "\033[1;33m[WARN]  $*\033[0m" | tee -a "$LOG_FILE" >&2; }
error() { echo -e "\033[1;31m[ERROR] $*\033[0m" | tee -a "$LOG_FILE" >&2; exit 1; }

# --- Usage ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <host1> [host2 ...]"
  exit 1
fi

# --- Step 1: Ensure SSH key exists ---
if [[ ! -f "$SSH_KEY" ]]; then
  info "No SSH key found at $SSH_KEY — generating one..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "raid-orchestrator" | tee -a "$LOG_FILE"
else
  info "SSH key already exists at $SSH_KEY"
fi

# --- Step 2: SSH options ---
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# --- Step 3: Iterate through hosts ---
for host in "$@"; do
  info "Setting up SSH access for host: $host"

  {
    info "  → Accepting fingerprint..."
    ssh $SSH_OPTS "$SSH_USER@$host" "echo '[OK] Fingerprint accepted.'" || true

    info "  → Copying SSH key..."
    ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=no "$SSH_USER@$host" 2>&1 | tee -a "$LOG_FILE" || {
      warn "  ⚠️  Automatic key copy failed. Manual password entry may be required."
    }

    info "  → Verifying passwordless login..."
    if ssh $SSH_OPTS -o BatchMode=yes "$SSH_USER@$host" "echo ok" >/dev/null 2>&1; then
      info "  ✅ Passwordless SSH verified for $host"
    else
      warn "  ⚠️  Passwordless SSH not confirmed for $host"
    fi
  } | stdbuf -oL tee -a "$LOG_FILE"
done

info "SSH setup completed. Log saved to: $LOG_FILE"
