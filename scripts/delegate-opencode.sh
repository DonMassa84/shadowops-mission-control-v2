#!/usr/bin/env bash
set -euo pipefail

# Local OpenCode delegation script
# Usage: SHADOWOPS_CODER_MODEL='provider/model' scripts/delegate-opencode.sh "task description"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
  echo "Not a git repository" >&2
  exit 1
fi
cd "$ROOT"

MODEL="${SHADOWOPS_CODER_MODEL:-}"
if [[ -z "$MODEL" ]]; then
  echo "SHADOWOPS_CODER_MODEL not set" >&2
  echo "Available models:" >&2
  opencode models 2>/dev/null | head -20 >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: SHADOWOPS_CODER_MODEL='provider/model' $0 \"task description\"" >&2
  exit 1
fi

TASK="$*"

echo "=== Delegating to OpenCode Agent ==="
echo "Model: $MODEL"
echo "Task: $TASK"
echo "Branch: $(git branch --show-current)"
echo "Repo: $ROOT"
echo ""

STATE_DIR="${SHADOWOPS_STATE_DIR:-$HOME/.local/state/shadowops}"
LOG_DIR="$STATE_DIR/opencode"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/delegate-$STAMP.log"

opencode run \
  --dir "$ROOT" \
  --agent shadowops-coder \
  --model "$MODEL" \
  --format default \
  "$TASK" 2>&1 | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
