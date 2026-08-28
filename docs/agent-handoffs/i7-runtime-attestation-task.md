# i7 Runtime Attestation + Compute Worker Task

STATUS=IMPLEMENTATION_IN_PROGRESS
WORKER=i7 Runtime Attestation Worker
WORK_BRANCH=ai/i7-runtime-attestation-worker
BASE_SHA=2872cfcb5fac8fa0f470fd80ea79e5eff1055fbe
TARGET_NODE=i7
TARGET_ROLE=qa_supplementary_compute
TARGET_BASE=local/all-developments

## Mission

Bring the i7 node to the same evidence-backed routing standard as Kali and **actually use its CPU for bounded ShadowOps QA/compute jobs**.

Required end-to-end path:

`ShadowOps task -> capability routing -> verified i7 -> bounded SSH executor -> CPU work on i7 -> exit code + evidence hash -> ShadowOps`.

Declared metadata alone is not sufficient.

## Implemented on this branch

- `ShadowOpsCore.I7Node`: fixed `shadowserver-i7` SSH target, read-only CPU/Git/Mix/workspace evidence, no fake READY.
- `ShadowOpsCore.I7RemoteExecutor`: fixed remote runner and allow-listed jobs only.
- `ShadowOpsCore.NodeComputeDispatcher`: routes through `NodeCapabilityRouter` and executes only when i7 has verified capability evidence.
- `mix shadowops.i7.compute <job> --sha <sha>`: bounded operator path.
- `scripts/shadowops-i7-executor.sh`: exact-head remote wrapper for `cpu_probe`, `format`, `compile`, `target_test`, `full_test`, `qa_bundle`, `diff_check`.
- Regression tests for i7 evidence, job allowlist, exact-head and no-arbitrary-execution contract.

The executor accepts no caller-selected host, executable path, systemd unit, port or shell fragment. Only a fixed job enum plus validated 40-hex SHA crosses the SSH boundary.

## Real i7 worker actions required now

1. Verify `shadowserver-i7` resolves only to the authorized i7.
2. Ensure the authorized checkout exists at `$HOME/Projects/shadowops-mission-control-v2` or configure `SHADOWOPS_I7_WORKSPACE` locally on i7.
3. Install the versioned wrapper unchanged:

```bash
install -d -m 0755 "$HOME/.local/bin"
install -m 0755 scripts/shadowops-i7-executor.sh "$HOME/.local/bin/shadowops-i7-executor"
```

4. The i7 checkout HEAD must equal the supplied exact SHA. The executor must report `EXACT_HEAD_MISMATCH` rather than fetching/checking out automatically.
5. Run local quality gates on the worker branch.
6. Run real remote CPU jobs through ShadowOps:

```bash
mix shadowops.i7.compute cpu_probe --sha <EXACT_SHA>
mix shadowops.i7.compute target_test --sha <EXACT_SHA>
mix shadowops.i7.compute full_test --sha <EXACT_SHA>
```

7. Persist hostname, CPU count, exit code, duration and output SHA-256 evidence.
8. Prove no verified i7 -> fail closed.
9. Preserve Security -> Kali and AI/GPU -> Ryzen.
10. No credentials/keys/tokens in repository evidence.

## Required runtime gates

```text
I7_SETUP=PASS
I7_REACHABLE=PASS
I7_REAL_DATA=PASS
I7_SYNTHETIC=FALSE
I7_CPU_COUNT=<real>
I7_QA_CAPABILITY=PASS
I7_REPOSITORY_CHANGE=PASS
I7_SUPPLEMENTARY_COMPUTE=PASS
I7_NO_FAKE_READY=PASS
QA_COMPUTE_TO_I7=PASS
REPOSITORY_CHANGE_TO_I7=PASS
SUPPLEMENTARY_COMPUTE_TO_I7=PASS
I7_REMOTE_EXECUTOR=PASS
I7_CPU_PROBE=PASS
I7_TARGET_TEST_REMOTE=PASS
I7_FULL_TEST_REMOTE=PASS
I7_REMOTE_OUTPUT_SHA256=PASS
I7_EXACT_HEAD_ENFORCEMENT=PASS
NO_VERIFIED_EXECUTOR_FAIL_CLOSED=PASS
SECURITY_TO_KALI_UNCHANGED=PASS
AI_GPU_TO_RYZEN_UNCHANGED=PASS
ARBITRARY_EXECUTION=BLOCKED
ARBITRARY_SYSTEMD=BLOCKED
4013_MUTATION=NO
4014_MUTATION=NO
```

## Repository gates

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

## Governance

Fail closed. No invented evidence. No arbitrary remote shell. No destructive git. `NO_FORCE_PUSH`, `NO_MERGE`, `NO_DEPLOY`, `NO_MAIN_WRITE`, `NO_4013_MUTATION`, `NO_4014_MUTATION`. Worker commits/pushes only to `ai/i7-runtime-attestation-worker`.

## Final handoff

```text
I7_WORKER_STATUS=PASS|FAIL|BLOCKED
TESTED_HEAD=
REMOTE_HEAD=
REMOTE_HEAD_MATCH=YES|NO
I7_SETUP=PASS|FAIL
I7_REACHABLE=PASS|FAIL
I7_REAL_DATA=PASS|FAIL
I7_CPU_COUNT=
I7_QA_CAPABILITY=PASS|FAIL
I7_REPOSITORY_CHANGE=PASS|FAIL
I7_SUPPLEMENTARY_COMPUTE=PASS|FAIL
I7_NO_FAKE_READY=PASS|FAIL
QA_COMPUTE_TO_I7=PASS|FAIL
REPOSITORY_CHANGE_TO_I7=PASS|FAIL
SUPPLEMENTARY_COMPUTE_TO_I7=PASS|FAIL
I7_REMOTE_EXECUTOR=PASS|FAIL
I7_CPU_PROBE=PASS|FAIL
I7_TARGET_TEST_REMOTE=PASS|FAIL
I7_FULL_TEST_REMOTE=PASS|FAIL
I7_REMOTE_OUTPUT_SHA256=PASS|FAIL
I7_EXACT_HEAD_ENFORCEMENT=PASS|FAIL
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
