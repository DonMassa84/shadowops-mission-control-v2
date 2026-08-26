#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_NOT_A_GIT_WORKTREE" >&2
  exit 64
fi
cd "$ROOT"

BASELINE_FILE="${1:-}"
if [[ -z "$BASELINE_FILE" || ! -f "$BASELINE_FILE" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_BASELINE_MISSING" >&2
  exit 64
fi

BASELINE_HEAD="$(awk -F= '$1 == "HEAD" {print $2}' "$BASELINE_FILE")"
BASELINE_BRANCH="$(awk -F= '$1 == "BRANCH" {print $2}' "$BASELINE_FILE")"
if [[ ! "$BASELINE_HEAD" =~ ^[0-9a-f]{40}$ || -z "$BASELINE_BRANCH" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_BASELINE_INVALID" >&2
  exit 64
fi

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "local/all-developments" || "$BRANCH" != "$BASELINE_BRANCH" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_WRONG_BRANCH" >&2
  echo "BASELINE_BRANCH=$BASELINE_BRANCH" >&2
  echo "BRANCH=$BRANCH" >&2
  exit 65
fi

if git diff --name-only --diff-filter=U | grep -q .; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_UNRESOLVED_CONFLICTS" >&2
  exit 66
fi

if ! git merge-base --is-ancestor "$BASELINE_HEAD" HEAD; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_HISTORY_REWRITE_OR_BRANCH_DRIFT" >&2
  echo "BASELINE_HEAD=$BASELINE_HEAD" >&2
  echo "HEAD=$(git rev-parse HEAD)" >&2
  exit 68
fi

# Include both committed changes since the post-preflight baseline and current worktree changes.
mapfile -t CHANGED < <(
  {
    git diff --name-only "$BASELINE_HEAD"..HEAD
    git status --porcelain=v1 --untracked-files=all | sed -E 's/^.. //' | sed -E 's/^"(.*)"$/\1/'
  } | sed '/^$/d' | sort -u
)

allowed_path() {
  local path="$1"
  case "$path" in
    apps/shadowops_core/lib/shadow_ops_core/approval.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/approval_store.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/governance_gate.ex) return 0 ;;
    apps/shadowops_core/lib/shadow_ops_core/audit.ex) return 0 ;;
    apps/shadowops_core/test/durable_governance_test.exs) return 0 ;;
    apps/shadowops_core/test/*approval*_test.exs) return 0 ;;
    *) return 1 ;;
  esac
}

UNEXPECTED=()
for path in "${CHANGED[@]:-}"; do
  [[ -n "$path" ]] || continue
  if [[ "$path" == "mix.lock" ]]; then
    UNEXPECTED+=("$path")
    continue
  fi
  if ! allowed_path "$path"; then
    UNEXPECTED+=("$path")
  fi
done

if (( ${#UNEXPECTED[@]} > 0 )); then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_UNEXPECTED_PATHS" >&2
  printf 'UNEXPECTED_PATH=%s\n' "${UNEXPECTED[@]}" >&2
  echo "Do not delete or reset automatically. Inspect and recover only the unexpected agent-created paths." >&2
  exit 67
fi

git diff --check

echo "OPENCODE_POSTFLIGHT=PASS"
echo "BASELINE_HEAD=$BASELINE_HEAD"
echo "HEAD=$(git rev-parse HEAD)"
echo "BRANCH=$BRANCH"
echo "CHANGED_COUNT=${#CHANGED[@]}"
for path in "${CHANGED[@]:-}"; do
  [[ -n "$path" ]] && echo "CHANGED_PATH=$path"
done
