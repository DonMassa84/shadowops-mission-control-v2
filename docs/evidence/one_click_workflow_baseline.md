# One-Click Workflow Baseline (Preparation Evidence)

**Phase:** ONE_CLICK_WORKFLOW_PREPARATION_ONLY
**Branch:** `local/all-developments`
**Date:** 2026-08-26
**Scope:** inventory, contract design, documentation only. No code, no registry
entries, no controllers, no LiveViews, no new scripts, no governance changes.

## What was done

- Inventoried existing workflows, registry entries, scripts, mix tasks,
  runtime sources, controllers/routes, LiveViews, evidence generators, career
  and IHK modules, system/security diagnostics, backup/maintenance code,
  release/acceptance scripts and daily-control/mission/next-action code.
- Confirmed none of the five desired workflow IDs exist yet.
- Defined one canonical result contract shared by all five workflows.
- Mapped each workflow to existing reusable components and missing components.
- Documented the existing governance/execution path that future mutations must
  use.

## Deliverables (documentation only)

- `docs/workflows/ONE_CLICK_WORKFLOW_ARCHITECTURE.md`
- `docs/workflows/ONE_CLICK_WORKFLOW_REUSE_MATRIX.md`
- `docs/workflows/ONE_CLICK_WORKFLOW_CONTRACTS.md`
- `docs/evidence/one_click_workflow_baseline.md` (this file)

## Baseline metrics (preparation estimates)

```text
DAILY_CONTROL_REUSE=82%
SYSTEM_DOCTOR_REUSE=85%
RELEASE_ACCEPTANCE_REUSE=90%
CAREER_CONTROL_REUSE=55%
IHK_EVIDENCE_REUSE=70%

EXISTING_WORKFLOWS_FOUND=9
EXISTING_COMPONENTS_REUSED=24
NEW_COMPONENTS_REQUIRED=12

GOVERNANCE_MODEL=REUSED
NEW_ARCHITECTURE=NO
RUNTIME_MUTATIONS=0
EXTERNAL_ACTIONS=0
PUSH=NO
```

## Reuse highlights

- **Daily Control** reuses `ShadowOpsApi.system_overview/0`,
  `SecurityStatus.check/0`, `RuntimeSources.*`, `ProjectDomains`,
  `Audit`, `ApprovalStore`, `RunStore`.
- **System Doctor** reuses the existing `RuntimeSources` / `OperationalSources`
  probes; only inode / pending-update / fs-warning probes are missing.
- **Release Acceptance** reuses `scripts/certify_all_developments.sh` and the
  CI gate chain; only registry wiring + `agent_contract` are new.
- **Career Control** reuses `RuntimeSources.career/0` and `SourceRegistry`;
  funnel-state mapping and a live Gmail adapter are absent (stub → `Deny`).
- **IHK Evidence Gate** reuses `ShadowOpsCore.Evidence`, `RuntimeSources.evidence/0`
  and `ProjectDomains.snapshot(:ihk)`; only the IHK category enumerator and
  manifest schema are new.

## Governance assertion

All future mutating actions from these workflows route through the existing
`ExecutionService` → `GovernanceGate` → `CapabilityRegistry` → `Policy` →
`RiskPolicy` → `PrivacyGate` → `ApprovalStore` → `Adapter` → `Audit` chain.
No controller or LiveView receives direct mutating adapter calls.

## Recommended implementation order

1. `daily_control` (read-only core) — highest reuse, orchestrator.
2. `system_doctor` (diagnostic).
3. `release_acceptance`.
4. `ihk_evidence_gate`.
5. `career_control`.

(Reorder only if repository evidence shows a better sequence.)

## Validation

- `git diff --check` passes on the changed worktree (documentation only).
- No existing source code was modified for implementation; existing code was
  only read.
- No tests were changed.

```text
NEXT_RECOMMENDED_WORKFLOW=shadowops.daily_control
FINAL_STATUS=ONE_CLICK_WORKFLOW_PREPARATION_READY
```
