#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -e "$ROOT/.git" ]]; then
  echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_NOT_A_GIT_WORKTREE" >&2
  exit 64
fi
cd "$ROOT"

STATE_DIR="${SHADOWOPS_STATE_DIR:-$HOME/.local/state/shadowops}"
AUTO_DIR="$STATE_DIR/opencode/auto"
QUEUE_DIR="$AUTO_DIR/queue"
DONE_DIR="$AUTO_DIR/done"
FAILED_DIR="$AUTO_DIR/failed"
LOG_DIR="$AUTO_DIR/logs"
LOCK_FILE="$AUTO_DIR/worker.lock"
MAX_TASKS="${SHADOWOPS_OPENCODE_AUTO_MAX_TASKS:-3}"

mkdir -p "$QUEUE_DIR" "$DONE_DIR" "$FAILED_DIR" "$LOG_DIR"
chmod 700 "$AUTO_DIR" "$QUEUE_DIR" "$DONE_DIR" "$FAILED_DIR" "$LOG_DIR" 2>/dev/null || true

usage() {
  cat <<'EOF'
Usage:
  scripts/shadowops-opencode-auto.sh --status
  scripts/shadowops-opencode-auto.sh --enqueue "implement <bounded task>"
  scripts/shadowops-opencode-auto.sh --run

Required for execution:
  SHADOWOPS_CODER_MODEL='remote-provider/model'

Safety contract:
  - non-main branch only
  - clean worktree required before every queued task
  - no OpenCode --auto permission blanket
  - remote model enforced by scripts/shadowops-coder.sh and OpenCodeAdapter
  - security/control-plane protected paths are blocked
  - format + compile + full test suite must pass before local auto-commit
  - never push, merge, rebase, deploy, restart systemd, or mutate production runtime
EOF
}

branch_guard() {
  local branch
  branch="$(git branch --show-current)"

  if [[ -z "$branch" ]]; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_DETACHED_HEAD" >&2
    exit 65
  fi

  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_PROTECTED_BRANCH" >&2
    echo "BRANCH=$branch" >&2
    exit 65
  fi

  if git diff --name-only --diff-filter=U | grep -q .; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_UNRESOLVED_CONFLICTS" >&2
    exit 66
  fi
}

clean_guard() {
  if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_DIRTY_WORKTREE" >&2
    git status --short --branch --untracked-files=all >&2
    echo "Resolve the existing worktree state manually; no reset/clean is performed." >&2
    exit 70
  fi
}

model_guard() {
  local model="${SHADOWOPS_CODER_MODEL:-}"

  if [[ -z "$model" ]]; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_REMOTE_MODEL_REQUIRED" >&2
    echo "Run: opencode models" >&2
    echo "Then export SHADOWOPS_CODER_MODEL='provider/model'" >&2
    exit 69
  fi

  case "${model,,}" in
    ollama/*|local/*|lmstudio/*|llamacpp/*|llama.cpp/*)
      echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_LOCAL_AI_FORBIDDEN" >&2
      echo "MODEL=$model" >&2
      exit 69
      ;;
  esac
}

protected_path() {
  local path="$1"
  case "$path" in
    .env|.env.*|*credentials*|*credential*|*secret*|*private_key*|*private-key*) return 0 ;;
    mix.lock) return 0 ;;
    .github/workflows/*) return 0 ;;
    .opencode/*) return 0 ;;
    docs/handoff/*) return 0 ;;
    ops/mcp/*) return 0 ;;
    config/runtime.exs) return 0 ;;
    rel/*) return 0 ;;
    scripts/shadowops-coder.sh) return 0 ;;
    scripts/shadowops-opencode-auto.sh) return 0 ;;
    scripts/*deploy*|scripts/*release*|scripts/*promote*) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/adapters/open_code_adapter.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/capability_registry.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/execution_service.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/policy.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/risk_policy.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/privacy_gate.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/approval.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/approval_store.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/governance_gate.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/audit.ex) return 0 ;;
    apps/shadowops_web/priv/static/assets/mission-control.js) return 0 ;;
    *) return 1 ;;
  esac
}

changed_paths() {
  {
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

fail_task() {
  local task="$1"
  local reason="$2"
  local name
  name="$(basename "$task")"
  printf '%s\n' "$reason" > "$FAILED_DIR/${name%.task}.reason"
  chmod 600 "$FAILED_DIR/${name%.task}.reason" 2>/dev/null || true
  mv "$task" "$FAILED_DIR/$name"
  echo "TASK_RESULT=FAILED"
  echo "TASK=$name"
  echo "REASON=$reason"
}

enqueue_task() {
  shift
  local prompt="$*"

  if [[ -z "$prompt" ]]; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_EMPTY_TASK" >&2
    exit 64
  fi

  local bytes
  bytes="$(printf '%s' "$prompt" | wc -c)"
  if (( bytes < 1 || bytes > 32000 )); then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_TASK_SIZE" >&2
    echo "TASK_BYTES=$bytes" >&2
    exit 64
  fi

  local stamp task tmp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
  task="$QUEUE_DIR/$stamp.task"
  tmp="$QUEUE_DIR/.$stamp.tmp"

  printf '%s\n' "$prompt" > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$task"

  echo "SHADOWOPS_OPENCODE_AUTO=ENQUEUED"
  echo "TASK=$(basename "$task")"
  echo "QUEUE=$QUEUE_DIR"
}

status() {
  local branch model_state
  branch="$(git branch --show-current 2>/dev/null || true)"
  model_state="MISSING"
  [[ -n "${SHADOWOPS_CODER_MODEL:-}" ]] && model_state="CONFIGURED"

  echo "SHADOWOPS_OPENCODE_AUTO=STATUS"
  echo "ROOT=$ROOT"
  echo "BRANCH=${branch:-DETACHED}"
  echo "MODEL=$model_state"
  echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
  echo "QUEUE_COUNT=$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.task' | wc -l)"
  echo "DONE_COUNT=$(find "$DONE_DIR" -maxdepth 1 -type f -name '*.task' | wc -l)"
  echo "FAILED_COUNT=$(find "$FAILED_DIR" -maxdepth 1 -type f -name '*.task' | wc -l)"
  echo "QUEUE=$QUEUE_DIR"
}

run_queue() {
  branch_guard
  clean_guard
  model_guard

  if ! command -v flock >/dev/null 2>&1; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_FLOCK_MISSING" >&2
    exit 127
  fi

  if ! [[ "$MAX_TASKS" =~ ^[0-9]+$ ]] || (( MAX_TASKS < 1 || MAX_TASKS > 20 )); then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_INVALID_MAX_TASKS" >&2
    echo "MAX_TASKS=$MAX_TASKS" >&2
    exit 64
  fi

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "SHADOWOPS_OPENCODE_AUTO=BLOCKED_WORKER_ALREADY_RUNNING" >&2
    exit 75
  fi

  mapfile -t tasks < <(
    find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.task' -print | sort | head -n "$MAX_TASKS"
  )

  if (( ${#tasks[@]} == 0 )); then
    echo "SHADOWOPS_OPENCODE_AUTO=IDLE"
    echo "QUEUE_COUNT=0"
    return 0
  fi

  local processed=0

  for task in "${tasks[@]}"; do
    branch_guard
    clean_guard

    local name task_id prompt before_head stamp log auto_prompt run_rc
    name="$(basename "$task")"
    task_id="${name%.task}"
    prompt="$(cat "$task")"
    before_head="$(git rev-parse HEAD)"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    log="$LOG_DIR/$task_id-$stamp.log"

    auto_prompt="SHADOWOPS_AUTO_TASK
Task ID: $task_id

The explicitly queued task below is authoritative for this invocation. Do not execute a stale CURRENT TASK from docs/handoff. Do not commit or push; the bounded ShadowOps auto-worker owns postflight gates and the local commit. Do not change governance/security boundaries, OpenCode configuration, MCP, GitHub workflows, release/deploy files, systemd/runtime configuration, or any protected path. Work only in this current non-main worktree. Make the smallest implementation and regression-test changes required for this task. Run focused tests while working. If the task requires a protected path or productive/external mutation, stop and report the block.

QUEUED TASK:
$prompt"

    echo "=== SHADOWOPS OPENCODE AUTO TASK ===" | tee "$log"
    echo "TASK=$name" | tee -a "$log"
    echo "BASELINE_HEAD=$before_head" | tee -a "$log"
    echo "BRANCH=$(git branch --show-current)" | tee -a "$log"
    echo "AI_EXECUTION_POLICY=REMOTE_ONLY" | tee -a "$log"

    set +e
    bash scripts/shadowops-coder.sh "$auto_prompt" 2>&1 | tee -a "$log"
    run_rc=${PIPESTATUS[0]}
    set -e

    if (( run_rc != 0 )); then
      fail_task "$task" "OPENCODE_RUN_RC_$run_rc"
      echo "LOG=$log"
      return "$run_rc"
    fi

    if [[ "$(git branch --show-current)" == "main" || "$(git branch --show-current)" == "master" ]]; then
      fail_task "$task" "PROTECTED_BRANCH_AFTER_RUN"
      echo "LOG=$log"
      return 65
    fi

    if [[ "$(git rev-parse HEAD)" != "$before_head" ]]; then
      fail_task "$task" "AGENT_COMMITTED_UNEXPECTEDLY"
      echo "No automatic reset is performed." >&2
      echo "LOG=$log"
      return 73
    fi

    mapfile -t changed < <(changed_paths)

    local blocked=()
    for path in "${changed[@]:-}"; do
      [[ -n "$path" ]] || continue
      if protected_path "$path"; then
        blocked+=("$path")
      fi
    done

    if (( ${#blocked[@]} > 0 )); then
      printf 'BLOCKED_PATH=%s\n' "${blocked[@]}" | tee -a "$log" >&2
      fail_task "$task" "PROTECTED_PATH_CHANGED"
      echo "No automatic reset or clean is performed." >&2
      echo "LOG=$log"
      return 74
    fi

    if (( ${#changed[@]} == 0 )); then
      mv "$task" "$DONE_DIR/$name"
      echo "TASK_RESULT=NO_CHANGES" | tee -a "$log"
      echo "TASK=$name" | tee -a "$log"
      processed=$((processed + 1))
      continue
    fi

    echo "=== AUTO POSTFLIGHT GATES ===" | tee -a "$log"

    if ! git diff --check 2>&1 | tee -a "$log"; then
      fail_task "$task" "DIFF_CHECK_FAILED"
      echo "LOG=$log"
      return 72
    fi

    if ! mix format --check-formatted 2>&1 | tee -a "$log"; then
      fail_task "$task" "FORMAT_FAILED"
      echo "LOG=$log"
      return 72
    fi

    if ! MIX_ENV=test mix compile --warnings-as-errors 2>&1 | tee -a "$log"; then
      fail_task "$task" "COMPILE_FAILED"
      echo "LOG=$log"
      return 72
    fi

    if ! MIX_ENV=test mix test 2>&1 | tee -a "$log"; then
      fail_task "$task" "FULL_TEST_FAILED"
      echo "LOG=$log"
      return 72
    fi

    branch_guard

    if [[ "$(git rev-parse HEAD)" != "$before_head" ]]; then
      fail_task "$task" "HEAD_CHANGED_DURING_GATES"
      echo "LOG=$log"
      return 73
    fi

    git add -A -- .

    if git diff --cached --quiet; then
      mv "$task" "$DONE_DIR/$name"
      echo "TASK_RESULT=NO_STAGED_CHANGES" | tee -a "$log"
      processed=$((processed + 1))
      continue
    fi

    git commit -m "auto(opencode): $task_id" 2>&1 | tee -a "$log"

    if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
      fail_task "$task" "DIRTY_AFTER_AUTO_COMMIT"
      echo "No automatic reset or clean is performed." >&2
      echo "LOG=$log"
      return 73
    fi

    mv "$task" "$DONE_DIR/$name"
    processed=$((processed + 1))

    echo "TASK_RESULT=COMMITTED" | tee -a "$log"
    echo "TASK=$name" | tee -a "$log"
    echo "HEAD=$(git rev-parse HEAD)" | tee -a "$log"
    echo "LOG=$log" | tee -a "$log"
  done

  echo "SHADOWOPS_OPENCODE_AUTO=COMPLETE"
  echo "PROCESSED=$processed"
  echo "QUEUE_REMAINING=$(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.task' | wc -l)"
  echo "PUSHED=NO"
  echo "MERGED=NO"
  echo "DEPLOYED=NO"
}

case "${1:-}" in
  --status)
    [[ $# -eq 1 ]] || { usage >&2; exit 64; }
    status
    ;;
  --enqueue)
    [[ $# -ge 2 ]] || { usage >&2; exit 64; }
    enqueue_task "$@"
    ;;
  --run)
    [[ $# -eq 1 ]] || { usage >&2; exit 64; }
    run_queue
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
