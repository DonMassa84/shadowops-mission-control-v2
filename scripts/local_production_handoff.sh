#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="${SHADOWOPS_HANDOFF_BRANCH:-hardening/production-ready-2026-08-25}"
REMOTE_REF="${SHADOWOPS_HANDOFF_REMOTE_REF:-origin/${TARGET_BRANCH}}"
PORT="${SHADOWOPS_HANDOFF_PORT:-4014}"
STATE_ROOT="${SHADOWOPS_HANDOFF_STATE_ROOT:-${HOME}/.local/state/shadowops/handoff}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${STATE_ROOT}/handoff-${STAMP}.log"

mkdir -p "$STATE_ROOT"
chmod 700 "$STATE_ROOT" 2>/dev/null || true
umask 077

exec > >(tee "$REPORT") 2>&1

FAIL_REASON=""
FINAL_EMITTED=0

emit_final() {
  local status="$1"
  FINAL_EMITTED=1
  echo
  echo "SHADOWOPS_LOCAL_PRODUCTION_HANDOFF"
  echo "ROOT=$ROOT"
  echo "BRANCH=$(git branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "REMOTE_REF=$REMOTE_REF"
  echo "REMOTE_HEAD=$(git rev-parse "$REMOTE_REF" 2>/dev/null || true)"
  echo "REPORT=$REPORT"
  echo "RUNTIME_PORT=$PORT"
  echo "FAIL_REASON=${FAIL_REASON:-NONE}"
  echo "FINAL_STATUS=$status"
}

on_exit() {
  local rc=$?
  if [[ "$FINAL_EMITTED" != "1" && "$rc" != "0" ]]; then
    emit_final "LOCAL_PRODUCTION_HANDOFF_FAILED"
  fi
  exit "$rc"
}
trap on_exit EXIT

fail() {
  FAIL_REASON="$1"
  echo "FAIL $FAIL_REASON" >&2
  exit "${2:-1}"
}

pass() {
  printf 'PASS %-32s\n' "$1"
}

validate_port() {
  case "$PORT" in
    ''|*[!0-9]*) fail "HANDOFF_PORT_NOT_NUMERIC" 2 ;;
  esac
  if (( PORT < 1024 || PORT > 65535 )); then
    fail "HANDOFF_PORT_OUT_OF_RANGE" 2
  fi
}

critical_untracked_files() {
  git ls-files --others --exclude-standard -- apps config test .github scripts 2>/dev/null || true
}

certified_toolchain() {
  local elixir_version="$1"
  local otp_major="$2"

  case "${elixir_version}/${otp_major}" in
    1.17.3/27|1.20.3/28) return 0 ;;
    *) return 1 ;;
  esac
}

validate_port

echo "=== SHADOWOPS LOCAL PRODUCTION HANDOFF ==="
echo "ROOT=$ROOT"
echo "TARGET_BRANCH=$TARGET_BRANCH"
echo "REMOTE_REF=$REMOTE_REF"
echo "PORT=$PORT"
echo "REPORT=$REPORT"

echo
echo "=== SOURCE PARITY ==="
git fetch origin --prune

CURRENT_BRANCH="$(git branch --show-current)"
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"

printf 'CURRENT_BRANCH=%s\nLOCAL_HEAD=%s\nREMOTE_HEAD=%s\n' "$CURRENT_BRANCH" "$LOCAL_HEAD" "$REMOTE_HEAD"

[[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]] || fail "WRONG_BRANCH"
[[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"

git diff --quiet "$REMOTE_REF" -- . || fail "TRACKED_WORKTREE_DIFFERS_FROM_REMOTE"
git diff --cached --quiet || fail "STAGED_CHANGES_PRESENT"

UNTRACKED_SOURCE="$(critical_untracked_files)"
if [[ -n "$UNTRACKED_SOURCE" ]]; then
  echo "Untracked source/config/test files can shadow the proven Git tree:" >&2
  printf '%s\n' "$UNTRACKED_SOURCE" >&2
  fail "UNTRACKED_SOURCE_FILES_PRESENT"
fi
pass "source_parity"

echo
echo "=== TOOLCHAIN ==="
ELIXIR_VERSION="$(elixir --version | awk '/^Elixir / {print $2; exit}')"
OTP_MAJOR="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)"
echo "ELIXIR_VERSION=$ELIXIR_VERSION"
echo "OTP_MAJOR=$OTP_MAJOR"
echo "CERTIFIED_TOOLCHAINS=1.17.3/27,1.20.3/28"
certified_toolchain "$ELIXIR_VERSION" "$OTP_MAJOR" || fail "UNCERTIFIED_BEAM_TOOLCHAIN"
pass "toolchain"

echo
echo "=== CLEAN GENERATED BUILD STATE ==="
MIX_ENV=test mix clean
MIX_ENV=prod mix clean
pass "generated_build_state_clean"

echo
echo "=== DEPENDENCIES ==="
export SHADOWOPS_START_PERSISTENCE=false
MIX_ENV=test mix deps.get
git diff --exit-code -- mix.lock
git diff --quiet "$REMOTE_REF" -- . || fail "SOURCE_CHANGED_DURING_DEPENDENCY_RESOLUTION"
pass "dependencies_locked"

echo
echo "=== STATIC QUALITY GATES ==="
MIX_ENV=test mix format --check-formatted
pass "format"
MIX_ENV=test mix compile --warnings-as-errors
pass "compile"
MIX_ENV=test mix test --seed 12345
pass "tests"
MIX_ENV=test mix shadowops.registry validate
pass "registry"
MIX_ENV=test mix shadowops.workflow_ids.validate
pass "workflow_ids"
MIX_ENV=test mix hex.audit
pass "dependency_audit"
git diff --check
pass "whitespace"
SHADOWOPS_RUNTIME_REQUIRED=0 MIX_ENV=test bash scripts/production_acceptance.sh
pass "static_production_acceptance"

echo
echo "=== PRODUCTION RELEASE ==="
MIX_ENV=prod mix release shadowops --overwrite
[[ -x _build/prod/rel/shadowops/bin/shadowops ]] || fail "PRODUCTION_RELEASE_MISSING"
pass "production_release"

echo
echo "=== SAFE RUNTIME PORT CHECK ==="
if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -Eq "[:.]${PORT}[[:space:]]"; then
    fail "HANDOFF_PORT_ALREADY_IN_USE"
  fi
else
  echo "WARN ss not available; relying on release bind failure for port collision detection"
fi
pass "runtime_port_available"

echo
echo "=== PRODUCTION RELEASE RUNTIME SMOKE ==="
timeout 240s env \
  MIX_ENV=prod \
  PORT="$PORT" \
  SHADOWOPS_START_PERSISTENCE=false \
  SHADOWOPS_STATE_DIR="${STATE_ROOT}/runtime-${STAMP}" \
  bash scripts/release_runtime_gate.sh
pass "release_runtime_gate"

echo
echo "=== POST-RUN SOURCE INTEGRITY ==="
git diff --quiet "$REMOTE_REF" -- . || fail "SOURCE_CHANGED_DURING_HANDOFF"
git diff --cached --quiet || fail "STAGED_CHANGES_CREATED_DURING_HANDOFF"
[[ -z "$(critical_untracked_files)" ]] || fail "UNTRACKED_SOURCE_CREATED_DURING_HANDOFF"
pass "source_integrity"

FAIL_REASON=""
emit_final "LOCAL_PRODUCTION_HANDOFF_PASS"
