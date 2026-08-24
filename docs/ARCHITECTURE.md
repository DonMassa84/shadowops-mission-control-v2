# ShadowOps Mission Control V2

## Scope

Phoenix/LiveView operations console for aggregated ShadowOps state.

## Namespaces

- `/mission/*` — Mission Control V2
- `/control/*` — low-level operator diagnostics
- `/display/i7` — existing i7 display compatibility path

## Principles

- Reuse before rebuild
- Read-first, mutate-rare
- Fail-closed
- No fake state
- No secrets in HTML/API/logs/tests/Git
- Runtime state stays local
- Source definitions may be versioned
- Writes use existing governance/approval/audit paths
