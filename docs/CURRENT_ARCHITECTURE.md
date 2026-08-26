# ShadowOps Current Architecture

Status date: 2026-08-26  
Branch: `fix/functional-core-20260826`  
Baseline head before this document: `73c91b4b7b63cb4e7e08be2d018b676b5dcb5c1f`  
PR: #21 — `Make ShadowOps useful: WebMCP, remote-only AI and feature recovery`

## 1. Current gate

The current functional core is green locally.

- `mix format --check-formatted`: PASS
- `MIX_ENV=test mix compile --warnings-as-errors`: PASS
- `MIX_ENV=test mix test`: PASS
- observed umbrella test results: `shadowops_core=112`, `workflow_engine=32`, `agent_runtime=9`, `shadowops_web=89`; total observed tests: 242, failures: 0
- PR branch push: PASS
- PR mergeability: mergeable
- GitHub status checks for this branch/base combination: not currently reported
- exact live runtime verification of the final formatting-only head on `:4015`: PENDING; prior functional runtime acceptance was green before the final formatting-only commit

No production-ready claim should depend on the pending live-head match.

## 2. Product boundary

ShadowOps is one Phoenix/Elixir control-plane application. It is not a collection of independent dashboards.

Its intended product contract is:

1. show what is happening,
2. show what needs attention,
3. show what should happen next from verified data,
4. execute only governed capabilities,
5. produce evidence and audit state for meaningful actions.

The primary UI is intentionally narrower than the full router surface. Secondary and experimental routes may remain routable without being promoted into daily navigation.

## 3. Runtime architecture

```text
Browser / API / WebMCP
        |
        v
Phoenix Router
        |
        +--> read-only browser/API projections
        |
        +--> control_plane_write
                    |
                    v
              Security / actor / rate limit
                    |
                    v
              ExecutionService
                    |
                    v
        CapabilityRegistry -> Policy -> Approval -> PrivacyGate
                    |
                    v
                  Adapter
                    |
                    v
              Audit + Events
```

`ExecutionService` is the central mutation boundary. Controllers and LiveViews must not call mutating adapters directly. There is no arbitrary-shell control-plane API.

## 4. Router and access boundaries

### Browser

Primary recovered daily-use routes include:

- `/`
- `/compute`
- `/workflows`
- `/runs`
- `/jobs`
- `/services`
- `/integrations`
- `/evidence`
- `/knowledge`
- `/approvals`
- `/security`
- `/audit`
- `/logs`
- `/focus`
- `/ai`
- `/agents`

Additional routes remain available for infrastructure, layers, legal, settings, projects, social views, reporting, career and i7 display. They are not all part of the daily navigation.

### Read API

The `:api` pipeline requires JSON and passes through `Security.require_read`.

Important read endpoints include:

- `/api/health`
- `/api/ready`
- `/api/system/overview`
- `/api/workflows`
- `/api/runs`
- `/api/jobs`
- `/api/nodes`
- `/api/services`
- `/api/agents`
- `/api/ai`
- `/api/integrations`
- `/api/connectors`
- `/api/evidence`
- `/api/learning/plan`
- `/api/approvals`
- `/api/audit`
- `/api/audit/verify`
- `/api/logs/recent`
- `/api/security/status`

### Write API

The `:control_plane_write` pipeline applies security, actor validation and rate limiting before controller execution.

Governed write endpoints include:

- `POST /api/workflows/:id/run`
- `POST /api/nodes/:id/actions/healthcheck`
- `POST /api/nodes/:id/actions/start`
- `POST /api/nodes/:id/actions/stop`
- `POST /api/services/:id/actions/:action`
- `POST /api/approvals`
- `POST /api/approvals/:id/approve`
- `POST /api/approvals/:id/reject`

A route existing does not prove that the backing runtime action exists. Capability availability must be demonstrated separately.

## 5. Governance and execution

The canonical mutation flow is:

```text
REQUEST
  -> ACTOR / IDENTITY
  -> CAPABILITY REGISTRY
  -> POLICY / RISK
  -> APPROVAL WHEN REQUIRED
  -> PRIVACY GATE
  -> EXECUTION SERVICE
  -> ADAPTER
  -> AUDIT
  -> EVENTS / EVIDENCE
```

Current capability classes include workflow execution, node actions, service/systemd actions, OpenCode execution, Gmail actions and GitHub data actions.

Registered-but-not-connected capabilities currently include at least:

- `shadowctl.run`
- `ollama.generate`
- `local_agent.invoke`
- `telegram.send`

Registration is metadata, not availability evidence.

### AI policy

The active AI projection is policy-only and fail closed:

- `coding_execution=REMOTE_ONLY`
- `local_llm_runtime=DISABLED`
- `local_coding_fallback=FORBIDDEN`
- `fallback=NONE`
- `models=[]`
- `loaded_models=[]`
- model authority: CLI `--model`

`ollama.generate` remains registered as `:not_connected`. The active product surface does not expose local Ollama models.

## 6. Runtime overview

`RuntimeOverview` builds a bounded concurrent snapshot with a 3.5 second probe timeout and converts source errors/timeouts into explicit unavailable projections.

Current probe domains:

- system
- workflows
- runs
- services
- nodes
- agents
- AI policy
- approvals
- audit
- security
- knowledge
- evidence
- connectors
- career
- backups
- legal

Readiness currently depends on:

- workflow registry readable,
- audit chain valid,
- learning focus available.

This is fail closed, but coupling global readiness to LearningFocus should be reviewed because a personal focus source may not belong in infrastructure readiness.

## 7. Workflow model

Workflow inventory deliberately separates canonical and external runtime sets.

### Canonical

Canonical workflows may be executable through the governed execution path when their status and backing runtime allow it.

### External runtime inventory

External workflows are projected as inventory evidence with:

- `status=REGISTRY_ONLY`
- `execution_status=EXTERNAL_REGISTRY_ONLY`
- `executable=false`

Nested packs are excluded from parent totals when marked as included, preventing double counting.

The dashboard action list is intentionally canonical/executable-first rather than exposing every registry record as runnable.

## 8. Source and integration architecture

### SourceRegistry

The local source registry currently knows these import classes:

- Gmail
- Google Calendar
- Google Drive
- GitHub
- ChatGPT Project
- WhatsApp
- Telegram
- Obsidian
- Finance
- i7 Node

These are evidence manifests, not proof of live provider connections. Missing files become `NOT_CONFIGURED`; invalid JSON/schema, symlinks and unreadable files fail visibly.

Secret values are never returned. Only required/configured secret names and state are projected.

### IntegrationCatalog

The integration catalog combines:

1. core control-plane projections,
2. external connector records,
3. local import evidence.

Retired Ollama connector records are filtered from the active catalog.

### Data truth fields

Current source/integration records can expose:

- `status`
- `health`
- `source`
- `source_type`
- `real_data`
- `synthetic`
- `reachable`
- `record_count`
- `last_sync`
- `secret_binding`
- `error_code`
- `error_message`

## 9. Important truth-model gaps

### GAP-1 — import `real_data` default is too permissive

For a valid import JSON, `SourceRegistry` currently evaluates `real_data` with a default of `true` when the field is absent.

This is incompatible with the stricter product rule:

```text
IMPLEMENTED != CONNECTED != HAS_REAL_DATA != REACHABLE != VERIFIED
```

Recommended correction: default `real_data` to `false` and require explicit evidence to promote it to true.

Priority: HIGH.

### GAP-2 — integration aggregate can look healthy too easily

`IntegrationCatalog` currently marks the aggregate `READY/HEALTHY` when any record is positive.

That can hide a large number of degraded or not-configured sources.

Recommended correction: expose separate counts and derive aggregate state from required/core sources, while optional sources remain non-blocking.

Priority: HIGH.

### GAP-3 — route existence versus adapter evidence

`node.stop` is registered and a write route exists, but the Compute UI intentionally hides Stop because no concrete i7 stop adapter was proven during feature recovery.

Recommended rule: never expose a control as active from route/capability metadata alone.

Priority: KEEP CURRENT FAIL-CLOSED BEHAVIOR.

### GAP-4 — dead local-LLM execution code remains

`ExecutionService` still contains an `:ollama_runtime` dispatch clause and imports `OllamaAdapter`, while no active capability selects that executor.

This is currently unreachable through `ollama.generate` because its executor is `:not_connected`, but it is dead breadth.

Recommended correction: remove only after contract/reference audit proves no active dependency.

Priority: MEDIUM.

### GAP-5 — CI does not currently report checks for PR #21

The existing production workflow targets `main` for pull requests, while PR #21 targets `local/all-developments`.

Recommended correction: add or reuse a non-mutating CI contract for the actual integration branch before declaring merge-gate automation complete.

Priority: HIGH.

## 10. Active information architecture

Current daily navigation is intentionally grouped:

### Dashboard

- Overview

### Operations

- Compute
- Workflows
- Runs
- Jobs
- Services
- Backups

### Sources

- Integrations
- Evidence
- Knowledge

### Governance

- Approvals
- Security
- Audit
- Logs

### Focus & AI

- Focus
- AI
- Agents

This is the current production-oriented navigation. Broader project/social/legal/settings routes remain secondary until they meet the same activation standard.

## 11. Feature / source / runtime matrix

Legend:

- `YES` — code or route existence verified in the current branch
- `LOCAL_PASS` — covered by the current green local suite or local request tests
- `DYNAMIC` — depends on runtime/import evidence and must not be assumed
- `PENDING_LIVE_HEAD` — final exact-head process on `:4015` has not been re-proven after the formatting-only commit
- `SECONDARY` — routable but not promoted to daily navigation

| Feature | Code | Route/API | Source model | Test state | Real data | Current classification |
|---|---|---|---|---|---|---|
| Dashboard | YES | `/` | RuntimeOverview + Registry + JobQueue | LOCAL_PASS | mixed/dynamic | ACTIVE |
| Compute | YES | `/compute`, node APIs | NodeCatalog + JobQueue + RuntimeSources | LOCAL_PASS | DYNAMIC | ACTIVE, stop hidden unless proven |
| Jobs | YES | `/jobs`, `/api/jobs` | JobQueue / Oban projection | LOCAL_PASS | DYNAMIC | ACTIVE |
| Workflows | YES | UI + read/write APIs | Registry + Inventory + adapters | LOCAL_PASS | registry is real local state | ACTIVE |
| Runs | YES | UI + APIs | persisted/in-memory run source | LOCAL_PASS | DYNAMIC | ACTIVE |
| Services | YES | UI + APIs + governed actions | RuntimeSources + SystemdAdapter | LOCAL_PASS | DYNAMIC | ACTIVE |
| Integrations | YES | `/integrations`, `/api/integrations` | RuntimeOverview + connectors + SourceRegistry | LOCAL_PASS | DYNAMIC | ACTIVE; truth hardening required |
| Evidence | YES | UI + API | ShadowOps evidence projection | LOCAL_PASS | DYNAMIC | ACTIVE |
| Knowledge | YES | UI + API | ShadowOps knowledge projection | LOCAL_PASS | DYNAMIC | ACTIVE |
| Focus | YES | `/focus`, `/api/learning/plan` | LearningFocus YAML/fallback | LOCAL_PASS | local configured state | ACTIVE |
| Approvals | YES | UI + read/write APIs | ApprovalStore | LOCAL_PASS | real control-plane state | ACTIVE |
| Audit | YES | UI + `/api/audit/verify` | append/verify audit chain | LOCAL_PASS | real control-plane state | ACTIVE |
| Security | YES | UI + API | SecurityStatus / policy state | LOCAL_PASS | real policy/runtime state | ACTIVE |
| Logs | YES | UI + APIs | bounded runtime logs | LOCAL_PASS | DYNAMIC | ACTIVE |
| AI | YES | UI + API | policy projection | LOCAL_PASS | policy state, no local models | ACTIVE REMOTE_ONLY |
| Agents | YES | UI + API | agent/runtime projections | LOCAL_PASS | DYNAMIC | ACTIVE surface; execution may be degraded |
| Career | YES | UI + API | module source | LOCAL_PASS route coverage | DYNAMIC | SECONDARY |
| Legal | YES | UI + API | legal registry/source | LOCAL_PASS route/API coverage | DYNAMIC | SECONDARY |
| Settings | YES | `/settings` | application/runtime config projection | route exists | DYNAMIC | SECONDARY |
| Project domains | YES | `/projects/*` | project manifests/sources | LOCAL_PASS route coverage | DYNAMIC | SECONDARY |
| Facebook views | YES | social routes/API | Facebook source projection | LOCAL_PASS route/API coverage | DYNAMIC | SECONDARY |
| Messenger/WhatsApp/Telegram UI shells | YES | social routes | unavailable-state views / connector evidence | LOCAL_PASS route coverage | DYNAMIC | SECONDARY / NOT_CONNECTED unless evidence exists |
| Metrics | YES | `/metrics` | Prometheus exporter | prior acceptance + tests | runtime metrics | SYSTEM |
| Runtime dashboard | YES | `/runtime` | Phoenix LiveDashboard | access-gated tests | runtime state | SYSTEM |
| WebMCP | YES | browser `document.modelContext` | 16 bounded GET-only tools | LOCAL_PASS | mirrors read APIs | ACTIVE READ-ONLY |

## 12. WebMCP boundary

Current browser WebMCP exposes 16 bounded read-only tools:

- health
- readiness
- overview
- workflows
- runs
- jobs
- nodes
- services
- integrations
- connectors
- evidence
- focus
- approvals
- audit
- logs
- security

Rules:

- `document.modelContext`
- same-origin
- GET only
- read-only hints
- sensitive-key redaction
- bounded output
- no write/governance bypass
- protected APIs may return `AUTH_REQUIRED`

## 13. What should be built next

Do not add broad new domains yet.

Recommended order:

1. fix SourceRegistry `real_data` default and add regression test,
2. improve IntegrationCatalog aggregate health semantics,
3. add CI coverage for PRs targeting `local/all-developments`,
4. re-run exact-head live acceptance on `:4015`,
5. implement Mission + deterministic Top-3 Next Actions from existing verified sources,
6. consolidate duplicate conceptual integrations,
7. only then promote selected life domains such as IHK/Career based on source truth.

## 14. Production claim

Current status:

```text
FUNCTIONAL_CORE=GREEN
LOCAL_FORMAT=PASS
LOCAL_COMPILE=PASS
LOCAL_TESTS=PASS
REMOTE_BRANCH_PUSHED=YES
PR_MERGEABLE=YES
LIVE_FINAL_HEAD_MATCH=PENDING
DATA_TRUTH_HARDENING=OPEN
FINAL_STATUS=NOT_YET_PRODUCTION_READY
```

The next production claim must be evidence-based and must not be upgraded until the final head is live-verified and the high-priority truth-model gaps are closed or explicitly accepted as degraded optional behavior.
