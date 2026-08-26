# ADR: Commanded/EventStore versus existing ShadowOps architecture

**Status:** REJECT for Commanded/EventStore adoption; PARTIAL_ADOPT may be evaluated for an internal run state-machine pattern only.

## Decision context

This decision was checked against the current ShadowOps code on branch `feat/mission-control-v2`, based on the hardened code line from `hardening/production-ready-2026-08-25`.

ShadowOps already contains the following relevant primitives:

- `ShadowOpsCore.Audit`: durable append-only local journal with a SHA-256 hash chain and chain verification.
- `ShadowOpsCore.ApprovalStore`: durable approval lifecycle used by governed actions.
- `ShadowOpsCore.CapabilityRegistry` and `ShadowOpsCore.Policy`: canonical capability and policy/risk decisions.
- `ShadowOpsCore.ExecutionService`: the central mutation boundary; controllers and LiveViews must not invoke mutating adapters directly.
- `ShadowOpsCore.CanonicalEvent`: privacy-safe canonical event envelope.
- `ShadowOpsCore.EventBus`: bounded in-memory event bus. Its own module contract explicitly states that durable actions remain in the audit hash chain.
- workflow/run registries and stores used as the current operational read/state model.

The current `ExecutionService` chain is materially:

`Actor/Identity -> CapabilityRegistry -> Policy/Risk -> Approval (when required) -> PrivacyGate -> ExecutionService -> Adapter -> Audit/Events`

HTTP write authentication and the actor-scoped rate limiter sit outside that core mutation boundary and reject requests before controller execution.

## Commanded/EventStore pattern

A full Commanded/EventStore adoption would introduce commands, aggregates, immutable domain events as the primary source of truth, event-store persistence and projections rebuilt from that event history.

## Comparison

| Capability | Existing ShadowOps | Commanded/EventStore equivalent |
|---|---|---|
| Append-only durable history | Yes: hash-chained `Audit` | Event Store |
| Authorization of state changes | Yes: CapabilityRegistry + Policy + Approval + PrivacyGate + ExecutionService | Command handling in aggregate |
| Immutable event envelope | Yes: `CanonicalEvent` | Domain event |
| Event distribution | Yes: bounded in-memory `EventBus` | Event subscriptions |
| Durable event source of truth | No: durable truth remains registry/store state plus audit evidence | Event Store |
| Rebuildable projections | Partial only; current operational records are not reconstructed from an event store | Projections |
| Decision traceability | Yes: approvals, audit and run/evidence records | Aggregate event history |

## Code-backed finding

The current architecture is **not event sourced**. `EventBus` is explicitly bounded and in-memory, while durable actions are recorded in `Audit`. Introducing EventStore as an additional durable source of truth would therefore create a second persistence and consistency model rather than completing an already-partial EventStore design.

That duplication has no demonstrated production requirement in the current system.

## Risks of introducing Commanded/EventStore

1. **Competing sources of truth.** Registry/store state, audit chain and a new event store would all describe overlapping operational facts.
2. **Migration cost.** Existing workflow runs, project-domain records, source registry state and approval state would need aggregate/projection migration or dual-write logic.
3. **Expanded failure surface.** Backup, restore, migrations, monitoring and incident recovery would have to cover another durable subsystem.
4. **Governance ambiguity.** A second command path risks competing with the existing `ExecutionService` mutation boundary.
5. **No proven requirement.** Current requirements are auditability, fail-closed governance, deterministic run state/evidence and read projections; none require event sourcing.

## Decision

**COMMANDED_DECISION=REJECT**

Do not add Commanded or EventStore to ShadowOps Mission Control V2 unless a future evidence-backed requirement proves that replayable event-sourced state is necessary and cannot be met by the existing stores plus audit/evidence model.

## Narrow pattern that may be evaluated separately

**PARTIAL_ADOPT** may be considered for a pure design pattern: model each workflow/service run as an explicit finite-state machine with a documented transition table and invariants.

This must not introduce:

- Commanded,
- EventStore,
- a second workflow engine,
- a second mutation boundary,
- or another durable source of truth.

Any such state-machine change requires its own ADR and regression tests against the existing run lifecycle.

## Evidence used for this ADR

- `apps/shadowops_core/lib/shadow_ops_core/audit.ex`
- `apps/shadowops_core/lib/shadow_ops_core/approval_store.ex`
- `apps/shadowops_core/lib/shadow_ops_core/capability_registry.ex`
- `apps/shadowops_core/lib/shadow_ops_core/execution_service.ex`
- `apps/shadowops_core/lib/shadow_ops_core/canonical_event.ex`
- `apps/shadowops_core/lib/shadow_ops_core/event_bus.ex`

This decision is based on the actual repository code, not solely on the architecture proposal.
