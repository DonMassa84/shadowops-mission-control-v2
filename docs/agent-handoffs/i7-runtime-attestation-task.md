# i7 Runtime Attestation Worker Task

STATUS=ASSIGNED
WORKER=i7 Runtime Attestation Worker
WORK_BRANCH=ai/i7-runtime-attestation-worker
BASE_SHA=2872cfcb5fac8fa0f470fd80ea79e5eff1055fbe
TARGET_NODE=i7
TARGET_ROLE=qa_supplementary_compute
TARGET_BASE=local/all-developments

## Mission

Bring the i7 node to the same evidence-backed routing standard as Kali without broadening production control.

The worker must prove real runtime reachability and current capabilities for QA/repository/supplementary-compute routing. Declared metadata alone is not sufficient.

## Required implementation / verification

1. Inspect the current i7 runtime source and node projection on BASE_SHA.
2. Add or harden an i7 node adapter only if current runtime evidence is not already represented truthfully.
3. Evidence must be current, real, non-synthetic and bounded. Unknown/unreachable/stale evidence must never become READY.
4. Prove these capabilities independently on the real i7 node where applicable:
   - qa
   - repository_change
   - supplementary_compute
5. Verify `ShadowOpsCore.NodeCapabilityRouter` selects:
   - QA -> i7 when the i7 has verified `qa` evidence.
   - repository_change -> i7 when verified.
   - supplementary_compute -> i7 when verified.
   - fallback only to another node with the same independently verified capability.
   - no verified executor -> fail closed with `:no_verified_executor` or equivalent.
6. Preserve security routing to Kali and AI/GPU routing to Ryzen.
7. No arbitrary shell routing, no arbitrary systemd control, no production control plane.
8. Add deterministic regression tests for READY/ONLINE, unreachable, synthetic, stale/unverified and fallback cases.
9. Capture runtime evidence without committing credentials, SSH keys, tokens or machine secrets.
10. Persist final handoff and exact HEAD/test evidence in GitHub.

## Runtime acceptance gates

```text
I7_SETUP=PASS
I7_REACHABLE=PASS
I7_REAL_DATA=PASS
I7_SYNTHETIC=FALSE
I7_QA_CAPABILITY=PASS
I7_REPOSITORY_CHANGE=PASS
I7_SUPPLEMENTARY_COMPUTE=PASS
I7_NO_FAKE_READY=PASS
QA_COMPUTE_TO_I7=PASS
REPOSITORY_CHANGE_TO_I7=PASS
SUPPLEMENTARY_COMPUTE_TO_I7=PASS
NO_VERIFIED_EXECUTOR_FAIL_CLOSED=PASS
SECURITY_TO_KALI_UNCHANGED=PASS
AI_GPU_TO_RYZEN_UNCHANGED=PASS
ARBITRARY_EXECUTION=BLOCKED
ARBITRARY_SYSTEMD=BLOCKED
4013_MUTATION=NO
4014_MUTATION=NO
```

## Repository quality gates

```text
FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0
FULL_TEST_RC=0
CREDO_CHANGED_RC=0
DIFF_CHECK_RC=0
REMOTE_HEAD_MATCH=YES
READY_FOR_INTEGRATION=YES
```

If the full hardening workflow runs on the worker branch, report its exact run ID and result. Do not weaken or bypass any blocking gate.

## Governance

- Fail closed.
- Do not invent i7 capability evidence.
- Evidence cannot lower risk.
- No credentials or secrets in repo/evidence.
- No destructive git operations.
- NO_FORCE_PUSH.
- NO_MERGE.
- NO_DEPLOY.
- NO_MAIN_WRITE.
- NO_4013_MUTATION.
- NO_4014_MUTATION.
- Worker may commit/push only to `ai/i7-runtime-attestation-worker`.

## Final handoff

Return exactly:

```text
I7_WORKER_STATUS=PASS|FAIL|BLOCKED
TESTED_HEAD=
REMOTE_HEAD=
REMOTE_HEAD_MATCH=YES|NO
I7_SETUP=PASS|FAIL
I7_REACHABLE=PASS|FAIL
I7_REAL_DATA=PASS|FAIL
I7_QA_CAPABILITY=PASS|FAIL
I7_REPOSITORY_CHANGE=PASS|FAIL
I7_SUPPLEMENTARY_COMPUTE=PASS|FAIL
I7_NO_FAKE_READY=PASS|FAIL
QA_COMPUTE_TO_I7=PASS|FAIL
REPOSITORY_CHANGE_TO_I7=PASS|FAIL
SUPPLEMENTARY_COMPUTE_TO_I7=PASS|FAIL
NO_VERIFIED_EXECUTOR_FAIL_CLOSED=PASS|FAIL
SECURITY_TO_KALI_UNCHANGED=PASS|FAIL
AI_GPU_TO_RYZEN_UNCHANGED=PASS|FAIL
FORMAT_RC=
COMPILE_RC=
TARGET_TEST_RC=
FULL_TEST_RC=
CREDO_CHANGED_RC=
DIFF_CHECK_RC=
CRITICAL_BLOCKERS=
READY_FOR_INTEGRATION=YES|NO
4013_MUTATION=NO
4014_MUTATION=NO
NO_MERGE
NO_DEPLOY
```
