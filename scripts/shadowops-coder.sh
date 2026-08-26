#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -e "$ROOT/.git" ]]; then
  echo "SHADOWOPS_CODER=BLOCKED_NOT_A_GIT_WORKTREE" >&2
  exit 64
fi
cd "$ROOT"

BRANCH="$(git branch --show-current)"
if [[ -z "$BRANCH" ]]; then
  echo "SHADOWOPS_CODER=BLOCKED_DETACHED_HEAD" >&2
  exit 65
fi
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "SHADOWOPS_CODER=BLOCKED_PROTECTED_BRANCH" >&2
  echo "BRANCH=$BRANCH" >&2
  exit 65
fi

if git diff --name-only --diff-filter=U | grep -q .; then
  echo "SHADOWOPS_CODER=BLOCKED_UNRESOLVED_CONFLICTS" >&2
  exit 66
fi

if ! command -v opencode >/dev/null 2>&1; then
  echo "SHADOWOPS_CODER=BLOCKED_OPENCODE_NOT_INSTALLED" >&2
  exit 127
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "SHADOWOPS_CODER=BLOCKED_TIMEOUT_COMMAND_MISSING" >&2
  exit 127
fi

# ShadowOps coding agents are REMOTE-ONLY. There is intentionally no local-model
# default. The operator must choose an exact remote provider/model identifier that
# the installed OpenCode instance exposes.
MODEL="${SHADOWOPS_CODER_MODEL:-}"
MODEL_SOURCE="SHADOWOPS_CODER_MODEL"
RUN_TIMEOUT="${SHADOWOPS_CODER_TIMEOUT:-45m}"

if [[ -z "$MODEL" ]]; then
  echo "SHADOWOPS_CODER=BLOCKED_REMOTE_MODEL_REQUIRED" >&2
  echo "AI_EXECUTION_POLICY=REMOTE_ONLY" >&2
  echo "Choose an exact remote model identifier with: opencode models" >&2
  echo "Then run: SHADOWOPS_CODER_MODEL='provider/model' scripts/shadowops-coder.sh --next" >&2
  exit 69
fi

case "$MODEL" in
  ollama/*|local/*|lmstudio/*|llamacpp/*|llama.cpp/*)
    echo "SHADOWOPS_CODER=BLOCKED_LOCAL_AI_FORBIDDEN" >&2
    echo "AI_EXECUTION_POLICY=REMOTE_ONLY" >&2
    echo "MODEL=$MODEL" >&2
    exit 69
    ;;
esac

# The CLI --model value is authoritative. Verify that exact provider/model identifier
# is visible to the same OpenCode installation before starting an agent session.
MODEL_LIST="$(timeout 30s opencode models 2>/dev/null || true)"
if ! printf '%s\n' "$MODEL_LIST" | awk '{print $1}' | grep -Fxq "$MODEL"; then
  echo "SHADOWOPS_CODER=BLOCKED_MODEL_NOT_AVAILABLE_IN_OPENCODE" >&2
  echo "AI_EXECUTION_POLICY=REMOTE_ONLY" >&2
  echo "MODEL=$MODEL" >&2
  echo "MODEL_SOURCE=$MODEL_SOURCE" >&2
  echo "Resolve an exact remote identifier with: opencode models | grep -Ei 'nemotron|claude|gpt|gemini'" >&2
  exit 69
fi

NEXT_MODE=0
if [[ "${1:-}" == "--next" ]]; then
  NEXT_MODE=1
  shift
fi

if [[ "$NEXT_MODE" == "1" ]]; then
  [[ $# -eq 0 ]] || {
    echo "SHADOWOPS_CODER=BLOCKED_NEXT_MODE_TAKES_NO_EXTRA_ARGUMENTS" >&2
    exit 64
  }

  echo "=== SHADOWOPS OPENCODE PREFLIGHT + KNOWN-DRIFT RECOVERY ==="
  bash scripts/opencode-preflight.sh --repair-known-drift --sync

  PROMPT='Read README.md, AGENTS.md, docs/AI_CONTEXT.md, docs/PROJECT_STATUS.md, docs/LOCAL_ALL_DEVELOPMENTS.md, and docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md completely before editing anything. The preflight has already established the canonical local state. Execute ONLY the CURRENT TASK marked P0 in the handoff. Do not rediscover the architecture. Do not write any report, plan, scratch, example, or handoff file: the final completion report must be returned as text on stdout only. Never attempt placeholder/example paths or any path outside the current repository. Do not rewrite whole existing source files. Make the smallest targeted edits, one file at a time, and run the exact focused tests after each step. Respect every STOP condition. Do not touch MCP, Project Catalog, workflow registry, UI, release scripts, systemd, port 4013, main, deployments, or unrelated code. Finish with exactly the completion report format defined in the handoff document.'
else
  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage:
  SHADOWOPS_CODER_MODEL='provider/model' scripts/shadowops-coder.sh --next
  SHADOWOPS_CODER_MODEL='provider/model' scripts/shadowops-coder.sh "implement <task> and run relevant tests"

AI execution policy:
  REMOTE_ONLY
  Local models/providers such as ollama/* are forbidden.

Find an exact remote model known to OpenCode:
  opencode models

Optional run bound (GNU timeout syntax):
  SHADOWOPS_CODER_MODEL='provider/model' SHADOWOPS_CODER_TIMEOUT=30m scripts/shadowops-coder.sh --next
EOF
    exit 64
  fi
  PROMPT="$*"
fi

STATE_DIR="${SHADOWOPS_STATE_DIR:-$HOME/.local/state/shadowops}"
LOG_DIR="$STATE_DIR/opencode"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/shadowops-coder-$STAMP.log"
BASELINE_FILE="$LOG_DIR/shadowops-coder-$STAMP.baseline.env"

# Baseline is intentionally captured AFTER preflight. Deterministic --next mode
# starts only from a clean post-preflight worktree; the agent may then touch only
# the P0 allowlist verified by opencode-postflight.sh.
if [[ "$NEXT_MODE" == "1" ]]; then
  if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
    echo "SHADOWOPS_CODER=BLOCKED_DIRTY_AFTER_PREFLIGHT" >&2
    git status --short --branch --untracked-files=all >&2
    echo "Inspect the listed paths; do not reset or clean automatically." >&2
    exit 70
  fi
  {
    echo "HEAD=$(git rev-parse HEAD)"
    echo "BRANCH=$(git branch --show-current)"
  } > "$BASELINE_FILE"
  chmod 600 "$BASELINE_FILE" 2>/dev/null || true
fi

printf 'SHADOWOPS_CODER=START\nBRANCH=%s\nMODEL=%s\nMODEL_SOURCE=%s\nMODEL_AUTHORITY=CLI_--model\nMODEL_VERIFIED=YES\nAI_EXECUTION_POLICY=REMOTE_ONLY\nROOT=%s\nMODE=%s\nTIMEOUT=%s\nLOG=%s\nBASELINE=%s\n' \
  "$(git branch --show-current)" "$MODEL" "$MODEL_SOURCE" "$ROOT" "$([[ "$NEXT_MODE" == "1" ]] && echo NEXT || echo CUSTOM)" "$RUN_TIMEOUT" "$LOG_FILE" "${BASELINE_FILE:-NONE}"

set +e
timeout --foreground --signal=INT --kill-after=30s "$RUN_TIMEOUT" \
  opencode run \
    --dir "$ROOT" \
    --agent shadowops-coder \
    --model "$MODEL" \
    --format default \
    "$PROMPT" 2>&1 | tee "$LOG_FILE"
RUN_RC=${PIPESTATUS[0]}
set -e

if [[ "$NEXT_MODE" == "1" ]]; then
  echo "=== SHADOWOPS OPENCODE POSTFLIGHT ==="
  if ! bash scripts/opencode-postflight.sh "$BASELINE_FILE"; then
    echo "SHADOWOPS_CODER=BLOCKED_POSTFLIGHT" >&2
    echo "LOG=$LOG_FILE" >&2
    echo "BASELINE=$BASELINE_FILE" >&2
    exit 72
  fi
fi

case "$RUN_RC" in
  0)
    echo "SHADOWOPS_CODER=COMPLETE"
    echo "LOG=$LOG_FILE"
    ;;
  124|137)
    echo "SHADOWOPS_CODER=BLOCKED_TIMEOUT" >&2
    echo "TIMEOUT=$RUN_TIMEOUT" >&2
    echo "LOG=$LOG_FILE" >&2
    exit 71
    ;;
  *)
    echo "SHADOWOPS_CODER=FAILED" >&2
    echo "RC=$RUN_RC" >&2
    echo "LOG=$LOG_FILE" >&2
    exit "$RUN_RC"
    ;;
esac
