#!/usr/bin/env bash
set -Eeuo pipefail

# Dynamically find the shadowops repo
find_shadowops_repo() {
    local candidates=(
        "/home/schattenmacher/Projects/shadowops-mission-control-v2"
        "/home/shadowmaker/Projects/shadowops-mission-control-v2"
        "$HOME/Projects/shadowops-mission-control-v2"
    )
    for c in "${candidates[@]}"; do
        if [[ -d "$c/.git" ]]; then
            echo "$c"
            return 0
        fi
    done
    # Fallback to first candidate
    echo "${candidates[0]}"
    return 1
}

REPO="$(find_shadowops_repo)"
STATE_DIR="$HOME/.local/state/shadowops-agent-supervisor"
LOG="$STATE_DIR/supervisor.log"

mkdir -p "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$LOG"
}

log "SUPERVISOR_START repo=$REPO"

while true; do
  if ! timeout 5 systemctl --user is-active --quiet shadowops-agent-bridge.service 2>/dev/null; then
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
