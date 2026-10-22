#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${SHADOWOPS_REPO_ROOT:-$HOME/Projects/shadowops-mission-control-v2}"
DEV_WORKTREE="${SHADOWOPS_DEV_WORKTREE:-$HOME/Projects/shadowops-mission-control-v2-dev}"
DEV_BRANCH="${SHADOWOPS_DEV_BRANCH:-automation/opencode-work}"
DEV_STATE="${SHADOWOPS_DEV_STATE_DIR:-$HOME/.local/state/shadowops-dev}"
DEV_CONFIG_DIR="${SHADOWOPS_DEV_CONFIG_DIR:-$HOME/.config/shadowops}"
DEV_ENV="$DEV_CONFIG_DIR/dev.env"
STABLE_PORT="${SHADOWOPS_STABLE_PORT:-4013}"
DEV_PORT="${SHADOWOPS_DEV_PORT:-4014}"

fail() { printf 'SETUP_STATUS=FAIL\nERROR=%s\n' "$1" >&2; exit 1; }

[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || fail "REPO_NOT_FOUND:$REPO_ROOT"
cd "$REPO_ROOT"

echo "=== STABLE OBSERVATION (NO MUTATION) ==="
echo "STABLE_PORT=$STABLE_PORT"
if ss -ltn 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${STABLE_PORT}[[:space:]]"; then
  echo "STABLE_LISTENER=PRESENT"
else
  echo "STABLE_LISTENER=ABSENT"
fi

if systemctl --user status shadowops-phoenix.service >/dev/null 2>&1; then
  pid="$(systemctl --user show shadowops-phoenix.service -p MainPID --value)"
  cwd=""
  if [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" != "0" ]] && [[ -e "/proc/$pid/cwd" ]]; then
    cwd="$(readlink -f "/proc/$pid/cwd")"
  fi
  echo "STABLE_SERVICE=ACTIVE_OR_KNOWN"
  echo "STABLE_PID=$pid"
  echo "STABLE_CWD=$cwd"
else
  echo "STABLE_SERVICE=NOT_ACTIVE_OR_NOT_FOUND"
fi

echo
echo "=== DEVELOPMENT WORKTREE ==="
git fetch origin

if ! git show-ref --verify --quiet "refs/heads/$DEV_BRANCH"; then
  if git show-ref --verify --quiet "refs/remotes/origin/$DEV_BRANCH"; then
    git branch --track "$DEV_BRANCH" "origin/$DEV_BRANCH"
  else
    fail "DEV_BRANCH_NOT_FOUND:$DEV_BRANCH"
  fi
fi

if [[ -e "$DEV_WORKTREE" ]]; then
  current="$(git -C "$DEV_WORKTREE" branch --show-current 2>/dev/null || true)"
  [[ "$current" == "$DEV_BRANCH" ]] || fail "DEV_WORKTREE_EXISTS_ON_WRONG_BRANCH:$current"
else
  git worktree add "$DEV_WORKTREE" "$DEV_BRANCH"
fi

mkdir -p "$DEV_STATE" "$DEV_CONFIG_DIR"
chmod 700 "$DEV_STATE" "$DEV_CONFIG_DIR"

cat > "$DEV_ENV" <<EOF
PORT=$DEV_PORT
SHADOWOPS_STATE_DIR=$DEV_STATE
MIX_ENV=prod
EOF
chmod 600 "$DEV_ENV"

cat <<EOF
SETUP_STATUS=PASS
STABLE_PORT=$STABLE_PORT
DEV_PORT=$DEV_PORT
DEV_WORKTREE=$DEV_WORKTREE
DEV_BRANCH=$DEV_BRANCH
DEV_STATE=$DEV_STATE
DEV_ENV=$DEV_ENV
RULE=STABLE_WHILE_DEVELOPING
EOF
