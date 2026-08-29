# One-Click Workflow Reuse Matrix (Preparation)

**Status:** Preparation / Inventory only. Percentages are preparation estimates
of how much of each desired workflow already exists as reusable components.

None of the five desired workflow IDs currently exist in
`config/workflow_registry_v2.yaml`. All reuse targets below were verified to
exist in the repository at preparation time.

## Reuse matrix

| Desired Workflow          | Existing Components (reused)                                                                                  | Reuse % | Missing Components                                                                 | New Risk |
|---------------------------|---------------------------------------------------------------------------------------------------------------|---------|-----------------------------------------------------------------------------------|----------|
| `daily_control`          | `ShadowOpsApi.system_overview/0`, `SecurityStatus.check/0`, `RuntimeSources.system/services/backups/career`, `ProjectDomains.snapshot(:ihk)`, `Audit.verify/0`, `ApprovalStore.list/0`, `RunStore` (via `ShadowOpsApi.runs/0`), `SourceRegistry.all/0` | 82%     | composition/aggregator module; cross-domain Top-3 ranking                          | L0/L1    |
| `system_doctor`           | `RuntimeSources.system/0`, `services/0`, `logs/1`; `OperationalSources` helpers (`cpu_info`, `load_info`, `meminfo`, `disk_info`, `temperatures`, `network_info`); `Audit.verify/0`; `SecurityStatus.check/0`; `backups/0` | 85%     | inode-usage probe; pending-package/pending-update probe; fs-mount warning probe; composition module | L0/L1 (diagnose), L2/L3 (repair, separate) |
| `release_acceptance`      | `scripts/certify_all_developments.sh`, `scripts/production_acceptance.sh`, `scripts/shadowops-local.sh` (`certify`/`promote`), `.github/workflows/elixir.yml`, `mix shadowops.registry`, `mix shadowops.workflow_ids.validate`, `WorkflowEngine.Registry.validate/1` | 90%     | registry entry wrapping the existing script (pattern proven by `agent_state_sync`/`daily_digest`); `agent_contract` block | L1       |
| `career_control`          | `RuntimeSources.career/0`, `ShadowOpsApi.career/0`, `ProjectDomains.snapshot(:career)`, `SourceRegistry` (gmail/calendar/drive stubs), `CapabilityRegistry` (`gmail.*` registered) | 55%     | read-only `CareerControl` module; funnel-state mapping (NEW_LEAD…CLOSED); Gmail adapter is a **stub → Deny** (no live connector in-repo) | L0/L1 (read), L3 (send, separate) |
| `ihk_evidence_gate`       | `ShadowOpsCore.Evidence` (`build/4`, `drift/5`), `RuntimeSources.evidence/0`, `ProjectDomains.snapshot(:ihk)`, `SourceRegistry.snapshot("drive"/"obsidian")`, `evidence_live.ex` | 70%     | IHK evidence-category enumerator (11 categories); IHK evidence manifest schema      | L0/L1    |

## Summary counts (preparation estimates)

- **EXISTING_WORKFLOWS_FOUND = 9** (in `config/workflow_registry_v2.yaml`).
- **EXISTING_COMPONENTS_REUSED = 24** distinct reusable units cited above
  (runtime sources, security, audit, evidence, source registry, certify
  scripts, mix tasks, governance chain).
- **NEW_COMPONENTS_REQUIRED = 12** (estimate):
  - 5 new registry entries (`daily_control`, `system_doctor`,
    `release_acceptance`, `career_control`, `ihk_evidence_gate`).
  - 5 new canonical IDs in `config/workflow_ids.yaml`
    (`so:wf:v1:daily-control`, `so:wf:v1:system-doctor`,
    `so:wf:v1:release-acceptance`, `so:wf:v1:career-control`,
    `so:wf:v1:ihk-evidence-gate`).
  - ~2 net-new Elixir composition modules (`daily_control`,
    `system_doctor`) + 3 probe additions folded into `system_doctor`.
  - 1 `agent_contract` for `release_acceptance` (wiring only).
  - 1 `career_control` read module + funnel mapping.
  - 1 `ihk_evidence` enumerator + manifest schema.

## Reuse principle

Maximize reuse; build no second workflow engine. Where a capability is a
capability-registry stub (e.g. `gmail.*` → `Deny`), document the stub rather
than implementing a live connector in this preparation/contract phase.
