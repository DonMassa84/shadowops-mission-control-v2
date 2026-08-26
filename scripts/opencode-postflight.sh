#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_NOT_A_GIT_WORKTREE" >&2
  exit 64
fi
cd "$ROOT"

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "local/all-developments" ]]; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_WRONG_BRANCH" >&2
  echo "BRANCH=$BRANCH" >&2
  exit 65
fi

if git diff --name-only --diff-filter=U | grep -q .; then
  echo "OPENCODE_POSTFLIGHT=BLOCKED_UNRESOLVED_CONFLICTS" >&2
  exit 66
fi

mapfile -t CHANGED < <(git status --porcelain=v1 | sed -E 's/^.. //' | sed -E 's/^"(.*)"$/\1/' | sort -u)

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
echo "BRANCH=$BRANCH"
echo "CHANGED_COUNT=${#CHANGED[@]}"
for path in "${CHANGED[@]:-}"; do
  [[ -n "$path" ]] && echo "CHANGED_PATH=$path"
done
