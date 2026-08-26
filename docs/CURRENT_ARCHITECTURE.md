# ShadowOps Current Architecture

Status date: 2026-08-26  
Branch: `fix/functional-core-20260826`  
PR: #21 — `Make ShadowOps useful: WebMCP, remote-only AI and feature recovery`

## 1. Current gate

The functional core was green locally before the mission/truth hardening pass.

Previously observed:

- `mix format --check-formatted`: PASS
- `MIX_ENV=test mix compile --warnings-as-errors`: PASS
- `MIX_ENV=test mix test`: PASS
- observed umbrella test results: `shadowops_core=112`, `workflow_engine=32`, `agent_runtime=9`, `shadowops_web=89`; total observed tests: 242, failures: 0
- PR branch push: PASS

The current mission/truth head adds source-truth hardening and deterministic Mission/Top-3 logic. Exact-head local compile/test/runtime acceptance is PENDING until the current branch is fetched and verified on the local host.

No production-ready claim should depend on the pending exact-head verification.

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

Secondary or experimental routes remain routable but are not part of the primary daily navigation, including project-domain pages, social experiments, legal, reporting, layer health and the i7 display.

### Read API

The `:api` pipeline accepts JSON and applies `Security.require_read`.

Important read projections include:

- health/readiness/system overview
- workflows/runs/jobs
- nodes/services/agents
- AI status
- security/audit/logs
- knowledge/evidence/legal
- learning plan
- approvals
- integrations/connectors/social/career/backups/reports

### Write control plane

Mutations are isolated in `:control_plane_write`, which applies:

1. security authentication,
2. write actor requirement,
3. rate limiting.

Write routes include workflow execution, approval transitions, node actions and service actions.

Route existence alone does not prove that the runtime action is implemented. The UI only promotes actions with concrete adapter evidence.

## 5. Governance path

Canonical mutation path:

```text
Request
  -> actor / identity
  -> CapabilityRegistry
  -> Policy
  -> approval validation when required
  -> PrivacyGate
  -> ExecutionService
  -> allowlisted adapter
  -> Audit
  -> Events
```

Fail-closed behavior is deliberate. Registered capabilities with unavailable integrations use `:not_connected` and fall through the deny adapter rather than silently using another runtime.

Current notable capability truth:

- canonical workflow execution: connected
- service/systemd runtime: connected through allowlisted runtime/service state
- node status: connected where runtime evidence exists
- i7 node start: exposed because a concrete runtime implementation exists
- i7 node stop: not promoted in the UI until concrete implementation is proven
- OpenCode execution: runtime adapter exists
- Ollama generation: `:not_connected`
- local agent invocation: `:not_connected`
- Telegram send: `:not_connected`
- Gmail/GitHub capabilities: registry entries exist; registry presence alone is not connection evidence

## 6. AI policy

Active product AI state is policy-only and remote-only:

- coding execution: `REMOTE_ONLY`
- local LLM runtime: `DISABLED`
- local coding fallback: `FORBIDDEN`
- fallback: `NONE`
- model authority: CLI `--model`
- active local model inventory: empty

Retired Ollama connector rows are excluded from the active integration catalog.

## 7. Source truth model

`SourceRegistry` knows these local import-evidence source IDs:

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

A configured source entry is not automatically healthy.

For import JSON evidence:

- missing file -> `NOT_CONFIGURED`
- invalid/unreadable file -> fail visible
- `real_data` defaults to `false` when omitted
- `reachable` defaults to `false` when omitted
- external/import sources contribute to positive health only when status is positive AND `real_data=true` AND `reachable=true`
- secret names may be reported as configured/missing, but secret values are never projected

This prevents a merely present JSON file from being silently promoted to verified real data.

## 8. Integration health model

The Integration Catalog separates required control-plane health from optional source health.

Required core modules are:

- System
- Workflows
- Runs
- Services
- Nodes
- AI / Models
- Approvals
- Audit
- Security

Overall integration status is derived only from this required core set:

- all required core positive -> `READY`
- some required core positive -> `DEGRADED`
- no required core evidence -> `UNAVAILABLE`

Optional modules, external connectors and imports are reported separately and cannot make a degraded required core appear healthy.

The UI exposes both `required_core_ready_count / required_core_count` and `optional_ready_count / optional_count`.

## 9. Mission and Top-3 next actions

The dashboard now exposes a deterministic Mission Brief.

Mission source:

- first choice: validated `LearningFocus` configuration
- if no validated configured mission exists: bounded runtime-readiness fallback
- no AI-generated mission text is used

Next-action priority is deterministic:

1. pending governed approvals,
2. failed/degraded runtime readiness,
3. degraded required integrations,
4. degraded runtime services,
5. degraded physical compute,
6. unavailable/degraded persistent job queue,
7. configured current focus and configured `next` items.

Only the first three candidates are rendered. Each action includes its source and route. No task is invented merely to fill the list.

## 10. WebMCP

WebMCP uses `document.modelContext` and remains read-only.

Current tools project bounded versions of:

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

- GET only
- same-origin
- no write/governance bypass
- auth remains enforced
- sensitive keys are redacted
- output is bounded

## 11. Feature / source / runtime matrix

| Surface | Route | Backing source | Real-data rule | Mutation | Runtime evidence state |
|---|---|---|---|---|---|
| Dashboard | `/` | RuntimeOverview + JobQueue + IntegrationCatalog + LearningFocus | source-backed summaries only | No | previously accepted; current mission head pending exact-head retest |
| Mission / Top 3 | `/` | MissionBrief over verified runtime/focus state | deterministic; no invented tasks | No | contract added; local retest pending |
| Compute | `/compute` | NodeCatalog + JobQueue | physical nodes only | Governed node actions | status/start evidence-backed; stop hidden |
| Workflows | `/workflows` | Workflow registry | canonical and external provenance preserved | Governed run | canonical execution path proven previously |
| Runs | `/runs` | Run store/API | persisted runtime state | No | available when store source is available |
| Jobs | `/jobs`, `/api/jobs` | JobQueue / Oban projection | bounded job metadata | No | source-backed projection |
| Services | `/services` | Runtime service discovery | runtime state | Governed action | Systemd adapter path exists |
| Integrations | `/integrations` | RuntimeOverview + connectors + SourceRegistry | required core separated from optional; imports fail closed | No | contract added; local retest pending |
| Evidence | `/evidence` | evidence source/API | privacy-safe metadata | No | route/API proven previously |
| Knowledge | `/knowledge` | knowledge source/API | source state explicit | No | source-dependent |
| Focus | `/focus`, `/api/learning/plan` | allowlisted YAML/fallback | validated schema | No | route/API proven previously |
| Approvals | `/approvals` | ApprovalStore | persisted governance state | Governed transitions | transition contract previously proven |
| Audit | `/audit` | Audit chain | hash-chain verification | No direct arbitrary mutation | verification previously proven |
| Security | `/security` | SecurityStatus | policy/runtime projection | No | route/API proven previously |
| Logs | `/logs` | bounded log source | bounded diagnostics | No | route/API proven previously |
| AI | `/ai`, `/api/ai` | Remote AI policy | no local models | No local LLM execution | remote-only contract previously proven |
| Agents | `/agents` | agent source | source state explicit | capability-dependent | source-dependent |
| WebMCP | browser API | selected read APIs | redacted + bounded | No | contract previously proven |
| Gmail imports | Integration catalog | `gmail.json` + secret-binding state | `real_data` and `reachable` must be explicit | No | environment/import dependent |
| Calendar imports | Integration catalog | `calendar.json` + secret-binding state | same | No | environment/import dependent |
| Drive imports | Integration catalog | `drive.json` + secret-binding state | same | No | environment/import dependent |
| GitHub imports | Integration catalog | `github.json` + secret-binding state | same | No | environment/import dependent |
| WhatsApp imports | Integration catalog | `whatsapp.json` | same | No | import dependent |
| Telegram imports | Integration catalog | `telegram.json` + token-binding state | same | send capability remains not connected | environment/import dependent |
| Obsidian imports | Integration catalog | `obsidian.json` | same | No | import dependent |
| Finance imports | Integration catalog | `finance.json` | same | No | import dependent |
| i7 import | Integration catalog | `i7.json` | same | node actions separately governed | import/runtime dependent |

## 12. Remaining high-value gaps

Do not widen feature breadth until these are resolved or deliberately accepted:

1. exact-head local format/compile/full-test/runtime acceptance for the mission/truth head,
2. CI trigger coverage for PRs targeting `local/all-developments`,
3. real connector/import evidence for sources that currently remain environment-dependent,
4. removal or quarantine of dead workflow inventory entries after executable/source truth is measured,
5. merge only after draft acceptance criteria are green.

## 13. Next product step after acceptance

After the current exact-head acceptance is green, the next useful work is workflow cleanup and source activation, not new surface area:

```text
existing capability
  -> route
  -> UI
  -> real source
  -> runtime
  -> test
  -> evidence
```

Anything that cannot complete this chain remains secondary, `NOT_CONFIGURED`, `UNAVAILABLE` or explicitly pending.
