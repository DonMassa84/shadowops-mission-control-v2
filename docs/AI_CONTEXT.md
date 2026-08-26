# ShadowOps AI Context

Purpose: give future AI systems enough durable context to reason about this repository without relying on a previous chat session.

This document describes concepts and invariants. For time-sensitive status, use `docs/PROJECT_STATUS.md` and verify it against Git/CI/runtime before acting.

## 1. Product identity

ShadowOps Mission Control V2 is a local-first operations and decision-support control plane.

It combines:

- local infrastructure/runtime visibility;
- project and workflow inventory;
- controlled automation;
- source/data integration;
- canonical entities and relationships;
- evidence/provenance;
- governance, approvals and audit;
- AI-assisted tooling with remote-only model execution;
- decision-oriented Mission Control views.

It should not become an unrestricted autonomous agent or generic shell executor.

## 2. Core architecture

Canonical conceptual flow:

```text
Sources
  -> bounded ingest
  -> normalization
  -> canonical records
  -> entity resolution
  -> ontology objects / relationships
  -> timeline
  -> signals
  -> decision views
  -> governed actions
```

Three conceptual planes:

### Data Plane

Responsible for:

- source adapters;
- privacy-bounded ingestion;
- canonical records;
- source provenance;
- entity resolution;
- relationships;
- timeline/signals.

### Control Plane

Responsible for:

- workflow registry;
- capability registry;
- risk policy;
- privacy policy;
- approval lifecycle;
- execution boundaries;
- audit/evidence;
- runtime/service controls.

### Decision Plane

Responsible for:

- Mission Control summaries;
- prioritization;
- decision support;
- user-visible proposed actions;
- explanation/evidence links.

The Decision Plane must not bypass the Control Plane.

## 3. Truthfulness model

ShadowOps distinguishes knowledge, lifecycle and operational readiness.

Do not collapse these axes.

### Evidence axis

```text
FACT
DERIVED
INFERRED
CANDIDATE
CONFIRMED
```

`FACT` means the configured source reported the value. It does not mean the value was independently verified.

### Lifecycle/catalog axis

Examples:

```text
DISCOVERED
NOT_CONFIGURED
BLOCKED
ARCHIVED
```

### Operational axis

Examples:

```text
READY
DEGRADED
UNAVAILABLE
FAILED
```

Positive operational claims require actual evidence.

For real source/project readiness, prefer explicit fields such as:

```text
real_data=true
synthetic=false
reachable=true
```

## 4. Source integration contract

A source adapter must be bounded and explicit.

Preferred properties:

- fixed source identity;
- fixed or canonicalized import roots;
- no arbitrary client-provided filesystem paths;
- no arbitrary URLs unless explicitly designed/allowlisted;
- metadata-only where possible;
- raw secrets/private bodies excluded from normalized records;
- source provenance preserved;
- missing configuration -> `NOT_CONFIGURED` rather than success.

Known source families include Gmail, Google Calendar, Google Contacts, Documents metadata, GitHub and ChatGPT/local-export discovery. Availability varies by local configuration and must be checked at runtime.

## 5. Project Catalog

The Project Catalog tracks known ShadowOps-related projects/domains.

Stable project identities should be deterministic. Historical/known IDs include:

```text
shadowops:mission-control-v2
shadowops:data-fabric
shadowops:ontology-v3
shadowops:electron-mission-control   # historical name; review before treating as canonical desktop scope
shadowops:workflow-federation
shadowops:whatsapp-agent
shadowops:facebook-analytics
shadowops:messenger
shadowops:telegram-controller
shadowops:local-ai                   # historical catalog identity; do not infer permission to execute local AI models
shadowops:i7-control
shadowops:knowledge
shadowops:evidence
shadowops:career
shadowops:backups
shadowops:reporting
shadowops:opencode-standard
ihk:zero-trust-project
chatgpt:local-project
```

Important: known project != READY project.

ChatGPT remains `NOT_CONFIGURED` unless a real authorized local export is actually found and parsed.

## 6. Workflow system

Canonical workflow IDs use:

```text
so:wf:v1:<slug>
```

The established canonical set historically contains nine workflows:

```text
finanzabgleich
career_email_only
document_ai
repository_quality
finance_quality_gate
agent_state_sync
career_funnel_ihk
daily_digest
shadow_system_overnight_audit
```

Do not assume the count/status is current without reading `config/workflow_registry_v2.yaml` and running the registry validator.

Workflow execution should define/validate at least:

- workflow identity;
- executor/agent identity;
- capability;
- risk level;
- input contract;
- required arguments;
- runtime binding;
- approval requirement;
- result/failure semantics;
- evidence/audit semantics.

Unknown workflow/executor/capability/runtime bindings fail closed.

## 7. Risk and governance

Core execution risk semantics use:

```text
L0 = read-only / low effect
L1 = local state change
L2 = consequential/external action; approval required as defined by policy
L3 = privileged/high-risk action; approval required
```

The exact policy is code, not this prose. Always inspect `RiskPolicy`, capability definitions and tests before changing authorization behavior.

Governance principles:

- server-side policy is authoritative;
- privacy gating precedes sensitive execution;
- approvals must match intended action/resource/risk/actor semantics;
- approval-required execution must be auditable;
- no client-authoritative executor/risk/approval fields;
- approval replay must fail closed.

### Governance review status

The product-release line implements atomic single-use consumption (`APPROVED -> CONSUMED`) with persisted consumer/timestamp fields, replay protection, privacy-before-consumption ordering, audit evidence and concurrency tests. Treat this as closed only on a HEAD whose focused and full tests pass; inspect the current code and CI evidence before relying on it.

## 8. Audit and correlation

ShadowOps uses append-only/audited records for consequential decisions and actions.

Correlation identifiers should connect related HTTP/governance/approval/run/audit activity where implemented.

Never weaken audit correctness to make a workflow pass.

## 9. Runtime and release lifecycle

Trust levels:

```text
4014 = development/preview
4015 = ephemeral production-release smoke
4013 = stable production
```

Canonical rolling integration branch:

```text
local/all-developments
```

Normal lifecycle:

```text
source changes
 -> targeted tests
 -> 4014 preview
 -> full certification
 -> production release artifact
 -> 4015 smoke
 -> certificate + artifact SHA256
 -> explicit operator promotion
 -> 4013
```

4013 is not a development environment.

See `docs/LOCAL_ALL_DEVELOPMENTS.md`.

## 10. AI / coding stack

ShadowOps development remains local-first, but language-model execution for coding agents is explicitly remote-only:

```text
AI_EXECUTION_POLICY=REMOTE_ONLY
```

Canonical coding path:

```text
Remote AI provider/model
 -> OpenCode
 -> guarded shadowops-coder agent
 -> read-only local ShadowOps MCP
```

The repository must not configure local Ollama/LM Studio/llama.cpp model execution for coding tasks, must not silently fall back to local AI, and must require an explicit remote `provider/model` identifier for `scripts/shadowops-coder.sh`.

The coder is expected to be restricted from destructive Git operations, production deployment, `systemctl` mutation and direct stable-runtime changes.

The MCP gateway is local and read-only; it exposes a fixed API view set rather than generic URL forwarding. A local MCP process is not a local AI model and is allowed by the remote-only AI policy.

See `docs/REMOTE_AI_POLICY.md`.

## 11. Local integration discovery

Local host discovery may find services/scripts such as:

- Bot Gateway;
- System Healer;
- Documentation Factory;
- Voice Agent;
- Research Agent;
- Moving Material workflows;
- GitHub Actions/automation definitions.

Discovery alone does not grant execution capability.

Prefer a metadata-only `DISCOVERED` candidate until runtime binding, security policy and evidence exist.

Do not turn subcomponents (watchers, verifiers, request processors, daily helpers) into separate top-level workflows without a clear domain reason.

## 12. Desktop/UI

Phoenix/LiveView is the canonical control plane/UI backend.

A desktop client, where present, should be a thin shell over the canonical Phoenix control plane, not an independent governance/execution implementation.

Historical catalog naming may reference `electron-mission-control`; verify the current desktop implementation and rename/archive stale catalog identities rather than assuming a parallel Electron product exists.

## 13. Security boundaries

Review these attack classes for relevant changes:

- authorization bypass;
- confused deputy;
- approval replay/staleness;
- TOCTOU;
- path traversal;
- symlink escape;
- shell/argument injection;
- SSRF for network adapters;
- secret leakage;
- unsafe MCP expansion;
- unsafe systemd integration;
- rollback failure.

A coding agent finding a possible issue should add a focused regression test before broad refactoring.

## 14. Production gates

Production readiness is evidence, not intent.

Expected gates include, where applicable:

```text
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test
mix credo --strict
Dialyzer
Sobelow
Workflow Registry validation
Workflow ID validation
mix hex.audit
git diff --check
Project Catalog / Production Acceptance
MCP tests
Local coder contract
Production release build
4015 release smoke
```

Never copy a previous PASS into a current report without re-running or retrieving evidence for the current HEAD.

## 15. Product strategy

The architecture is intentionally ahead of some real integrations. Do not respond by adding more feature families.

Preferred sequence:

1. close security/governance correctness gaps;
2. prove certification/promotion/rollback;
3. connect 3–5 high-value authorized sources, starting with the easiest reliable end-to-end source;
4. prove one complete Source -> Entity/Timeline -> Signal -> Decision -> Approval -> Action -> Audit path;
5. expand only after the existing value chain is measurable.

## 16. How a future AI should begin

Run/read in this order:

```text
1. git status / branch / HEAD
2. README.md
3. AGENTS.md
4. docs/REMOTE_AI_POLICY.md
5. docs/PROJECT_STATUS.md
6. docs/LOCAL_ALL_DEVELOPMENTS.md
7. relevant implementation + tests
8. current CI/runtime evidence
```

Then state explicitly which facts are:

```text
VERIFIED_CURRENT
VERIFIED_HISTORICAL
DOCUMENTED_ONLY
UNKNOWN
```

This prevents stale documentation or previous-chat claims from becoming fake runtime truth.
