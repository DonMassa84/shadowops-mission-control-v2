# Hy3 Acceptance Handoff

BRANCH=ai/hy3-acceptance
ROLE=Independent Production Acceptance + Security Auditor
STATUS=HY3_PERSISTENCE_CLOSURE
HANDOFF_CURRENT=YES

## Scope
- independently audit production-readiness claims
- verify CapabilityRegistry/RiskPolicy/Approval/PrivacyGate/ExecutionService boundaries
- detect false READY states, approval bypasses and arbitrary execution paths
- run full acceptance tests without performing production mutations

## Required invariants
- all executable workflows have real source, runtime, capability, risk and audit evidence
- all L2/L3 require approval and reject reuse/mismatch
- no synthetic/mock/unknown-runtime/unknown-capability READY
- no arbitrary command, executable or systemd target
- no direct controller/LiveView mutation bypass

## Verified state (gates run on VERIFIED_CODE_SHA)
VERIFIED_CODE_SHA=4ac1ee2a5861ab5160acd1bb5b61769068607388
PUSHED_TO=origin/ai/hy3-acceptance (PR #26, DRAFT)
HANDOFF_CHECKPOINT=docs-only commit atop VERIFIED_CODE_SHA; no code change, so re-running gates on this checkpoint HEAD yields identical RC=0.
HEAD=4ac1ee2a5861ab5160acd1bb5b61769068607388

## Work completed
- Operator governance baseline recovery (commit e515f98 "Recover V2.5 workflow governance and inventory changes"):
  - CapabilityRegistry: pdf_governance.read added (executor :not_connected, risk L0)
  - RiskPolicy: pdf_governance.read L0
  - WorkflowCuration: approval_required derived from final effective risk (never from evidence override)
  - LocalWorkflowEvidenceStore.get: returns {:error, :unknown_workflow_id} for unknown local workflows
  - governance_baseline_recovery_test.exs: 9 regression tests (all pass)
- Hy3 final approval blocker fix (commit 4ac1ee2):
  - canonical_event.ex: registered "approval.consumed" in CanonicalEvent.@types (1 line)
  - Root cause: ApprovalStore.consume/5 published an unregistered event type -> rejected by CanonicalEvent.validate/1 -> consume failed -> L2/L3 approval-gated runs blocked at the consume edge (fail-closed, 409). Fixed; MissionControlUITest now passes (200 + COMPLETED).

## Files changed (this session)
- apps/shadowops_core/lib/shadow_ops_core/canonical_event.ex (commit 4ac1ee2)

## Gates (run on VERIFIED_CODE_SHA; re-verified identical on handoff checkpoint HEAD)
FORMAT_RC=0
COMPILE_RC=0 (MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix compile --warnings-as-errors)
TARGET_TEST_RC=0 (governance_baseline_recovery_test.exs 9 + local_workflow_evidence_store_test.exs + agent_contract_test.exs)
WORKFLOW_ENGINE_RC=0 (apps/workflow_engine full: 32 passed)
FULL_TEST_RC=0 (repo full suite: 106 passed, 0 failures)

## Audit results
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0
FALSE_READY_COUNT=0
APPROVAL_BYPASS_COUNT=0
RISK_DOWNGRADE_COUNT=0
ARBITRARY_EXECUTION_COUNT=0
DIRECT_MUTATION_BYPASS_COUNT=0
APPROVAL_SINGLE_USE=PASS
AUDIT_CHAIN=PASS

## Root cause / fix summary
- ROOT_CAUSE: ApprovalStore.consume/5 published "approval.consumed", not registered in CanonicalEvent.@types -> {:error, {:invalid_field, :type}} -> consume failed -> approval-gated run blocked (fail-closed, no bypass).
- PRE_EXISTING_FAILURE=YES: consume/5 + "approval.consumed" publish came from working-tree edits present before this session; at base b4eed98 consume/5 did not exist.
- FIX: added "approval.consumed" to CanonicalEvent.@types (1 line). Invariants preserved; single-use consumption emits a valid canonical event.
- DOUBLE_CONSUME=SAFE (proven): second consume -> {:blocked, {:approval_status, "CONSUMED"}} -> run blocked, no double execution.
- APPROVAL_PATH_CONSISTENT=YES: CREATE/APPROVE/VALIDATE/CONSUME share ApprovalStore + CanonicalEvent/EventBus; same approval_id/action/resource/risk propagate.

## Blocker
- NONE for Hy3 acceptance. Final approval blocker resolved and pushed.

## Dependencies
- DEPENDENCY_WAIT: awaiting V2.5 candidate SHAs for CONNECTED->TESTED (Supervisor, i7, communications audits per Issue #27 convergence gate). Hy3 does not modify V2.5 implementation.
- PR #26 remains DRAFT. No merge, no deploy, no force-push, no production runtime mutation.

## Readiness
READY_FOR_INTEGRATION=YES (Hy3 independent acceptance PASS; no critical false-readiness or approval-bypass finding)
HY3_FINAL_ACCEPTANCE=PASS

## Safety
MERGE=NO
DEPLOY=NO
PORT_4013_TOUCHED=NO
PORT_4014_TOUCHED=NO
PORT_4015_TOUCHED=NO
EXTERNAL_WRITES=0
