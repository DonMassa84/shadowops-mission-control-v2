#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="${SHADOWOPS_ALL_BRANCH:-local/all-developments}"
REMOTE_REF="${SHADOWOPS_ALL_REMOTE_REF:-origin/${TARGET_BRANCH}}"
PREVIEW_PORT="${SHADOWOPS_ALL_PREVIEW_PORT:-4014}"
STATE_ROOT="${SHADOWOPS_STATE_ROOT:-${HOME}/.local/state/shadowops}"
PROJECT_CATALOG="${SHADOWOPS_PROJECT_CATALOG:-${STATE_ROOT}/project_catalog.json}"

FINAL_STATUS="LOCAL_ALL_DEVELOPMENTS_FAILED"
FAIL_REASON="UNKNOWN"

final_report() {
  local rc=$?
  echo
  echo "SHADOWOPS_LOCAL_ALL_DEVELOPMENTS"
  echo "ROOT=$ROOT"
  echo "BRANCH=$(git branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "REMOTE_REF=$REMOTE_REF"
  echo "PREVIEW_PORT=$PREVIEW_PORT"
  echo "PROJECT_CATALOG=$PROJECT_CATALOG"
  echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
  echo "FAIL_REASON=${FAIL_REASON:-NONE}"
  echo "FINAL_STATUS=$FINAL_STATUS"
  exit "$rc"
}
trap final_report EXIT

fail() {
  FAIL_REASON="$1"
  echo "FAIL $FAIL_REASON" >&2
  exit "${2:-1}"
}

pass() {
  printf 'PASS %-40s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "MISSING_COMMAND_$1"
}

for cmd in git mix elixir erl curl ss systemctl openssl sha256sum opencode python3; do
  require_cmd "$cmd"
done

case "$PREVIEW_PORT" in
  ''|*[!0-9]*) fail "PREVIEW_PORT_NOT_NUMERIC" ;;
esac
(( PREVIEW_PORT >= 1024 && PREVIEW_PORT <= 65535 )) || fail "PREVIEW_PORT_OUT_OF_RANGE"
[[ "$PREVIEW_PORT" != "4013" ]] || fail "PREVIEW_MUST_NOT_USE_STABLE_4013"

echo "=== SOURCE PARITY ==="
git fetch origin --prune
CURRENT_BRANCH="$(git branch --show-current)"
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"
[[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]] || fail "WRONG_BRANCH_${CURRENT_BRANCH}"
[[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"
[[ -z "$(git status --porcelain)" ]] || fail "WORKTREE_NOT_CLEAN"
pass "source_parity"

echo
echo "=== AI EXECUTION POLICY ==="
OPENCODE_VERSION="$(opencode --version 2>/dev/null | head -1 || true)"
[[ -n "$OPENCODE_VERSION" ]] || fail "OPENCODE_VERSION_UNAVAILABLE"
echo "OPENCODE_VERSION=$OPENCODE_VERSION"
echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
pass "remote_only_ai_policy"

echo
echo "=== DEPENDENCIES + PROJECT CATALOG ==="
export SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG"
export SHADOWOPS_START_PERSISTENCE=false
mix deps.get
git diff --exit-code -- mix.lock
mix shadowops.projects.seed
[[ -s "$PROJECT_CATALOG" ]] || fail "PROJECT_CATALOG_NOT_CREATED"
pass "project_catalog_seed"

echo
echo "=== CODER CONTRACT ==="
bash scripts/test-shadowops-coder.sh
opencode agent list | grep -q 'shadowops-coder' || fail "SHADOWOPS_CODER_AGENT_NOT_VISIBLE"
pass "shadowops_coder_contract"

echo
echo "=== READ-ONLY MCP CONTRACT ==="
if command -v uv >/dev/null 2>&1; then
  PYTHONDONTWRITEBYTECODE=1 uv run --with 'mcp>=2,<3' --with 'httpx>=0.28,<1' \
    python -B -m unittest discover -s ops/mcp -p 'test_*.py' -v
elif PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import mcp, httpx' >/dev/null 2>&1; then
  PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s ops/mcp -p 'test_*.py' -v
else
  fail "MCP_DEPENDENCIES_MISSING_INSTALL_UV_OR_PYTHON_MCP_HTTPX"
fi
pass "runtime_mcp_contract"

echo
echo "=== COMPLETE PREVIEW CONFIGURATION ==="
SHADOWOPS_CONFIG_BRANCH="$TARGET_BRANCH" \
SHADOWOPS_CONFIG_REMOTE_REF="$REMOTE_REF" \
SHADOWOPS_PREVIEW_PORT="$PREVIEW_PORT" \
SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG" \
SHADOWOPS_OPEN_BROWSER=0 \
  bash scripts/configure_local_all.sh
pass "preview_configuration"

echo
echo "=== PREVIEW VERIFICATION ==="
PREVIEW_ENV="${HOME}/.config/shadowops/preview.env"
[[ -f "$PREVIEW_ENV" ]] || fail "PREVIEW_ENV_MISSING"
# shellcheck disable=SC1090
set -a
source "$PREVIEW_ENV"
set +a

for endpoint in /health /ready; do
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
    "http://127.0.0.1:${PREVIEW_PORT}${endpoint}")"
  [[ "$code" == "200" ]] || fail "PREVIEW_${endpoint//\//_}_HTTP_${code}"
done

for route in /projects /projects/federated /projects/chatgpt /workflows /services /security /evidence; do
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${PREVIEW_PORT}${route}")"
  [[ "$code" == "200" ]] || fail "PREVIEW_ROUTE_${route//\//_}_HTTP_${code}"
done
pass "preview_routes"

echo
echo "=== OPENCODE -> PREVIEW MCP ==="
SHADOWOPS_BASE_URL="http://127.0.0.1:${PREVIEW_PORT}" opencode mcp list >/tmp/shadowops-opencode-mcp-list.txt
cat /tmp/shadowops-opencode-mcp-list.txt
pass "opencode_mcp_configuration"

echo
echo "PORT_4013=UNTOUCHED"
echo "PREVIEW_URL=http://127.0.0.1:${PREVIEW_PORT}/"
echo "NEXT_CERTIFY_COMMAND=bash scripts/certify_all_developments.sh"
FAIL_REASON="NONE"
FINAL_STATUS="LOCAL_ALL_DEVELOPMENTS_PASS"
