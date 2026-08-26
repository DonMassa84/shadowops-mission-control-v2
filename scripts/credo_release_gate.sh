#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Immutable pre-finish baseline for release/product-finish-2026-08-26.
DEFAULT_BASE_REF="b521fafa1e8e5ad5a55edf8b5107edfe75ddfaa4"
BASE_REF="${SHADOWOPS_CREDO_BASE_REF:-$DEFAULT_BASE_REF}"

if [[ -z "$BASE_REF" || "$BASE_REF" == -* ]]; then
  echo "Invalid SHADOWOPS_CREDO_BASE_REF: $BASE_REF" >&2
  exit 2
fi

if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
  echo "Credo release baseline is unavailable: $BASE_REF" >&2
  echo "Fetch the repository history or set SHADOWOPS_CREDO_BASE_REF to an available audited baseline." >&2
  exit 2
fi

mapfile -t changed < <(
  git diff --name-only --diff-filter=ACMR "$BASE_REF" HEAD -- '*.ex' '*.exs' |
    grep -E '^(apps|config|test)/' || true
)

if ((${#changed[@]} == 0)); then
  echo "CREDO_RELEASE_DELTA=PASS_NO_ELIXIR_CHANGES"
  exit 0
fi

printf 'Credo strict release delta from %s:\n' "$BASE_REF"
printf '  %s\n' "${changed[@]}"
mix credo --strict "${changed[@]}"
echo "CREDO_RELEASE_DELTA=PASS"
