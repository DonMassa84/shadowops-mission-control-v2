#!/usr/bin/env bash
set -Eeuo pipefail

REPO="$HOME/Projects/shadowops-mission-control-v2"
STATE_DIR="$HOME/.local/state/shadowops-agent-supervisor"
LOG="$STATE_DIR/supervisor.log"

mkdir -p "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$LOG"
}

log "SUPERVISOR_START"

while true; do
  if ! systemctl --user is-active --quiet shadowops-agent-bridge.service; then
    log "BRIDGE_INACTIVE_AUTO_START_BLOCKED_COORDINATION_REVIEW"
  fi

  if ssh -o BatchMode=yes -o ConnectTimeout=3 shadowserver-i7 true 2>/dev/null; then
    log "I7_HEARTBEAT=PASS"
  else
    log "I7_HEARTBEAT=FAIL"
  fi

  if [[ -x "$REPO/scripts/shadowops-agent-bridge-status.sh" ]]; then
    "$REPO/scripts/shadowops-agent-bridge-status.sh" >>"$LOG" 2>&1 || true
  fi

  # Intentionally no arbitrary worker restart here.
  # Existing task-router / worker-registry remains authoritative.

  sleep 60
done
