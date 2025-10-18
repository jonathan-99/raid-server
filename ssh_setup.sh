#!/bin/bash
set -euo pipefail

LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ssh_setup_$(date +%Y%m%d_%H%M%S).log"

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_USER="pi"

info()  { echo -e "[INFO]  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "[WARN]  $*" | tee -a "$LOG_FILE"; }
error() { echo -e "[ERROR] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <host1> [host2 ...]"
  exit 1
fi

# Step 1: Ensure SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
  info "No SSH key found at $SSH_KEY — generating one..."
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "raid-orchestrator" | tee -a "$LOG_FILE"
else
  info "SSH key already exists at $SSH_KEY"
fi

# Step 2: Configure SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Step 3: Iterate through each host
for host in "$@"; do
  info "Setting up SSH access for host: $host"

  # Pre-accept fingerprint and test connectivity
  info "  → Accepting fingerprint..."
  ssh $SSH_OPTS -o ConnectTimeout=5 "$SSH_USER@$host" "echo '[OK] Fingerprint accepted.'" 2>&1 | tee -a "$LOG_FILE" || true

  # Step 4: Copy key if needed
  info "  → Copying SSH key..."
  ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=no "$SSH_USER@$host" 2>&1 | tee -a "$LOG_FILE" || {
    warn "  ⚠️  Failed to copy SSH key automatically. You may need to enter the password manually once."
  }

  # Step 5: Verify passwordless login
  if ssh $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$host" "echo ok" >/dev/null 2>&1; then
    info "  ✅ Passwordless SSH verified for $host"
  else
    warn "  ⚠️  Passwordless SSH not confirmed for $host (may require manual key copy)"
  fi
done

info "SSH setup completed. Log saved to: $LOG_FILE"
