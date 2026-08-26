# ShadowOps Mission Control V2 — Architecture

## Scope

ShadowOps is a local-first Phoenix/LiveView operations and decision-support control plane. It aggregates evidence-backed state from projects, workflows, runtime services, local AI tooling and approved data sources, then exposes governed views/actions.

The control plane is authoritative. Desktop clients, local AI agents and MCP clients are consumers of that control plane, not alternate governance implementations.

## Architectural planes

```text
                   SHADOWOPS
                       |
           +-----------+-----------+
           |                       |
       DATA PLANE              CONTROL PLANE
           |                       |
       Sources                 Governance
       Canonical Data          Privacy
       Entities                Risk Policy
       Relationships           Approvals
       Timeline                Capabilities
       Signals                 Audit
           |                   Execution
           +-----------+-----------+
                       |
                 DECISION PLANE
                       |
                 Mission Control
```

## Data pipeline

```text
Sources
  -> bounded/raw ingest
  -> normalization
  -> canonical records
  -> entity resolution
  -> ontology objects/links
  -> timeline
  -> signals
  -> decision views
  -> governed actions
```

Every transition should preserve provenance and avoid upgrading uncertainty into truth.

## Namespaces / surfaces

- `/mission/*` — Mission Control V2 views where present
- `/control/*` — lower-level operator diagnostics where present
- `/projects*` — project catalog / federated project status
- `/workflows`, `/runs` — workflow/runtime state
- `/services`, `/security`, `/audit`, `/evidence` — operations/security/evidence surfaces
- `/display/i7` — i7 display compatibility path
- `/health`, `/ready` — runtime probes

The actual router is authoritative; documentation is descriptive.

## Canonical responsibilities

### Project Catalog
Tracks known projects/domains and their evidence-backed status. It is not a workflow registry and does not authorize execution.

### Source Registry / Adapters
Defines bounded source identities and import/runtime boundaries. Sources must not accept arbitrary filesystem/network targets by default.

### Workflow Registry
Defines canonical workflows and immutable workflow identity contracts (`so:wf:v1:<slug>`).

### Capability Registry
Defines executable capability identities and allowed executor relationships.

### Risk Policy
Classifies execution risk using the canonical governed execution risk levels (`L0`–`L3`).

### Approval Store / Governance Gate
Controls approval-required execution. Matching, expiration, single-use semantics and auditability are security properties, not UI behavior.

### Audit / Evidence
Records consequential decisions/actions and supporting provenance. Audit must not be bypassed to improve availability.

### MCP Gateway
Provides bounded read-only runtime visibility to AI/coding tooling. It must not evolve into a generic action proxy.

## State model

Do not use one overloaded enum for everything.

Operational state, lifecycle/catalog state and evidence state are orthogonal.

Examples:

```text
Operational: READY / DEGRADED / UNAVAILABLE / FAILED
Lifecycle:   DISCOVERED / NOT_CONFIGURED / BLOCKED / ARCHIVED
Evidence:    FACT / DERIVED / INFERRED / CANDIDATE / CONFIRMED
Risk:        L0 / L1 / L2 / L3
```

Presentation layers may map these axes to simpler UI badges but must not mutate their core meaning.

## Runtime lifecycle

The local lifecycle uses separate trust levels:

```text
4014 = development / preview
4015 = isolated production release smoke
4013 = stable production
```

Normal code changes must not mutate 4013.

See `docs/LOCAL_ALL_DEVELOPMENTS.md` for the certification and promotion contract.

## Security principles

- Reuse before rebuild.
- Read-first, mutate-rare.
- Fail closed.
- No fake state.
- No secrets in HTML/API/logs/tests/Git.
- Runtime state stays local.
- Source definitions may be versioned; raw private runtime data may not.
- Writes use governance/approval/audit paths.
- UI/client input is not authoritative for executor, actor, capability, risk or approval.
- Arbitrary shell commands and arbitrary source paths are not workflow contracts.
- Unknown capability/executor/runtime/source state is not READY.
- Local AI output is advisory only.

## AI/coding-agent boundary

The preferred local AI path is:

```text
Ollama -> OpenCode -> guarded ShadowOps coder -> read-only MCP -> ShadowOps preview (4014)
```

The coding agent may edit/test code within its repository boundary but must not autonomously deploy, change stable 4013, invoke destructive Git recovery or use systemd as an implementation shortcut.

Repository-wide AI rules live in `AGENTS.md`.

## Architectural decision rule

Before introducing a new subsystem, answer:

1. Does an existing canonical responsibility already own this problem?
2. Is the new abstraction required by a proven end-to-end use case?
3. Can the requirement be solved by extending an existing contract instead?
4. Does the change increase the number of independent truth/status/risk models?
5. Can its behavior be proven with targeted negative tests?

If the answer indicates duplication or unproven feature breadth, freeze the feature rather than adding another layer.
