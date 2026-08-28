#!/usr/bin/env bash
set -euo pipefail

OUT="evidence/workflow_import"

mkdir -p "$OUT"

echo "=== FORMAT ==="
mix format \
  scripts/workflow_onboarding_phase_b.exs \
  test/scripts/workflow_onboarding_phase_b_contract_test.exs

echo
echo "=== COMPILE ==="
MIX_ENV=test mix compile --warnings-as-errors

echo
echo "=== PROPOSAL ==="

mix run --no-start \
  scripts/workflow_onboarding_phase_b.exs \
  --output "$OUT" |
  tee "$OUT/phase_b_run.txt"

echo
echo "=== PROPOSAL HASH ==="

sha256sum \
  "$OUT/external_workflow_proposal.json" \
  "$OUT/external_workflow_proposal.md" \
  "$OUT/phase_b_run.txt" \
  > "$OUT/SHA256SUMS"

cat "$OUT/SHA256SUMS"

echo
echo "=== CONTRACT TEST ==="

MIX_ENV=test mix test \
  test/scripts/workflow_onboarding_phase_b_contract_test.exs

echo
echo "PHASE_B_RUNNER=PASS"
