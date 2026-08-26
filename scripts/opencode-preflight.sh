#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_BRANCH="${SHADOWOPS_OPENCODE_BRANCH:-local/all-developments}"
REMOTE_REF="${SHADOWOPS_OPENCODE_REMOTE_REF:-origin/${EXPECTED_BRANCH}}"
MCP_FILE="ops/mcp/shadowops_runtime_mcp.py"
HANDOFF_FILE="docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md"
REPAIR_KNOWN_DRIFT=0
SYNC_REMOTE=0

for arg in "$@"; do
  case "$arg" in
    --repair-known-drift) REPAIR_KNOWN_DRIFT=1 ;;
    --sync) SYNC_REMOTE=1 ;;
    *) echo "OPENCODE_PREFLIGHT=BLOCKED_UNKNOWN_ARGUMENT:$arg" >&2; exit 64 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || { echo "OPENCODE_PREFLIGHT=BLOCKED_NOT_GIT_WORKTREE" >&2; exit 64; }
cd "$ROOT"

fail() {
  echo "OPENCODE_PREFLIGHT=BLOCKED"
  echo "REASON=$1"
  exit "${2:-1}"
}

pass() {
  printf 'PASS %-40s\n' "$1"
}

for cmd in git python3 mix; do
  command -v "$cmd" >/dev/null 2>&1 || fail "MISSING_COMMAND_${cmd}" 127
done

BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "WRONG_BRANCH_${BRANCH}_EXPECTED_${EXPECTED_BRANCH}"
[[ "$BRANCH" != "main" && "$BRANCH" != "master" ]] || fail "PROTECTED_BRANCH"
pass "branch"

for marker in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  marker_path="$(git rev-parse --git-path "$marker")"
  [[ ! -e "$marker_path" ]] || fail "GIT_OPERATION_IN_PROGRESS_${marker}"
done
[[ -z "$(git diff --name-only --diff-filter=U)" ]] || fail "UNRESOLVED_CONFLICTS"
pass "git_operation_state"

git fetch origin --prune
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF" 2>/dev/null || true)"
[[ -n "$REMOTE_HEAD" ]] || fail "REMOTE_REF_NOT_FOUND_${REMOTE_REF}"
LOCAL_HEAD="$(git rev-parse HEAD)"
printf 'LOCAL_HEAD=%s\nREMOTE_HEAD=%s\n' "$LOCAL_HEAD" "$REMOTE_HEAD"

if ! git diff --quiet "$REMOTE_REF" -- "$MCP_FILE"; then
  if [[ "$REPAIR_KNOWN_DRIFT" != "1" ]]; then
    echo "MCP_CANONICAL=NO"
    echo "RECOVERY_COMMAND=bash scripts/opencode-preflight.sh --repair-known-drift --sync"
    fail "LOCAL_MCP_DIFFERS_FROM_CANONICAL_REMOTE" 20
  fi

  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_root="${SHADOWOPS_STATE_ROOT:-${HOME}/.local/state/shadowops}/opencode-backups/${stamp}"
  mkdir -p "$backup_root"
  chmod 700 "$backup_root" 2>/dev/null || true
  if [[ -f "$MCP_FILE" ]]; then
    cp -a "$MCP_FILE" "$backup_root/shadowops_runtime_mcp.py.before"
  fi
  git diff -- "$MCP_FILE" > "$backup_root/shadowops_runtime_mcp.diff" || true
  git restore --source="$REMOTE_REF" -- "$MCP_FILE"
  echo "MCP_RECOVERED_FROM=$REMOTE_REF"
  echo "MCP_BACKUP=$backup_root"
fi

git diff --quiet "$REMOTE_REF" -- "$MCP_FILE" || fail "MCP_RECOVERY_DID_NOT_MATCH_REMOTE"
pass "mcp_matches_canonical_remote"

if [[ "$SYNC_REMOTE" == "1" && "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "WORKTREE_CHANGES_AFTER_MCP_RECOVERY:"
    git status --short
    fail "CANNOT_FAST_FORWARD_WITH_OTHER_LOCAL_CHANGES" 21
  fi
  git merge --ff-only "$REMOTE_REF"
  LOCAL_HEAD="$(git rev-parse HEAD)"
  [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || fail "FAST_FORWARD_DID_NOT_REACH_REMOTE_HEAD"
  pass "fast_forward_remote"
fi

[[ -f "$HANDOFF_FILE" ]] || fail "HANDOFF_FILE_MISSING_SYNC_REMOTE_FIRST"
pass "handoff_present"

python3 -m py_compile "$MCP_FILE"
pass "mcp_python_compile"

if command -v uv >/dev/null 2>&1; then
  uv run --with 'mcp>=2,<3' --with 'httpx>=0.28,<1' \
    python -m unittest discover -s ops/mcp -p 'test_*.py' -v
elif python3 -c 'import mcp, httpx' >/dev/null 2>&1; then
  python3 -m unittest discover -s ops/mcp -p 'test_*.py' -v
else
  fail "MCP_TEST_DEPENDENCIES_MISSING_INSTALL_UV_OR_PYTHON_MCP_HTTPX" 22
fi
pass "mcp_tests"

mix format --check-formatted
pass "format_baseline"

mix compile --warnings-as-errors
pass "compile_baseline"

MIX_ENV=test mix test apps/shadowops_core/test/durable_governance_test.exs
pass "governance_baseline_tests"

git diff --check
pass "diff_check"

echo
echo "OPENCODE_PREFLIGHT=PASS"
echo "BRANCH=$(git branch --show-current)"
echo "HEAD=$(git rev-parse HEAD)"
echo "REMOTE_HEAD=$(git rev-parse "$REMOTE_REF")"
echo "MCP_CANONICAL=YES"
echo "HANDOFF=$HANDOFF_FILE"
echo "NEXT_TASK=ATOMIC_SINGLE_USE_APPROVAL_CONSUMPTION"
echo "NEXT_COMMAND=scripts/shadowops-coder.sh --next"
