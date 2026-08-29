# One-Click Workflow Architecture (Preparation)

**Status:** Preparation / Inventory / Contract Design only.
**Branch:** `local/all-developments`
**No implementation, no new registry entries, no controllers, no LiveViews, no new scripts, no governance changes in this phase.**

This document defines how five "One-Click" workflows fit into the existing
ShadowOps control plane **without creating a new architecture**. The existing
workflow registry remains the workflow source of truth; all future side effects
remain behind the already-existing governance / execution service.

## Goal

Provide one-click daily mission control by composing existing read-only
runtime signals into five workflow contracts, with `daily_control` as the
orchestrator that produces a ranked Top-3 action list.

## Existing source-of-truth (reused, not replaced)

- **Workflow registry:** `config/workflow_registry_v2.yaml` — 9 existing
  workflow IDs (`finanzabgleich`, `career_email_only`, `document_ai`,
  `repository_quality`, `finance_quality_gate`, `agent_state_sync`,
  `career_funnel_ihk`, `daily_digest`, `shadow_system_overnight_audit`).
- **Read-only runtime surface:** `ShadowOpsApi` (`system_overview/0`,
  `career/0`, `evidence/0`, `approvals/0`, `runs/0`), `RuntimeSources`
  (`system/0`, `services/0`, `backups/0`, `career/0`, `evidence/0`, `logs/1`),
  `ShadowOpsWeb.SecurityStatus.check/0`, `ProjectDomains.snapshot/1`,
  `ShadowOpsWeb.SourceRegistry`.
- **Evidence engine:** `ShadowOpsCore.Evidence` (`build/4`, `drift/5`).
- **Certification gates:** `scripts/certify_all_developments.sh`,
  `scripts/production_acceptance.sh`, `scripts/shadowops-local.sh`,
  `.github/workflows/elixir.yml`, `mix shadowops.registry`,
  `mix shadowops.workflow_ids.validate`.
- **Governance chain:** `ExecutionService`, `GovernanceGate`,
  `CapabilityRegistry`, `Policy`, `RiskPolicy`, `PrivacyGate`,
  `ApprovalStore`, `Audit`.

## Data / control flow

```text
Existing ShadowOps Sources (read-only)
  system, security, services, career, ihk, git/tests, evidence,
  backups, approvals, runs/jobs, source registry
        │
        ▼
  Workflow Contracts (one per domain; pure read + classify)
        │   daily_control · system_doctor · release_acceptance
        │   career_control · ihk_evidence_gate
        ▼
  Daily Control Orchestrator  (collects the contracts, ranks, Top-3)
        │
        ▼
  TOP 3 NEXT ACTIONS
```

`daily_control` is the **orchestrator**, not a new monolith. It consumes the
other four contracts; it does not re-implement them.

## One-Click governance map

Every future mutating action from any of the five workflows MUST route
through the existing governed path:

```text
CapabilityRegistry (what is allowed)
  → Policy / RiskPolicy (L0–L3, approval_required?)
  → PrivacyGate (secret/token boundary)
  → ApprovalStore (durable Approval, single-use consume)
  → ExecutionService / WorkflowExecutor
  → Adapter (canonical_workflow / systemd / script / …)
  → Audit (hash-chained journal)
```

Controllers and LiveViews MUST NOT call mutating adapters directly. This
assertion is enforced by `execution_service.ex` (moduledoc) and the
write-authorization self-checks in `security_status.ex`.

## Per-workflow risk posture

| Workflow               | Default mode        | Risk        | Notes                                       |
|------------------------|---------------------|-------------|---------------------------------------------|
| `daily_control`        | read-only           | L0 / L1     | orchestrator; never mutates                 |
| `system_doctor`        | diagnose read-only  | L0 / L1     | repair is a **separate** L2/L3 capability   |
| `release_acceptance`   | gate runner         | L1          | no auto-promotion, no 4013 mutation         |
| `career_control`       | read-only pipeline  | L0 / L1     | send is a separate L3 action + approval     |
| `ihk_evidence_gate`    | read-only gate      | L0 / L1     | no invented evidence                         |

Diagnosis is not repair; sending is not reading; promotion is not acceptance.
Each separation is a distinct governed capability.
