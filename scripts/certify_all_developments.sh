#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="${SHADOWOPS_CERT_BRANCH:-local/all-developments}"
REMOTE_REF="${SHADOWOPS_CERT_REMOTE_REF:-origin/${TARGET_BRANCH}}"
PREVIEW_PORT="${SHADOWOPS_CERT_PREVIEW_PORT:-4014}"
SMOKE_PORT="${SHADOWOPS_CERT_SMOKE_PORT:-4015}"
STATE_ROOT="${SHADOWOPS_STATE_ROOT:-${HOME}/.local/state/shadowops}"
PROJECT_CATALOG="${SHADOWOPS_PROJECT_CATALOG:-${STATE_ROOT}/project_catalog.json}"
CERT_DIR="${SHADOWOPS_CERT_DIR:-${STATE_ROOT}/certified-releases}"
PREVIEW_ENV="${HOME}/.config/shadowops/preview.env"

FAIL_REASON="UNKNOWN"
FINAL_STATUS="ALL_DEVELOPMENTS_CERTIFICATION_FAILED"

report() {
  local rc=$?
  echo
  echo "SHADOWOPS_ALL_DEVELOPMENTS_CERTIFICATION"
  echo "BRANCH=$(git branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "PROJECT_CATALOG=$PROJECT_CATALOG"
  echo "PREVIEW_PORT=$PREVIEW_PORT"
  echo "SMOKE_PORT=$SMOKE_PORT"
  echo "CERT_DIR=$CERT_DIR"
  echo "FAIL_REASON=${FAIL_REASON:-NONE}"
  echo "FINAL_STATUS=$FINAL_STATUS"
  exit "$rc"
}
trap report EXIT

fail() {
  FAIL_REASON="$1"
  echo "FAIL $FAIL_REASON" >&2
  exit "${2:-1}"
}

pass() {
  printf 'PASS %-40s\n' "$1"
}

run_isolated_test_suite() {
  local clean_user="${USER:-$(id -un)}"
  local clean_lang="${LANG:-C.UTF-8}"

  env -i \
    HOME="$HOME" \
    USER="$clean_user" \
    LOGNAME="$clean_user" \
    PATH="$PATH" \
    LANG="$clean_lang" \
    MIX_ENV=test \
    SHADOWOPS_START_PERSISTENCE=false \
    mix test --seed 12345
}

for cmd in git mix elixir erl curl ss tar sha256sum date; do
  command -v "$cmd" >/dev/null 2>&1 || fail "MISSING_COMMAND_$cmd"
done

[[ "$PREVIEW_PORT" != "4013" && "$SMOKE_PORT" != "4013" ]] || fail "CERTIFICATION_MUST_NOT_BIND_4013"
[[ "$PREVIEW_PORT" != "$SMOKE_PORT" ]] || fail "PREVIEW_AND_SMOKE_PORT_COLLISION"

echo "=== SOURCE PARITY ==="
git fetch origin --prune
BRANCH="$(git branch --show-current)"
HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"
[[ "$BRANCH" == "$TARGET_BRANCH" ]] || fail "WRONG_BRANCH_${BRANCH}"
[[ "$HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"
[[ -z "$(git status --porcelain)" ]] || fail "WORKTREE_NOT_CLEAN"
pass "source_parity"

echo
echo "=== PREVIEW 4014 EVIDENCE ==="
[[ -f "$PREVIEW_ENV" ]] || fail "PREVIEW_ENV_MISSING_RUN_LOCAL_ALL_DEVELOPMENTS_FIRST"
# shellcheck disable=SC1090
set -a
source "$PREVIEW_ENV"
set +a
export SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG"

for endpoint in /health /ready; do
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
    "http://127.0.0.1:${PREVIEW_PORT}${endpoint}")"
  [[ "$code" == "200" ]] || fail "PREVIEW_${endpoint//\//_}_HTTP_${code}"
done
[[ -s "$PROJECT_CATALOG" ]] || fail "PROJECT_CATALOG_MISSING"
pass "preview_and_catalog"

echo
echo "=== FULL STATIC + SECURITY GATES ==="
export SHADOWOPS_START_PERSISTENCE=false
mix deps.get
git diff --exit-code -- mix.lock
mix format --check-formatted
mix compile --warnings-as-errors
run_isolated_test_suite
mix credo --strict
mix dialyzer
mix sobelow --exit
mix shadowops.registry validate
mix shadowops.workflow_ids.validate
mix hex.audit
git diff --check
pass "static_security_quality"

echo
echo "=== LOCAL CODER + MCP CONTRACTS ==="
bash scripts/test-shadowops-coder.sh
if command -v uv >/dev/null 2>&1; then
  uv run --with 'mcp>=2,<3' --with 'httpx>=0.28,<1' \
    python -m unittest discover -s ops/mcp -p 'test_*.py' -v
elif python3 -c 'import mcp, httpx' >/dev/null 2>&1; then
  python3 -m unittest discover -s ops/mcp -p 'test_*.py' -v
else
  fail "MCP_DEPENDENCIES_MISSING"
fi
pass "coder_and_mcp_contracts"

echo
echo "=== ISOLATED PRODUCTION HANDOFF ON 4015 ==="
SHADOWOPS_HANDOFF_BRANCH="$TARGET_BRANCH" \
SHADOWOPS_HANDOFF_REMOTE_REF="$REMOTE_REF" \
SHADOWOPS_HANDOFF_PORT="$SMOKE_PORT" \
SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG" \
  bash scripts/local_production_handoff.sh
pass "production_handoff"

echo
echo "=== CERTIFIED RELEASE ARTIFACT ==="
RELEASE_DIR="$ROOT/_build/prod/rel/shadowops"
[[ -x "$RELEASE_DIR/bin/shadowops" ]] || fail "RELEASE_BINARY_MISSING"
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR" 2>/dev/null || true
umask 077

ARTIFACT="$CERT_DIR/shadowops-${HEAD}.tar.gz"
SHA_FILE="$ARTIFACT.sha256"
CERT_FILE="$CERT_DIR/${HEAD}.env"
TMP_ARTIFACT="$ARTIFACT.tmp.$$"
TMP_CERT="$CERT_FILE.tmp.$$"

tar -C "$ROOT/_build/prod/rel" -czf "$TMP_ARTIFACT" shadowops
mv "$TMP_ARTIFACT" "$ARTIFACT"
ARTIFACT_SHA256="$(sha256sum "$ARTIFACT" | awk '{print $1}')"
printf '%s  %s\n' "$ARTIFACT_SHA256" "$ARTIFACT" > "$SHA_FILE"

cat > "$TMP_CERT" <<EOF
CERT_SCHEMA=shadowops-certified-release-v1
BRANCH=$TARGET_BRANCH
HEAD=$HEAD
REMOTE_REF=$REMOTE_REF
ARTIFACT=$ARTIFACT
ARTIFACT_SHA256=$ARTIFACT_SHA256
CERTIFIED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROJECT_CATALOG=$PROJECT_CATALOG
PREVIEW_PORT=$PREVIEW_PORT
SMOKE_PORT=$SMOKE_PORT
FORMAT=PASS
COMPILE=PASS
TESTS=PASS
CREDO=PASS
DIALYZER=PASS
SOBELOW=PASS
REGISTRY=PASS
WORKFLOW_IDS=PASS
HEX_AUDIT=PASS
PRODUCTION_HANDOFF=PASS
MCP_CONTRACT=PASS
LOCAL_CODER_CONTRACT=PASS
EOF
mv "$TMP_CERT" "$CERT_FILE"
chmod 600 "$ARTIFACT" "$SHA_FILE" "$CERT_FILE"

sha256sum -c "$SHA_FILE"
pass "certified_artifact"

echo "CERT_FILE=$CERT_FILE"
echo "ARTIFACT=$ARTIFACT"
echo "ARTIFACT_SHA256=$ARTIFACT_SHA256"
echo "NEXT_PROMOTION_COMMAND=SHADOWOPS_PROMOTE_STABLE=YES bash scripts/promote_stable_4013.sh"
FAIL_REASON="NONE"
FINAL_STATUS="ALL_DEVELOPMENTS_CERTIFIED"
