#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRANCH="${SHADOWOPS_PRODUCT_BRANCH:-release/product-finish-2026-08-26}"
REMOTE_REF="${SHADOWOPS_PRODUCT_REMOTE_REF:-origin/${BRANCH}}"
PORT="${SHADOWOPS_PRODUCT_PORT:-4014}"
CONFIG_ROOT="${SHADOWOPS_PRODUCT_CONFIG_ROOT:-${HOME}/.config/shadowops-product-preview}"
OPEN_BROWSER="${SHADOWOPS_OPEN_BROWSER:-1}"

fail() {
  echo "PRODUCT_PREVIEW=FAILED"
  echo "FAIL_REASON=$1"
  exit "${2:-1}"
}

[[ "$PORT" == "4014" ]] || fail "PRODUCT_PREVIEW_REQUIRES_PORT_4014"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "WRONG_BRANCH_$(git branch --show-current)"
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || fail "WORKTREE_NOT_CLEAN"

git fetch origin --prune
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"
[[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"

mkdir -p "$CONFIG_ROOT"
chmod 700 "$CONFIG_ROOT"

# A previous preview may point to another worktree. It is safe to replace only the
# preview service; stable 4013 is never stopped or rewritten here.
if systemctl --user is-active --quiet shadowops-preview.service; then
  EXISTING_WD="$(systemctl --user show shadowops-preview.service -p WorkingDirectory --value 2>/dev/null || true)"
  if [[ "$EXISTING_WD" != "$ROOT" ]]; then
    echo "PREVIOUS_PREVIEW_WORKTREE=${EXISTING_WD:-UNKNOWN}"
    systemctl --user stop shadowops-preview.service
  fi
fi

echo "SHADOWOPS_PRODUCT_PREVIEW"
echo "ROOT=$ROOT"
echo "BRANCH=$BRANCH"
echo "HEAD=$LOCAL_HEAD"
echo "PORT=$PORT"
echo "CONFIG_ROOT=$CONFIG_ROOT"
echo "AI_EXECUTION_POLICY=REMOTE_ONLY"
echo "PORT_4013=UNTOUCHED"

# Do not allow live runtime credentials or DB settings to contaminate the
# acceptance tests executed by configure_local_all.sh. The script creates a
# fresh preview.env under CONFIG_ROOT and systemd loads it only for the preview.
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
  SHADOWOPS_CONFIG_BRANCH="$BRANCH" \
  SHADOWOPS_CONFIG_REMOTE_REF="$REMOTE_REF" \
  SHADOWOPS_PREVIEW_PORT="$PORT" \
  SHADOWOPS_CONFIG_ROOT="$CONFIG_ROOT" \
  SHADOWOPS_OPEN_BROWSER=0 \
  bash scripts/configure_local_all.sh

systemctl --user is-active --quiet shadowops-preview.service || fail "PREVIEW_SERVICE_NOT_ACTIVE"

ENV_FILE="$CONFIG_ROOT/preview.env"
[[ -f "$ENV_FILE" ]] || fail "PREVIEW_ENV_MISSING"
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

HEALTH_HTTP="$(curl -sS -o /tmp/shadowops-product-health.json -w '%{http_code}' \
  -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
  "http://127.0.0.1:${PORT}/health")"
READY_HTTP="$(curl -sS -o /tmp/shadowops-product-ready.json -w '%{http_code}' \
  -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
  "http://127.0.0.1:${PORT}/ready")"
UI_HTTP="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/")"

[[ "$HEALTH_HTTP" == "200" ]] || fail "HEALTH_HTTP_${HEALTH_HTTP}"
[[ "$READY_HTTP" == "200" ]] || fail "READY_HTTP_${READY_HTTP}"
[[ "$UI_HTTP" == "200" ]] || fail "UI_HTTP_${UI_HTTP}"

echo "HEALTH_HTTP=$HEALTH_HTTP"
echo "READY_HTTP=$READY_HTTP"
echo "UI_HTTP=$UI_HTTP"
echo "URL=http://127.0.0.1:${PORT}/"
echo "COMMAND_PALETTE=CTRL_K_OR_SLASH"
echo "FINAL_STATUS=PRODUCT_PREVIEW_PASS"

if command -v xdg-open >/dev/null 2>&1 && [[ "$OPEN_BROWSER" != "0" ]]; then
  xdg-open "http://127.0.0.1:${PORT}/" >/dev/null 2>&1 || true
fi
