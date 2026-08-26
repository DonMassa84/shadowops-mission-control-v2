#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="${SHADOWOPS_CONFIG_BRANCH:-automation/opencode-work}"
REMOTE_REF="${SHADOWOPS_CONFIG_REMOTE_REF:-origin/${TARGET_BRANCH}}"
PORT="${SHADOWOPS_PREVIEW_PORT:-4014}"
STATE_ROOT="${SHADOWOPS_STATE_ROOT:-${HOME}/.local/state/shadowops}"
CONFIG_ROOT="${SHADOWOPS_CONFIG_ROOT:-${HOME}/.config/shadowops}"
DOMAIN_DIR="${SHADOWOPS_DOMAIN_DIR:-${HOME}/.local/share/shadowops/domains}"
PROJECT_CATALOG="${SHADOWOPS_PROJECT_CATALOG:-${STATE_ROOT}/project_catalog.json}"
SNAPSHOT_ROOT="${STATE_ROOT}/snapshots"
RUNTIME_STATE="${STATE_ROOT}/runtime-preview"
ENV_FILE="${CONFIG_ROOT}/preview.env"
DB_ENV_FILE="${CONFIG_ROOT}/database.env"
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_NAME="shadowops-preview.service"
UNIT_FILE="${UNIT_DIR}/${UNIT_NAME}"
RELEASE_BIN="${ROOT}/_build/prod/rel/shadowops/bin/shadowops"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SNAPSHOT_DIR="${SNAPSHOT_ROOT}/${STAMP}"

FINAL_EMITTED=0
FAIL_REASON=""

emit_final() {
  local final_status="$1"
  FINAL_EMITTED=1
  echo
  echo "SHADOWOPS_LOCAL_ALL_CONFIG"
  echo "ROOT=$ROOT"
  echo "BRANCH=$(git branch --show-current 2>/dev/null || true)"
  echo "HEAD=$(git rev-parse HEAD 2>/dev/null || true)"
  echo "REMOTE_HEAD=$(git rev-parse "$REMOTE_REF" 2>/dev/null || true)"
  echo "SNAPSHOT_DIR=$SNAPSHOT_DIR"
  echo "ENV_FILE=$ENV_FILE"
  echo "DOMAIN_DIR=$DOMAIN_DIR"
  echo "PROJECT_CATALOG=$PROJECT_CATALOG"
  echo "UNIT=$UNIT_NAME"
  echo "PREVIEW_URL=http://127.0.0.1:${PORT}/"
  echo "FAIL_REASON=${FAIL_REASON:-NONE}"
  echo "FINAL_STATUS=$final_status"
}

on_exit() {
  local rc=$?
  if [[ "$FINAL_EMITTED" != "1" && "$rc" != "0" ]]; then
    emit_final "LOCAL_ALL_CONFIG_FAILED"
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
  printf 'PASS %-36s\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "MISSING_COMMAND_$1"
}

critical_untracked_files() {
  git ls-files --others --exclude-standard -- apps config test .github scripts 2>/dev/null || true
}

write_env_line() {
  local key="$1"
  local value="$2"
  [[ "$value" != *$'\n'* ]] || fail "ENV_VALUE_CONTAINS_NEWLINE_${key}"
  printf '%s=%s\n' "$key" "$value"
}

for cmd in git mix elixir erl openssl curl ss systemctl sha256sum; do
  require_cmd "$cmd"
done

case "$PORT" in
  ''|*[!0-9]*) fail "PREVIEW_PORT_NOT_NUMERIC" ;;
esac
(( PORT >= 1024 && PORT <= 65535 )) || fail "PREVIEW_PORT_OUT_OF_RANGE"

mkdir -p "$STATE_ROOT" "$CONFIG_ROOT" "$DOMAIN_DIR" "$SNAPSHOT_ROOT" "$RUNTIME_STATE" "$UNIT_DIR"
chmod 700 "$STATE_ROOT" "$CONFIG_ROOT" "$DOMAIN_DIR" "$SNAPSHOT_ROOT" "$RUNTIME_STATE" 2>/dev/null || true
umask 077

echo "=== SOURCE PARITY ==="
git fetch origin --prune
CURRENT_BRANCH="$(git branch --show-current)"
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE_REF")"
echo "CURRENT_BRANCH=$CURRENT_BRANCH"
echo "LOCAL_HEAD=$LOCAL_HEAD"
echo "REMOTE_HEAD=$REMOTE_HEAD"
[[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]] || fail "WRONG_BRANCH"
[[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]] || fail "LOCAL_HEAD_DIFFERS_FROM_REMOTE"
git diff --quiet "$REMOTE_REF" -- . || fail "TRACKED_WORKTREE_DIFFERS_FROM_REMOTE"
git diff --cached --quiet || fail "STAGED_CHANGES_PRESENT"
UNTRACKED_SOURCE="$(critical_untracked_files)"
if [[ -n "$UNTRACKED_SOURCE" ]]; then
  printf '%s\n' "$UNTRACKED_SOURCE" >&2
  fail "UNTRACKED_SOURCE_FILES_PRESENT"
fi
pass "source_parity"

echo
echo "=== SNAPSHOT ==="
mkdir -p "$SNAPSHOT_DIR"
git rev-parse HEAD > "$SNAPSHOT_DIR/HEAD.txt"
git branch --show-current > "$SNAPSHOT_DIR/BRANCH.txt"
git status --short --branch > "$SNAPSHOT_DIR/GIT_STATUS.txt"
git log -30 --oneline --decorate > "$SNAPSHOT_DIR/GIT_LOG.txt"
git bundle create "$SNAPSHOT_DIR/shadowops-local.bundle" HEAD
sha256sum "$SNAPSHOT_DIR/shadowops-local.bundle" > "$SNAPSHOT_DIR/SHA256SUMS.txt"
chmod -R go-rwx "$SNAPSHOT_DIR" 2>/dev/null || true
pass "snapshot"

echo
echo "=== LOCAL PRIVATE CONFIGURATION ==="
if [[ -f "$ENV_FILE" ]]; then
  chmod 600 "$ENV_FILE"
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
fi

SECRET_KEY_BASE="${SHADOWOPS_SECRET_KEY_BASE:-$(openssl rand -hex 64)}"
READ_TOKEN="${SHADOWOPS_READ_TOKEN:-$(openssl rand -hex 32)}"
WRITE_TOKEN="${SHADOWOPS_WRITE_TOKEN:-$(openssl rand -hex 32)}"
RELEASE_COOKIE_VALUE="${RELEASE_COOKIE:-$(openssl rand -hex 32)}"

[[ ${#SECRET_KEY_BASE} -ge 64 ]] || fail "SECRET_KEY_BASE_TOO_SHORT"
[[ ${#READ_TOKEN} -ge 32 ]] || fail "READ_TOKEN_TOO_SHORT"
[[ ${#WRITE_TOKEN} -ge 32 ]] || fail "WRITE_TOKEN_TOO_SHORT"

PERSISTENCE=false
DB_STATUS="NOT_CONFIGURED"
DB_LINES=""
if [[ -f "$DB_ENV_FILE" ]]; then
  chmod 600 "$DB_ENV_FILE"
  # shellcheck disable=SC1090
  set -a
  source "$DB_ENV_FILE"
  set +a

  if [[ -n "${SHADOWOPS_DB_PASSWORD:-}" && ${#SHADOWOPS_DB_PASSWORD} -ge 16 && \
        -n "${SHADOWOPS_DB_USER:-}" && -n "${SHADOWOPS_DB_NAME:-}" ]]; then
    SHADOWOPS_DB_HOST="${SHADOWOPS_DB_HOST:-localhost}"
    SHADOWOPS_DB_POOL_SIZE="${SHADOWOPS_DB_POOL_SIZE:-10}"
    PERSISTENCE=true
    DB_STATUS="CONFIGURED"
    DB_LINES="1"
  else
    fail "DATABASE_ENV_INCOMPLETE"
  fi
fi

TMP_ENV="${ENV_FILE}.tmp.$$"
{
  write_env_line PORT "$PORT"
  write_env_line SHADOWOPS_PUBLIC_HOST "localhost"
  write_env_line SHADOWOPS_START_PERSISTENCE "$PERSISTENCE"
  write_env_line SHADOWOPS_SECRET_KEY_BASE "$SECRET_KEY_BASE"
  write_env_line SHADOWOPS_READ_TOKEN "$READ_TOKEN"
  write_env_line SHADOWOPS_WRITE_TOKEN "$WRITE_TOKEN"
  write_env_line SHADOWOPS_STATE_DIR "$RUNTIME_STATE"
  write_env_line SHADOWOPS_DOMAIN_DIR "$DOMAIN_DIR"
  write_env_line SHADOWOPS_PROJECT_CATALOG "$PROJECT_CATALOG"
  write_env_line RELEASE_NODE "shadowops_preview"
  write_env_line RELEASE_COOKIE "$RELEASE_COOKIE_VALUE"
  if [[ "$DB_LINES" == "1" ]]; then
    write_env_line SHADOWOPS_DB_HOST "$SHADOWOPS_DB_HOST"
    write_env_line SHADOWOPS_DB_USER "$SHADOWOPS_DB_USER"
    write_env_line SHADOWOPS_DB_PASSWORD "$SHADOWOPS_DB_PASSWORD"
    write_env_line SHADOWOPS_DB_NAME "$SHADOWOPS_DB_NAME"
    write_env_line SHADOWOPS_DB_POOL_SIZE "$SHADOWOPS_DB_POOL_SIZE"
  fi
} > "$TMP_ENV"
mv "$TMP_ENV" "$ENV_FILE"
chmod 600 "$ENV_FILE"
pass "private_runtime_env"

echo "DATABASE=$DB_STATUS"
echo "DOMAIN_MANIFESTS=$(find "$DOMAIN_DIR" -maxdepth 1 -type f -name '*.json' -printf '.' 2>/dev/null | wc -c)"
if [[ -f "$PROJECT_CATALOG" ]]; then
  echo "PROJECT_CATALOG_STATUS=PRESENT"
else
  echo "PROJECT_CATALOG_STATUS=NOT_CONFIGURED"
fi

echo
echo "=== OPTIONAL LOCAL RUNTIMES ==="
if command -v opencode >/dev/null 2>&1; then
  echo "OPENCODE=AVAILABLE"
else
  echo "OPENCODE=NOT_CONFIGURED"
fi
if command -v ollama >/dev/null 2>&1; then
  if curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "OLLAMA=AVAILABLE"
  else
    echo "OLLAMA=INSTALLED_NOT_REACHABLE"
  fi
else
  echo "OLLAMA=NOT_CONFIGURED"
fi
if [[ -n "${SHADOWOPS_I7_HOST:-}" ]]; then
  if command -v ping >/dev/null 2>&1 && ping -c 1 -W 1 "$SHADOWOPS_I7_HOST" >/dev/null 2>&1; then
    echo "I7_NODE=REACHABLE"
  else
    echo "I7_NODE=OPTIONAL_UNAVAILABLE"
  fi
else
  echo "I7_NODE=NOT_CONFIGURED_OPTIONAL"
fi

echo
echo "=== QUALITY GATE ==="
export SHADOWOPS_START_PERSISTENCE=false
mix deps.get
git diff --exit-code -- mix.lock
mix archive.install hex sobelow 0.15.0 --force
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test --seed 12345
mix shadowops.registry validate
mix shadowops.workflow_ids.validate
mix hex.audit
git diff --check
SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG" MIX_ENV=test mix shadowops.projects.seed
export SHADOWOPS_PROJECT_CATALOG="$PROJECT_CATALOG"
SHADOWOPS_RUNTIME_REQUIRED=0 bash scripts/production_acceptance.sh
pass "quality_gate"

echo
echo "=== PRODUCTION RELEASE ==="
MIX_ENV=prod mix release shadowops --overwrite
[[ -x "$RELEASE_BIN" ]] || fail "PRODUCTION_RELEASE_MISSING"
pass "production_release"

echo
echo "=== PREVIEW SYSTEMD UNIT ==="
if ss -ltn | grep -Eq "[:.]4013[[:space:]]"; then
  echo "PORT_4013=IN_USE_UNTOUCHED"
else
  echo "PORT_4013=FREE_UNTOUCHED"
fi

if systemctl --user is-active --quiet "$UNIT_NAME"; then
  EXISTING_WD="$(systemctl --user show "$UNIT_NAME" -p WorkingDirectory --value 2>/dev/null || true)"
  [[ "$EXISTING_WD" == "$ROOT" ]] || fail "EXISTING_PREVIEW_UNIT_POINTS_ELSEWHERE"
  systemctl --user stop "$UNIT_NAME"
fi

if ss -ltn | grep -Eq "[:.]${PORT}[[:space:]]"; then
  fail "PREVIEW_PORT_ALREADY_IN_USE"
fi

cat > "$UNIT_FILE" <<EOF
[Unit]
Description=ShadowOps Mission Control local preview
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
EnvironmentFile=$ENV_FILE
ExecStart=$RELEASE_BIN start
ExecStop=$RELEASE_BIN stop
Restart=on-failure
RestartSec=3
TimeoutStartSec=60
TimeoutStopSec=20
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=default.target
EOF
chmod 600 "$UNIT_FILE"
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"
pass "preview_systemd_unit"

echo
echo "=== AUTHENTICATED RUNTIME CHECK ==="
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

READY=0
for _ in $(seq 1 45); do
  if curl -fsS --max-time 2 \
    -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
    "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
[[ "$READY" == "1" ]] || {
  systemctl --user status "$UNIT_NAME" --no-pager || true
  journalctl --user -u "$UNIT_NAME" -n 80 --no-pager || true
  fail "PREVIEW_NOT_HEALTHY"
}

HEALTH_HTTP="$(curl -sS -o /tmp/shadowops-config-health.json -w '%{http_code}' \
  -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
  "http://127.0.0.1:${PORT}/health")"
READY_HTTP="$(curl -sS -o /tmp/shadowops-config-ready.json -w '%{http_code}' \
  -H "Authorization: Bearer ${SHADOWOPS_READ_TOKEN}" \
  "http://127.0.0.1:${PORT}/ready")"
[[ "$HEALTH_HTTP" == "200" ]] || fail "HEALTH_HTTP_${HEALTH_HTTP}"
[[ "$READY_HTTP" == "200" ]] || fail "READY_HTTP_${READY_HTTP}"
echo "HEALTH_HTTP=$HEALTH_HTTP"
echo "READY_HTTP=$READY_HTTP"
pass "authenticated_health_ready"

echo
echo "=== UI ROUTES ==="
UI_FAIL=0
for route in / /workflows /workflows/repository_quality /services /runs /layers /nodes /projects /projects/federated /projects/chatgpt /security /approvals /audit /evidence /logs; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}${route}")"
  printf '%-36s %s\n' "$route" "$code"
  [[ "$code" == "200" ]] || UI_FAIL=1
done
[[ "$UI_FAIL" == "0" ]] || fail "UI_ROUTE_FAILURE"
pass "ui_routes"

echo
echo "=== FINAL SOURCE INTEGRITY ==="
git diff --quiet "$REMOTE_REF" -- . || fail "SOURCE_CHANGED_DURING_CONFIGURATION"
git diff --cached --quiet || fail "STAGED_CHANGES_CREATED"
[[ -z "$(critical_untracked_files)" ]] || fail "UNTRACKED_SOURCE_CREATED"
pass "source_integrity"

echo
echo "TOKENS_EXPOSED=NO"
echo "PORT_4013=UNTOUCHED"
echo "PREVIEW_SERVICE=$UNIT_NAME"
echo "PREVIEW_PORT=$PORT"
echo "BROWSER_URL=http://127.0.0.1:${PORT}/"
echo "STOP_COMMAND=systemctl --user stop $UNIT_NAME"
echo "START_COMMAND=systemctl --user start $UNIT_NAME"
echo "STATUS_COMMAND=systemctl --user status $UNIT_NAME --no-pager"
echo "LOG_COMMAND=journalctl --user -u $UNIT_NAME -n 100 --no-pager"

if command -v xdg-open >/dev/null 2>&1 && [[ "${SHADOWOPS_OPEN_BROWSER:-1}" != "0" ]]; then
  xdg-open "http://127.0.0.1:${PORT}/" >/dev/null 2>&1 || true
fi

FAIL_REASON=""
emit_final "LOCAL_ALL_CONFIG_PASS"
