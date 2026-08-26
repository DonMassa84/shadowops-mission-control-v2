#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="${SHADOWOPS_PROMOTE_BRANCH:-local/all-developments}"
REMOTE_REF="${SHADOWOPS_PROMOTE_REMOTE_REF:-origin/${TARGET_BRANCH}}"
PREVIEW_PORT="${SHADOWOPS_PROMOTE_PREVIEW_PORT:-4014}"
STABLE_PORT="4013"
SERVICE="${SHADOWOPS_STABLE_SERVICE:-shadowops-phoenix.service}"
STATE_ROOT="${SHADOWOPS_STATE_ROOT:-${HOME}/.local/state/shadowops}"
CERT_DIR="${SHADOWOPS_CERT_DIR:-${STATE_ROOT}/certified-releases}"
RELEASES_ROOT="${SHADOWOPS_RELEASES_ROOT:-${HOME}/Projects/shadowops-releases}"
DROPIN_DIR="${HOME}/.config/systemd/user/${SERVICE}.d"
DROPIN_FILE="${DROPIN_DIR}/90-certified-release.conf"
PROJECT_CATALOG="${SHADOWOPS_PROJECT_CATALOG:-${STATE_ROOT}/project_catalog.json}"
PREVIEW_ENV="${HOME}/.config/shadowops/preview.env"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PROMOTION_DIR="${STATE_ROOT}/promotions/${STAMP}"

FAIL_REASON="UNKNOWN"
FINAL_STATUS="STABLE_4013_PROMOTION_FAILED"
SWITCHED=0
PRIOR_DROPIN_PRESENT=0

rollback() {
  set +e
  echo "=== AUTOMATIC ROLLBACK ===" >&2
  if [[ "$PRIOR_DROPIN_PRESENT" == "1" && -f "$PROMOTION_DIR/90-certified-release.conf.before" ]]; then
    cp -a "$PROMOTION_DIR/90-certified-release.conf.before" "$DROPIN_FILE"
  else
    rm -f "$DROPIN_FILE"
  fi
  systemctl --user daemon-reload
  systemctl --user restart "$SERVICE"
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${STABLE_PORT}/health" >/dev/null 2>&1; then
      echo "ROLLBACK_HEALTH=PASS" >&2
      return 0
    fi
    sleep 1
  done
  echo "ROLLBACK_HEALTH=FAIL" >&2
  systemctl --user status "$SERVICE" --no-pager >&2 || true
  journalctl --user -u "$SERVICE" -n 100 --no-pager >&2 || true
  return 1
}

report() {
  local rc=$?
  if [[ "$rc" != "0" && "$SWITCHED" == "1" ]]; then
    rollback || true
  fi
  echo
  echo "SHADOWOPS_STABLE_4013_PROMOTION"
  echo "BRANCH=$(git branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "SERVICE=$SERVICE"
  echo "STABLE_PORT=$STABLE_PORT"
  echo "PREVIEW_PORT=$PREVIEW_PORT"
  echo "PROMOTION_DIR=$PROMOTION_DIR"
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

[[ "${SHADOWOPS_PROMOTE_STABLE:-NO}" == "YES" ]] || fail "EXPLICIT_PROMOTION_OPT_IN_REQUIRED_SET_SHADOWOPS_PROMOTE_STABLE=YES" 64

for cmd in git curl systemctl journalctl sha256sum tar awk sed; do
  command -v "$cmd" >/dev/null 2>&1 || fail "MISSING_COMMAND_$cmd"
done

echo "=== SOURCE + CERTIFICATE ==="
git fetch origin --prune
BRANCH="$(git branch --show-current)"
HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"
[[ "$BRANCH" == "$TARGET_BRANCH" ]] || fail "WRONG_BRANCH_${BRANCH}"
[[ "$HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"
[[ -z "$(git status --porcelain)" ]] || fail "WORKTREE_NOT_CLEAN"

CERT_FILE="$CERT_DIR/${HEAD}.env"
[[ -f "$CERT_FILE" ]] || fail "CERTIFICATE_MISSING_RUN_CERTIFY_ALL_DEVELOPMENTS_FIRST"
# shellcheck disable=SC1090
source "$CERT_FILE"
[[ "${CERT_SCHEMA:-}" == "shadowops-certified-release-v1" ]] || fail "CERTIFICATE_SCHEMA_INVALID"
[[ "${HEAD:-}" == "$(git rev-parse HEAD)" ]] || fail "CERTIFICATE_HEAD_MISMATCH"
[[ "${BRANCH:-}" == "$TARGET_BRANCH" ]] || fail "CERTIFICATE_BRANCH_MISMATCH"
for gate in FORMAT COMPILE TESTS CREDO DIALYZER SOBELOW REGISTRY WORKFLOW_IDS HEX_AUDIT PRODUCTION_HANDOFF MCP_CONTRACT LOCAL_CODER_CONTRACT; do
  [[ "${!gate:-}" == "PASS" ]] || fail "CERTIFICATE_GATE_${gate}_NOT_PASS"
done
[[ -f "${ARTIFACT:-}" ]] || fail "CERTIFIED_ARTIFACT_MISSING"
ACTUAL_SHA="$(sha256sum "$ARTIFACT" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "${ARTIFACT_SHA256:-}" ]] || fail "CERTIFIED_ARTIFACT_SHA256_MISMATCH"
pass "certificate_and_artifact"

echo
echo "=== PREVIEW CANDIDATE STILL HEALTHY ==="
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
pass "preview_candidate"

echo
echo "=== CURRENT STABLE SNAPSHOT ==="
systemctl --user status "$SERVICE" --no-pager >/dev/null 2>&1 || fail "STABLE_SERVICE_NOT_LOADED"
systemctl --user is-active --quiet "$SERVICE" || fail "STABLE_SERVICE_NOT_ACTIVE"
curl -fsS --max-time 5 "http://127.0.0.1:${STABLE_PORT}/health" >/dev/null || fail "CURRENT_STABLE_4013_NOT_HEALTHY"
mkdir -p "$PROMOTION_DIR" "$DROPIN_DIR" "$RELEASES_ROOT"
chmod 700 "$PROMOTION_DIR" "$RELEASES_ROOT" 2>/dev/null || true
umask 077
systemctl --user cat "$SERVICE" > "$PROMOTION_DIR/service.before.txt"
systemctl --user show "$SERVICE" -p WorkingDirectory -p ExecStart -p MainPID -p ActiveState -p SubState > "$PROMOTION_DIR/service.show.before.txt"
if [[ -f "$DROPIN_FILE" ]]; then
  PRIOR_DROPIN_PRESENT=1
  cp -a "$DROPIN_FILE" "$PROMOTION_DIR/90-certified-release.conf.before"
fi
pass "stable_snapshot"

echo
echo "=== IMMUTABLE CERTIFIED RELEASE WORKTREE ==="
RELEASE_ROOT="$RELEASES_ROOT/$HEAD"
SOURCE_DIR="$RELEASE_ROOT/source"
if [[ -e "$SOURCE_DIR" ]]; then
  [[ -d "$SOURCE_DIR/.git" || -f "$SOURCE_DIR/.git" ]] || fail "RELEASE_SOURCE_PATH_EXISTS_NOT_WORKTREE"
  [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" == "$HEAD" ]] || fail "EXISTING_RELEASE_WORKTREE_HEAD_MISMATCH"
  [[ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ]] || fail "EXISTING_RELEASE_WORKTREE_DIRTY"
else
  mkdir -p "$RELEASE_ROOT"
  git worktree add --detach "$SOURCE_DIR" "$HEAD"
fi
mkdir -p "$SOURCE_DIR/_build/prod/rel"
rm -rf "$SOURCE_DIR/_build/prod/rel/shadowops"
tar -C "$SOURCE_DIR/_build/prod/rel" -xzf "$ARTIFACT"
[[ -x "$SOURCE_DIR/_build/prod/rel/shadowops/bin/shadowops" ]] || fail "EXTRACTED_RELEASE_BINARY_MISSING"
[[ -f "$SOURCE_DIR/config/workflow_registry_v2.yaml" ]] || fail "CERTIFIED_SOURCE_REGISTRY_MISSING"
pass "immutable_release_worktree"

echo
echo "=== SWITCH STABLE SERVICE TO CERTIFIED RELEASE ==="
TMP_DROPIN="$DROPIN_FILE.tmp.$$"
cat > "$TMP_DROPIN" <<EOF
[Service]
WorkingDirectory=$SOURCE_DIR
Environment=PORT=$STABLE_PORT
Environment=SHADOWOPS_PROJECT_CATALOG=$PROJECT_CATALOG
ExecStart=
ExecStart=$SOURCE_DIR/_build/prod/rel/shadowops/bin/shadowops start
ExecStop=
ExecStop=$SOURCE_DIR/_build/prod/rel/shadowops/bin/shadowops stop
EOF
mv "$TMP_DROPIN" "$DROPIN_FILE"
chmod 600 "$DROPIN_FILE"
SWITCHED=1
systemctl --user daemon-reload
systemctl --user restart "$SERVICE"

READY=0
for _ in $(seq 1 45); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${STABLE_PORT}/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
[[ "$READY" == "1" ]] || fail "PROMOTED_STABLE_NOT_HEALTHY"
pass "stable_restart"

echo
echo "=== POST-PROMOTION ACCEPTANCE ==="
for endpoint in /health /ready; do
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${STABLE_PORT}${endpoint}")"
  [[ "$code" == "200" ]] || fail "STABLE_${endpoint//\//_}_HTTP_${code}"
done
for route in /projects /projects/federated /projects/chatgpt /workflows /services /security /evidence; do
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${STABLE_PORT}${route}")"
  [[ "$code" == "200" ]] || fail "STABLE_ROUTE_${route//\//_}_HTTP_${code}"
done
ACTUAL_WD="$(systemctl --user show "$SERVICE" -p WorkingDirectory --value)"
[[ "$ACTUAL_WD" == "$SOURCE_DIR" ]] || fail "STABLE_WORKING_DIRECTORY_MISMATCH"
systemctl --user show "$SERVICE" -p WorkingDirectory -p ExecStart -p MainPID -p ActiveState -p SubState > "$PROMOTION_DIR/service.show.after.txt"
printf '%s\n' "$HEAD" > "$PROMOTION_DIR/PROMOTED_HEAD.txt"
printf '%s\n' "$ARTIFACT_SHA256" > "$PROMOTION_DIR/ARTIFACT_SHA256.txt"
pass "post_promotion_acceptance"

SWITCHED=0
FAIL_REASON="NONE"
FINAL_STATUS="STABLE_4013_PROMOTION_PASS"
echo "PROMOTED_HEAD=$HEAD"
echo "STABLE_WORKING_DIRECTORY=$SOURCE_DIR"
echo "ROLLBACK_SNAPSHOT=$PROMOTION_DIR"
echo "PREVIEW_4014=LEFT_RUNNING"
