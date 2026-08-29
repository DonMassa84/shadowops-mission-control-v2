# Kali Finalizer Status

STATUS=ASSIGNED
ROLE=security_forensics_finalizer
WORK_BRANCH=ai/kali-finalizer
BASE_INTEGRATION_BRANCH=local/all-developments
BASE_INTEGRATION_SHA=f4a61dc35a6afd2120e7630d5c7389f1bbdbfbb1
ISSUE=27

## Purpose

Kali `kali-2026` is the preferred ShadowOps security/forensics node and finalizer for the remaining production-readiness work. It may perform bounded repository finalization work, defensive validation, evidence collection and exact-head acceptance. It must not merge or deploy.

## Remaining ordered work

1. Verify Kali workspace, SSH access, OpenCode, evidence directories and required defensive tooling.
2. Complete capability routing:
   - Security / forensics / network analysis -> Kali
   - AI / GPU / local model work -> Ryzen
   - QA / auxiliary compute -> i7
3. Prove each Kali capability from current runtime/tool evidence; no synthetic READY.
4. Close all blocking ShadowOps Hardening CI gates on the exact candidate SHA.
5. Complete V2.5 truthful convergence accounting and persist the final report.
6. Freeze one immutable final candidate SHA after all code changes are complete.
7. Build/update 4015 from that exact SHA only.
8. Run 4015 governance acceptance.
9. Run Kali independent security acceptance against the same exact 4015 SHA.
10. Persist one final acceptance report to Issue #27.
11. Stop before any production promotion.

## Required Kali setup evidence

KALI_SETUP=PASS|FAIL|PARTIAL
HOSTNAME=kali-2026
SSH=PASS|FAIL
NAT_IP=192.168.122.238
SHADOWLAB_IP=10.20.0.173
OPENCODE_VERSION=
WORKSPACE=
EVIDENCE_PATH=
SHADOWOPS_NODE_CONTRACT=PASS|FAIL
READ_ONLY_TOOLSET=PASS|FAIL
KALI_SECURITY_AUDIT_WORKFLOW=PASS|FAIL
WEEKLY_SCHEDULE=PASS|FAIL

## Capability routing acceptance

SECURITY_TO_KALI=PASS|FAIL
AI_GPU_TO_RYZEN=PASS|FAIL
QA_COMPUTE_TO_I7=PASS|FAIL
UNKNOWN_CAPABILITY_FAIL_CLOSED=PASS|FAIL
MISSING_TOOL_FALSE_READY_BLOCKED=PASS|FAIL
ARBITRARY_EXECUTION=BLOCKED
ARBITRARY_SYSTEMD=BLOCKED
PRODUCTION_CONTROL_PLANE=FALSE

## Hardening gates

FORMAT_RC=
COMPILE_RC=
FULL_TEST_RC=
CREDO_CHANGED_RC=
CREDO_BASELINE_REPORT=
DIALYZER_BASELINE_REPORT=
SOBELOW_RC=
REGISTRY_VALIDATE_RC=
WORKFLOW_IDS_RC=
HEX_AUDIT_RC=
DIFF_CHECK_RC=
PRODUCTION_ACCEPTANCE_RC=
PROD_COMPILE_RC=
RELEASE_BUILD_RC=

## V2.5 convergence gate

V25_HEAD=
V25_CONNECTED=10
V25_TESTED=0
V25_BLOCKED_FROM_TESTED=10
V25_PRODUCTION_READY=0
V25_REMOTE_HEAD_MATCH=YES|NO
V25_READY_FOR_CONVERGENCE=YES|NO

`TESTED=0` and `PRODUCTION_READY=0` remain truthful until persisted canonical execution attestations exist. Evidence must never be fabricated to promote a workflow.

## Exact-head acceptance

FINAL_HEAD=
REMOTE_HEAD_MATCH=YES|NO
4015_ACCEPTANCE=PASS|FAIL|BLOCKED
APPROVAL_SINGLE_USE=PASS|FAIL
AUDIT_VERIFY=PASS|FAIL
RISK_DOWNGRADE_BLOCKED=PASS|FAIL
UNKNOWN_WORKFLOW_FAIL_CLOSED=PASS|FAIL
PRIVACY_GATE=PASS|FAIL
FALSE_READY=0
KALI_SECURITY_ACCEPTANCE=PASS|FAIL|BLOCKED
CRITICAL_BLOCKERS=
FINAL_ACCEPTANCE=PASS|FAIL

## Hard safety constraints

- NO_MERGE
- NO_DEPLOY
- NO_FORCE_PUSH
- NO_4013_MUTATION
- NO_4014_MUTATION from Kali acceptance work
- No arbitrary shell/executable-path or arbitrary systemd-unit execution exposed through ShadowOps.
- No destructive VM operations, image deletion/move, reformat, `virsh undefine`, SSH-key replacement or destructive network/firewall changes.
- No aggressive scanning or exploitation of non-lab/non-owned systems.
- No secrets, tokens, credentials or private message bodies in repository evidence.
- Approval consumption for L2/L3 remains single-use.
- Unknown/malformed/high-risk tasks fail closed.

## Final report contract

KALI_SETUP=PASS|FAIL|PARTIAL
CAPABILITY_ROUTING=PASS|FAIL
SECURITY_TO_KALI=PASS|FAIL
AI_GPU_TO_RYZEN=PASS|FAIL
QA_COMPUTE_TO_I7=PASS|FAIL
FULL_HARDENING_CI=PASS|FAIL
V25_READY_FOR_CONVERGENCE=YES|NO
FINAL_HEAD=
REMOTE_HEAD_MATCH=YES|NO
4015_ACCEPTANCE=PASS|FAIL|BLOCKED
KALI_SECURITY_ACCEPTANCE=PASS|FAIL|BLOCKED
CRITICAL_BLOCKERS=
READY_FOR_CONVERGENCE=YES|NO
FINAL_ACCEPTANCE=PASS|FAIL
4013_MUTATION=NO
