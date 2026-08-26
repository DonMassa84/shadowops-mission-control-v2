# ShadowOps Feature Recovery / Activation Evidence

Date: 2026-08-26
Branch: `fix/functional-core-20260826`

## Rule

A feature is treated as activated only through:

`existing function -> route -> UI -> real source -> runtime -> test -> evidence`

No route or adapter is promoted to production capability solely because code exists.

## Activation matrix

| Feature | Existing function | Route/API | Daily UI | Source truth | Contract | Runtime acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| Compute Center | `NodeCatalog`, `RuntimeSources`, `ExecutionService` | `/compute`, `/api/nodes`, governed node POST routes | ACTIVATED | physical runtime node evidence | ADDED | PENDING updated-head retest |
| Job Queue | `JobQueue` / Oban projection | `/jobs`, `/api/jobs` | ACTIVATED | explicit READY or NOT_CONFIGURED | ADDED | PENDING updated-head retest |
| Integrations | `IntegrationCatalog`, `SourceRegistry` | `/integrations`, `/api/integrations`, `/api/connectors` | ACTIVATED | `real_data`, `reachable`, `source`, `source_type`, errors | ADDED | PENDING updated-head retest |
| Evidence | `RuntimeSources.evidence` | `/evidence`, `/api/evidence` | ACTIVATED | bounded artifact metadata | EXISTING + recovery route contract | PENDING updated-head retest |
| Focus | `LearningFocus` | `/focus`, `/api/learning/plan` | ACTIVATED | allowlisted YAML plan / explicit fallback | ADDED | PENDING updated-head retest |
| WebMCP recovered reads | browser `document.modelContext` | jobs/integrations/connectors/evidence/focus read APIs | ACTIVATED | same-origin GET only, redacted/bounded | UPDATED | PENDING updated-head retest |
| Workflow execution | `ExecutionTracker` / `WorkflowJobs` / governance pipeline | `/workflows/:id`, POST run API | EXISTING | canonical registry + run/audit stores | EXISTING | previously accepted before recovery edits |
| Approval / Audit | approval store, governance gate, audit chain | approvals + audit UI/API | EXISTING | durable governance/audit state | EXISTING | previously accepted before recovery edits |

## Compute action truthfulness

The router exposes healthcheck/start/stop API routes, but route existence is not treated as adapter evidence.

Current recovered Compute UI activates only:

- physical node `status` / healthcheck
- i7 `start`

`stop` is deliberately not offered in the Compute UI because no concrete `OperationalSources.node_action("i7", "stop")` implementation was found during this activation pass.

## Removed obsolete surface

The previous `compute_live.html.heex` placeholder rendered static `UNKNOWN` / `UNVERIFIED` content and has been removed. `ComputeLive` now renders runtime-backed node and job evidence.

## WebMCP

Recovered read-only tools include:

- `shadowops_jobs`
- `shadowops_integrations`
- `shadowops_connectors`
- `shadowops_evidence`
- `shadowops_focus`

They retain the existing rules: GET only, same-origin, bounded output, sensitive-key redaction, `AUTH_REQUIRED` on protected APIs, and no write/governance bypass.

## Acceptance state

The pre-recovery head had operator-reported evidence of compile PASS, full test PASS, WebMCP PASS, remote-AI-policy PASS, Phoenix listening on `:4015`, and all selected live API routes HTTP 200.

The feature-recovery edits in this document were made after that acceptance run. Therefore the updated head remains:

`FEATURE_RECOVERY_RUNTIME_ACCEPTANCE=PENDING`

until compile, focused contracts, full tests and live routes are rerun on the updated branch head.
