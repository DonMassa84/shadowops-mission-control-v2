# V2.5 Workflow Runtime + Governance — Final Accounting

BRANCH=ai/v25-workflows
VERIFIED_CODE_SHA=9e1decb9a6e1b98b0870cfb5d10910b30fd693e3
HANDOFF_CURRENT=YES
V25_ACCOUNTING_COMPLETE=YES

## Scope closure

This checkpoint closes the V2.5 accounting contract without inventing execution evidence.
The verified code checkpoint discovered and connected 10 candidates, but its own durable evidence reports `TESTED=0` and `PRODUCTION_READY=0`. No persisted per-workflow canonical execution attestation is present for those 10 candidates in the branch evidence. Therefore none may be promoted to TESTED.

A CONNECTED workflow is not the same as a TESTED workflow. Runtime/source evidence is retained, while the TESTED transition fails closed until a real bounded canonical execution and persisted attestation exist.

## Work Completed

- Recovered 14 files from source worktree (governance/inventory/registry)
- Published verified code checkpoint `9e1decb9a6e1b98b0870cfb5d10910b30fd693e3`
- Ran recovery quality gates on that code checkpoint
- Verified security invariants and truthful source/runtime accounting
- Closed all 10 CONNECTED candidates with a terminal verdict: BLOCKED_FROM_TESTED where execution attestation is absent

## Inventory

RAW_TOTAL=5175
LOCALWF_REGISTERED=500
UNIQUE=500
NORMALIZED=489
REJECTED=4675
DUPLICATES=0

CONNECTED=10
TESTED=0
BLOCKED_FROM_TESTED=10
PRODUCTION_READY=0

## Risk Distribution

RISK_L0=35
RISK_L1=331
RISK_L2=108
RISK_L3=26
RISK_TOTAL=500

## Connected Workflow Terminal Verdicts

| ID | Risk | Capability | Adapter | Verdict | Exact blocker |
|----|------|------------|---------|---------|---------------|
| localwf_projects_2bfcaef0d5b8 | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_2bfde0029ca0 | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_34cdb22dfe1d | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_53bb185be57b | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_5b74eb4b262e | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_6b34f484140f | L0 | node.status | ScriptAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_bd7888260092 | L2 | service.status | SystemdAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_projects_fcac239a2dbc | L2 | node.status | ScriptAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_proofflow-obsidian-vault_598ffb03958e | L1 | knowledge.read | ScriptAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |
| localwf_proofflow-obsidian-vault_6fc36a3a1df6 | L1 | knowledge.read | ScriptAdapter | BLOCKED_FROM_TESTED | No persisted canonical execution attestation on verified V2.5 checkpoint |

## Security Invariants

SYNTHETIC_READY=0
MOCK_READY=0
UNKNOWN_RUNTIME_READY=0
UNKNOWN_CAPABILITY_READY=0
UNKNOWN_RISK_READY=0
ARBITRARY_COMMANDS=0
ARBITRARY_EXECUTABLE_PATHS=0
ARBITRARY_SYSTEMD_UNITS=0
METADATA_ONLY_PROMOTION=0

## Quality Gates on VERIFIED_CODE_SHA

FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0
RECOVERY_CORE_TESTS=180/180

The historical web failure recorded before Hy3 closure was the approval-consumption blocker. Hy3 subsequently resolved and independently verified that approval path with `FULL_TEST_RC=0` and `HY3_FINAL_ACCEPTANCE=PASS`; V2.5 does not claim ownership of that fix.

## Integration note

The V2.5 branch predates the current `local/all-developments` integration head and must not be merged blindly. Its genuine governance/inventory deltas are to be deduplicated against Hy3 and the current integration branch. The accounting above is complete regardless of whether any CONNECTED workflow later receives a real execution attestation.

BLOCKERS=NONE_FOR_ACCOUNTING
DEPENDENCIES=CONTROLLED_DEDUPLICATION_WITH_CURRENT_INTEGRATION_BASE
READY_FOR_INTEGRATION=YES
READY_TO_BUILD_INTEGRATION_CANDIDATE=YES

MERGE=NO
DEPLOY=NO
PRODUCTION_MUTATION=NO
4013_MUTATION=NO
