# Workflow discovery inventory semantics — 2026-08-27

## Beschreibung

A local Shadowmaker workflow-discovery index reported the following inventory:

```text
TOTAL_RECORDS=3262
VERIFIED=0
VALIDATED_STATIC=1441
DOCUMENTATION=1609
NEEDS_REVIEW=204
BLOCKED_SECRET=8
```

These records are discovery artifacts. They are **not** equivalent to executable or production-ready ShadowOps workflows.

## Decision

ShadowOps keeps the existing canonical workflow registry as the source of truth for executable workflow definitions.

The 3262 discovered artifacts are integrated only as a discovery/inventory source. They must not be copied wholesale into `workflow_registry_v2.yaml` and must not create a second workflow registry.

Canonical execution truth and discovery breadth remain separate.

## Maturity model

Discovered artifacts follow this lifecycle:

```text
DISCOVERED
  -> STRUCTURE_VALIDATED
  -> RUNTIME_VERIFIED
  -> REAL_DATA
  -> CONNECTED
  -> READY
```

`VALIDATED_STATIC` means only that the artifact passed bounded static inspection. It does not imply runtime execution, connectivity, readiness, safety for mutation, or production verification.

`DOCUMENTATION` remains reference material.

`NEEDS_REVIEW` remains non-ready until reviewed.

`BLOCKED_SECRET` remains excluded from execution and public projection.

## Source-truth projection

The inventory should project approximately as:

```text
id=workflow_discovery
status=AVAILABLE
health=HEALTHY
source_type=LOCAL_DISCOVERY_INDEX
real_data=true
synthetic=false
reachable=true
record_count=3262
integration_mode=INVENTORY_ONLY
verified_count=0
execution_ready=false
```

The following representation is forbidden:

```text
3262_WORKFLOWS=VERIFIED
```

The correct representation is:

```text
3262_ARTIFACTS=DISCOVERED
0_ARTIFACTS=RUNTIME_VERIFIED
CANONICAL_WORKFLOWS=SEPARATE
```

## Privacy and secret handling

The discovery inventory may internally contain absolute local paths and references to configuration files such as `.env` files.

These are internal metadata only.

API and UI projections must not expose private absolute paths, secret values, tokens, passwords, cookies, authentication databases, or environment-file contents.

Environment files and similarly sensitive artifacts must never become executable solely because they were discovered or statically classified.

The public bounded projection may expose only non-sensitive fields such as:

```text
id
name
domain
kind
status
health
source_type
real_data
synthetic
reachable
record_count
integration_mode
last_update
reason
```

## Architecture invariant

```text
LOCAL DISCOVERY
  -> CORRELATE WITH EXISTING IDS
  -> VALIDATE STRUCTURE
  -> VERIFY RUNTIME
  -> PROJECT THROUGH EXISTING ADAPTERS
  -> TEST
  -> ONLY THEN READY
```

No duplicate registry, duplicate execution engine, or duplicate business logic may be introduced.

## Certification impact

The discovery inventory does not block ShadowOps application certification by itself.

Application certification and workflow-discovery maturity are separate dimensions:

```text
SHADOWOPS_APPLICATION_CERTIFICATION != WORKFLOW_ARTIFACT_RUNTIME_VERIFICATION
```

A certified ShadowOps release may truthfully expose a discovery inventory containing zero runtime-verified artifacts as long as the UI/API does not falsely label those artifacts READY or VERIFIED.

## Regression rules

1. Never infer READY from file presence.
2. Never infer VERIFIED from static validation.
3. Never automatically promote discovered artifacts into the canonical registry.
4. Never expose private local paths or secret values through API/UI.
5. Never execute `BLOCKED_SECRET` artifacts.
6. Correlate discovered items to stable canonical IDs before considering runtime integration.
7. Runtime verification must be explicit and evidence-backed.
