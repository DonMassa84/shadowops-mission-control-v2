# MiMo Governance Handoff

BRANCH=ai/mimo-governance
ROLE=Governance + Baseline Owner
STATUS=READY_FOR_WORK

## Scope
- CapabilityRegistry / RiskPolicy consistency
- LocalWorkflowEvidenceStore error contract
- WorkflowCuration final-risk / approval invariants
- WorkflowEngine AgentContract
- Full repository baseline

## Required invariants
- effective risk cannot be lowered by evidence
- L2/L3 always require approval
- unknown local workflow IDs fail closed with the canonical specific error
- pdf_governance.read is consistently registered and risk-mapped if referenced canonically
- no fake runtime readiness

## Report contract
HEAD=
FILES_CHANGED=
FORMAT_RC=
COMPILE_RC=
GOVERNANCE_TEST_RC=
WORKFLOW_ENGINE_RC=
FULL_TEST_RC=
PDF_GOVERNANCE=
RISK_DOWNGRADE_BLOCKED=
APPROVAL_BYPASS_BLOCKED=
BLOCKERS=
DEPENDENCIES=
READY_FOR_INTEGRATION=NO

## Safety
MERGE=NO
DEPLOY=NO
PORT_4013_TOUCHED=NO
PORT_4014_TOUCHED=NO
PORT_4015_TOUCHED=NO
EXTERNAL_WRITES=0
