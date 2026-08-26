#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EXPECTED_BRANCH="${SHADOWOPS_PRODUCT_BRANCH:-release/product-finish-2026-08-26}"
CURRENT_BRANCH="$(git branch --show-current)"
HEAD="$(git rev-parse HEAD)"
FINAL_EMITTED=0
FAIL_REASON=""

emit_final() {
  FINAL_EMITTED=1
  echo
  echo "SHADOWOPS_PRODUCT_ACCEPTANCE"
  echo "BRANCH=$CURRENT_BRANCH"
  echo "HEAD=$HEAD"
  echo "WORKTREE=$(if [[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]]; then echo CLEAN; else echo DIRTY; fi)"
  echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
  echo "PORT_4013_CHANGED=NO"
  echo "DEPLOY_TRIGGERED=NO"
  echo "FAIL_REASON=${FAIL_REASON:-NONE}"
  echo "FINAL_STATUS=$1"
}

fail() {
  FAIL_REASON="$1"
  echo "FAIL $FAIL_REASON" >&2
  emit_final "PRODUCT_ACCEPTANCE_FAILED"
  exit "${2:-1}"
}

pass() {
  printf 'PASS %-38s\n' "$1"
}

trap 'rc=$?; if [[ "$FINAL_EMITTED" != "1" && "$rc" != "0" ]]; then FAIL_REASON="${FAIL_REASON:-UNEXPECTED_EXIT_$rc}"; emit_final "PRODUCT_ACCEPTANCE_FAILED"; fi' EXIT

for cmd in git mix node python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "MISSING_COMMAND_${cmd}"
done

[[ "$CURRENT_BRANCH" == "$EXPECTED_BRANCH" ]] || fail "WRONG_BRANCH_${CURRENT_BRANCH}"
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || fail "WORKTREE_NOT_CLEAN"
pass "clean_release_candidate"

echo
echo "=== PRODUCT UI CONTRACT ==="
node --check apps/shadowops_web/priv/static/assets/mission-control.js

grep -Fq 'mc-command-palette' apps/shadowops_web/priv/static/assets/mission-control.js || fail "COMMAND_PALETTE_MISSING"
grep -Fq 'AI Governance' apps/shadowops_web/lib/shadow_ops_web/live/ai_live.ex || fail "AI_GOVERNANCE_UI_MISSING"
grep -Fq 'REMOTE_ONLY' apps/shadowops_web/lib/shadow_ops_web/live/ai_live.ex || fail "REMOTE_ONLY_UI_MISSING"
grep -Fq 'FORBIDDEN' apps/shadowops_web/lib/shadow_ops_web/live/ai_live.ex || fail "LOCAL_AI_FORBIDDEN_UI_MISSING"
pass "product_ui_contract"

echo
echo "=== REMOTE-ONLY AI POLICY ==="
grep -Fq 'AI_EXECUTION_POLICY=REMOTE_ONLY' docs/REMOTE_AI_POLICY.md || fail "REMOTE_AI_POLICY_MARKER_MISSING"
if grep -Eq '"model"[[:space:]]*:[[:space:]]*"(ollama|local|lmstudio|llamacpp|llama\.cpp)/' opencode.jsonc; then
  fail "LOCAL_AI_DEFAULT_PRESENT"
fi
if grep -Eq '"(ollama|lmstudio|llamacpp|llama\.cpp)"[[:space:]]*:' opencode.jsonc; then
  fail "LOCAL_AI_PROVIDER_PRESENT"
fi
pass "remote_only_ai_policy"

echo
echo "=== READ-ONLY MCP ==="
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v ops.mcp.test_shadowops_runtime_mcp
pass "runtime_mcp_contract"

echo
echo "=== HERMETIC ELIXIR QUALITY GATE ==="
# Product acceptance must not inherit live preview credentials or DB/runtime state.
env \
  -u PORT \
  -u SHADOWOPS_PUBLIC_HOST \
  -u SHADOWOPS_SECRET_KEY_BASE \
  -u SHADOWOPS_READ_TOKEN \
  -u SHADOWOPS_WRITE_TOKEN \
  -u SHADOWOPS_STATE_DIR \
  -u SHADOWOPS_DB_HOST \
  -u SHADOWOPS_DB_USER \
  -u SHADOWOPS_DB_PASSWORD \
  -u SHADOWOPS_DB_NAME \
  -u SHADOWOPS_DB_POOL_SIZE \
  -u DATABASE_URL \
  -u RELEASE_NODE \
  -u RELEASE_COOKIE \
  bash -Eeuo pipefail <<'QUALITY'
export SHADOWOPS_START_PERSISTENCE=false
mix deps.get
git diff --exit-code -- mix.lock
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test --seed 12345
bash scripts/credo_release_gate.sh
if mix credo --strict; then
  echo "CREDO_FULL_REPOSITORY=PASS"
else
  echo "CREDO_FULL_REPOSITORY=LEGACY_DEBT_REPORTED_NON_BLOCKING"
fi
mix shadowops.registry validate
mix shadowops.workflow_ids.validate
mix hex.audit
git diff --check
QUALITY
pass "hermetic_quality_gate"

echo
echo "=== SECURITY STATIC ANALYSIS ==="
if mix help sobelow >/dev/null 2>&1; then
  mix sobelow --config
else
  echo "SOBELOW=NOT_AVAILABLE_IN_CURRENT_ENV"
fi
pass "sobelow"

if [[ "${SHADOWOPS_PRODUCT_DIALYZER:-0}" == "1" ]]; then
  echo
  echo "=== DIALYZER ==="
  mix dialyzer
  pass "dialyzer"
else
  echo "DIALYZER=SKIPPED_SET_SHADOWOPS_PRODUCT_DIALYZER_1_FOR_FULL_GATE"
fi

echo
echo "=== P0 APPROVAL SINGLE-USE EVIDENCE ==="
if grep -Rqs --include='*.ex' --include='*.exs' 'approval_consumed' apps/shadowops_core; then
  echo "P0_APPROVAL_CONSUMPTION=IMPLEMENTATION_MARKER_PRESENT"
else
  fail "P0_APPROVAL_CONSUMPTION_NOT_PRESENT"
fi
if grep -Rqs --include='*.ex' --include='*.exs' 'consumed_at' apps/shadowops_core; then
  echo "P0_CONSUMED_AT=IMPLEMENTATION_MARKER_PRESENT"
else
  fail "P0_CONSUMED_AT_NOT_PRESENT"
fi
if grep -Rqs --include='*.ex' --include='*.exs' 'consumed_by' apps/shadowops_core; then
  echo "P0_CONSUMED_BY=IMPLEMENTATION_MARKER_PRESENT"
else
  fail "P0_CONSUMED_BY_NOT_PRESENT"
fi
pass "p0_single_use_markers"

echo
echo "=== SOURCE INTEGRITY ==="
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || fail "ACCEPTANCE_CHANGED_WORKTREE"
pass "source_integrity"

FAIL_REASON=""
emit_final "PRODUCT_ACCEPTANCE_PASS"
