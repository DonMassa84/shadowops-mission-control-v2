# Nemo 4015 UI Acceptance Checkpoint — 2026-08-28

SOURCE=NEMO
PHASE=RECOVERY_BASELINE -> UI_ACCEPTANCE -> LOCAL_COMPLETE
REPORTED_LOCAL_BRANCH=local/all-developments
REPORTED_LOCAL_HEAD=a466e77
REMOTE_COMMIT_VERIFIED=NO
REMOTE_WORKER_BRANCH=ai/4015-ui-acceptance
REMOTE_WORKER_BRANCH_EXISTS=NO

## Reported work completed

- Fixed 4015 root `/` timeout/performance issue.
- Root latency reported improved from ~13.7s to ~3.5s.
- `/api/knowledge` reported improved from ~21.2s to ~2.6s.
- `/api/services` reported improved from ~2.8s to ~1.6s.
- Root cause reported as `PRAGMA quick_check` against the ChromaDB store adding ~11.7s per request; probe replaced by collection-record validity check.
- `/workflows`, `/runs`, `/jobs`, `/approvals` reported HTTP 200.
- Navigation reported 17/17 canonical routes operational.
- RUNNABLE vs REFERENCE_ONLY UI reported enforced.
- Run buttons reported only for executable canonical workflows and disabled without write token.
- Approval-required UI reported for L2 flows.
- UI/LiveView test suite reported 106 tests passing.
- Acceptance evidence reported in `docs/ai/4015-ui-acceptance.md`.

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
GET / -> 200 (~3.5s)
GET /api/* -> reported all 16 probes below timeout

## Critical persistence correction

The worker report claimed both `Commit + Push=YES` and `ready for push`, while reporting work on `local/all-developments`.

Live GitHub verification immediately after the report found:

- commit `a466e77` was not discoverable in the repository;
- branch `ai/4015-ui-acceptance` did not exist remotely.

Therefore the correct classification is:

```text
NEMO_LOCAL_ACCEPTANCE=PASS_REPORTED
NEMO_GITHUB_PERSISTENCE=FAIL
NEMO_4015_GREEN=NO
```

The work must be preserved losslessly before any further task:

1. Create/push `recovery/nemo-a466e77` pointing at the exact local commit.
2. Fetch current `origin/local/all-developments`.
3. Create `ai/4015-ui-acceptance` from the current remote base, not from a stale local branch.
4. Cherry-pick/reconcile only the Nemo-owned UI/performance/evidence commit(s), preserving scope.
5. Re-run FORMAT/COMPILE/TARGET/FULL and 4015 runtime acceptance on the exact worker-branch candidate.
6. Push `ai/4015-ui-acceptance` and verify `LOCAL_HEAD=REMOTE_HEAD`.
7. Publish heartbeat/handoff with exact `PUSHED_SHA`.

## Scope guard

Nemo must NOT continue into P0 approval/governance-core work. `ApprovalStore`, atomic single-use approval consumption, `RiskPolicy`, `CapabilityRegistry` semantics, and workflow promotion belong to the governance/integration owners. Nemo remains 4015 UI/acceptance only.

NO_MERGE
NO_DEPLOY
NO_4013_MUTATION
NO_FORCE_PUSH
