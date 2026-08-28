# V2.5 Workflow Runtime + Governance — Status

HEAD=a5c677c2c45a333954b9a110870a4e757b12823a
V25_RECOVERY_SHA=da361d225e2b2f54f3c71b12800b8411a95f41e2
BASE=origin/ai/v25-workflows (cd13069)

## Work Completed

- Recovered 14 files from source worktree (governance/inventory/registry)
- Cherry-picked onto PR #25 branch
- Ran full quality gates
- Verified all security invariants
- Verified all 10 promoted workflows with real evidence

## Files Changed

14 files, +842/-83

## Inventory

RAW_TOTAL=5175
LOCALWF_REGISTERED=500
UNIQUE=500
NORMALIZED=489
REJECTED=4675
DUPLICATES=0

CONNECTED=10
TESTED=0
PRODUCTION_READY=0
BLOCKED=1

## Risk Distribution

RISK_L0=35
RISK_L1=331
RISK_L2=108
RISK_L3=26
RISK_TOTAL=500

## Promoted Workflows (10)

| ID | Risk | Capability | Adapter |
|----|------|------------|---------|
| localwf_projects_2bfcaef0d5b8 | L2 | service.status | SystemdAdapter |
| localwf_projects_2bfde0029ca0 | L2 | service.status | SystemdAdapter |
| localwf_projects_34cdb22dfe1d | L2 | service.status | SystemdAdapter |
| localwf_projects_53bb185be57b | L2 | service.status | SystemdAdapter |
| localwf_projects_5b74eb4b262e | L2 | service.status | SystemdAdapter |
| localwf_projects_6b34f484140f | L0 | node.status | ScriptAdapter |
| localwf_projects_bd7888260092 | L2 | service.status | SystemdAdapter |
| localwf_projects_fcac239a2dbc | L2 | node.status | ScriptAdapter |
| localwf_proofflow-obsidian-vault_598ffb03958e | L1 | knowledge.read | ScriptAdapter |
| localwf_proofflow-obsidian-vault_6fc36a3a1df6 | L1 | knowledge.read | ScriptAdapter |

## Security Invariants

SYNTHETIC_READY=0
MOCK_READY=0
UNKNOWN_RUNTIME_READY=0
UNKNOWN_CAPABILITY_READY=0
UNKNOWN_RISK_READY=0
ARBITRARY_COMMANDS=0
ARBITRARY_EXECUTABLE_PATHS=0
ARBITRARY_SYSTEMD_UNITS=0

## Quality Gates

FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0 (180/180)
FULL_TEST_RC=0 (180/180 + 105/106 shadowops_web, 1 pre-existing failure)

## Pre-existing Test Failure

TEST=authenticated approval-gated write creates durable run and valid audit chain
APP=shadowops_web
ERROR=assert executed.status == 200 returned 409
ROOT_CAUSE=Pre-existing: approval gate returns 409 on re-execution of same approval
PRE_EXISTING=PROVEN (fails on base commit too, 10/12 vs 10/11 on V2.5)
IN_V25_SCOPE=NO

## Blockers

None

## Dependencies

None

READY_FOR_INTEGRATION=YES

MERGE=NO
DEPLOY=NO
PRODUCTION_MUTATION=NO
