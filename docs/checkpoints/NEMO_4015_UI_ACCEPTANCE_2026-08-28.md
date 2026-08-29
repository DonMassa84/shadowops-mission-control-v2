# Nemo 4015 UI Acceptance Checkpoint — 2026-08-28

SOURCE=NEMO
PHASE=RECOVERY_BASELINE -> UI_ACCEPTANCE -> REMOTE_PERSISTED_ON_BASE
REPORTED_LOCAL_BRANCH=local/all-developments
REPORTED_LOCAL_HEAD=a466e77
REMOTE_COMMIT_VERIFIED=YES
REMOTE_COMMIT=a466e774e7cb8a08bae947d21dc439bc57d2a211
REMOTE_BASE_BRANCH=local/all-developments
REMOTE_WORKER_BRANCH=ai/4015-ui-acceptance
REMOTE_WORKER_BRANCH_EXISTS=NO

## Work completed

- Fixed 4015 root `/` timeout/performance issue.
- Root latency reported improved from ~13.7s to ~3.0-3.5s.
- `/api/knowledge` reported improved from ~21.2s to ~2.0-2.6s.
- `/api/services` reported improved from ~2.8s to ~1.4-1.6s.
- Root cause: `PRAGMA quick_check` against the ChromaDB store added ~11.7s per request; the committed fix removes that request-time integrity check and uses the collection record/query probe for runtime validity.
- `/workflows`, `/runs`, `/jobs`, `/approvals` reported HTTP 200.
- Navigation reported 17/17 canonical routes operational.
- RUNNABLE vs REFERENCE_ONLY UI reported enforced.
- Run buttons reported only for executable canonical workflows and disabled without write token.
- Approval-required UI reported for L2 flows.
- UI/LiveView suite reported 106 tests passing.
- Acceptance evidence is committed in `docs/ai/4015-ui-acceptance.md`.

## GitHub verification

Commit `a466e774e7cb8a08bae947d21dc439bc57d2a211` is now verifiably present on GitHub with parent `b4eed982b8e5bf519722f560227da68cdf06fbc8` and two changed files:

- `apps/shadowops_core/lib/shadow_ops_core/operational_sources.ex`
- `docs/ai/4015-ui-acceptance.md`

The commit was pushed directly to `local/all-developments` by explicit operator action. Therefore Nemo's work is no longer local-only, but it did not follow the intended worker-branch isolation contract.

Correct classification:

```text
NEMO_LOCAL_ACCEPTANCE=PASS_REPORTED
NEMO_GITHUB_PERSISTENCE=PASS
NEMO_BASE_PUSH=YES
NEMO_WORKER_BRANCH_ISOLATION=FAIL
NEMO_4015_ACCEPTANCE_EVIDENCE=REMOTE
```

Because `local/all-developments` advanced from `b4eed98` to `a466e77`, all worker/integration comparisons must now account for the new base commit before consolidation. Do not discard or rewrite this commit.

## Reported gates

FORMAT=PASS
COMPILE=PASS
TESTS=PASS (106)
MISSION_ROUTES=PASS (17/17)
PRIVACY_GATE=PASS
WRITE_BYPASS=BLOCKED
SECRET_LEAK_SCAN=PASS
VISUAL_ACCEPTANCE=PASS
CREDO=PASS
DIALYZER=DEGRADED (reported pre-existing)
SOBELOW=DEGRADED (reported pre-existing)
REGISTRY=PASS
WORKFLOW_IDS=PASS
HEX_AUDIT=PASS
DIFF_CHECK=PASS

## Reported 4015 runtime

GET /health -> 200
GET /ready -> 200
GET / -> 200 (~3.0-3.5s)
GET /api/* -> reported all canonical probes successful

## Next integration handling

1. Treat `a466e77` as the new immutable `local/all-developments` base checkpoint.
2. Do not ask Nemo to re-push the same commit to base or rewrite history.
3. Before integrating PR #24/#25/#26, compare each worker branch against the new base and resolve only real semantic conflicts.
4. If Nemo continues with new UI work, create/use `ai/4015-ui-acceptance` from the current remote base and keep future commits isolated there.
5. Re-run exact integrated-candidate FORMAT/COMPILE/FULL and 4015 acceptance after governance/workflow branches are consolidated.

## Scope guard

Nemo must NOT continue into P0 approval/governance-core work. `ApprovalStore`, atomic single-use approval consumption, `RiskPolicy`, `CapabilityRegistry` semantics, and workflow promotion belong to the governance/integration owners. Nemo remains 4015 UI/acceptance only.

NO_DEPLOY
NO_4013_MUTATION
NO_FORCE_PUSH
