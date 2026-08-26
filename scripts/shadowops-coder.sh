#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
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
if ! command -v ollama >/dev/null 2>&1; then
  echo "SHADOWOPS_CODER=BLOCKED_OLLAMA_NOT_INSTALLED" >&2
  exit 127
fi

MODEL="${SHADOWOPS_CODER_MODEL:-ollama/qwen2.5-coder:14b}"
LOCAL_MODEL="${MODEL#ollama/}"

if ! ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$LOCAL_MODEL"; then
  echo "SHADOWOPS_CODER=BLOCKED_MODEL_NOT_AVAILABLE" >&2
  echo "MODEL=$MODEL" >&2
  echo "Available local models:" >&2
  ollama list >&2 || true
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

  PROMPT='Read docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md completely before editing anything. The preflight has already established the canonical local state. Execute ONLY the CURRENT TASK marked P0 in that document. Do not rediscover the architecture. Do not rewrite whole existing source files. Make the smallest targeted edits, one file at a time, and run the exact focused tests after each step. Respect every STOP condition. Do not touch MCP, Project Catalog, workflow registry, UI, release scripts, systemd, port 4013, main, deployments, or unrelated code. Finish with exactly the completion report format defined in the handoff document.'
else
  if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
Usage:
  scripts/shadowops-coder.sh --next
  scripts/shadowops-coder.sh "implement <task> and run relevant tests"

Recommended deterministic mode:
  scripts/shadowops-coder.sh --next

Optional model override:
  SHADOWOPS_CODER_MODEL=ollama/qwen2.5-coder:7b scripts/shadowops-coder.sh --next
EOF
    exit 64
  fi
  PROMPT="$*"
fi

printf 'SHADOWOPS_CODER=START\nBRANCH=%s\nMODEL=%s\nROOT=%s\nMODE=%s\n' \
  "$(git branch --show-current)" "$MODEL" "$ROOT" "$([[ "$NEXT_MODE" == "1" ]] && echo NEXT || echo CUSTOM)"

exec opencode run \
  --dir "$ROOT" \
  --agent shadowops-coder \
  --model "$MODEL" \
  --format default \
  "$PROMPT"
