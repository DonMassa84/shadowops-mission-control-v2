# Blockers

## P0
0

## P1
0

## P2
1. **mix format --check-formatted** fails on `apps/shadowops_core/lib/shadow_ops_core/adapters/tcc_adapter.ex:142`
   - EXPECTED: `mix format` passes
   - ACTUAL: `mix format failed due to --check-formatted` diff shows unformatted long line `id = if String.starts_with?(raw_id || "", "so:wf:v1:"), do: raw_id, else: "so:wf:v1:" <> to_string(raw_id)`
   - REPRODUCTION: `MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix format --check-formatted` (also `gh run 33193759820 --log-failed`)
   - SEVERITY: P2 (formatting, no security, no prod behavior change)
   - SUGGESTED_FIX: `mix format` (auto-fix splits line into 4 lines as shown in CI diff)
   - CI_CLASSIFICATION: TEST_BUG

## P3
0

## Summary
No P0/P1 security blockers. Product verified_app is **fail-closed** for all adversarial cases (unknown, L2, blocked, injection, tamper). CI is red **only** on formatting gate, not product logic.

