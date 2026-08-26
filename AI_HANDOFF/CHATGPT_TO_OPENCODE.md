# ChatGPT → OpenCode

TASK_ID=shadowops-local-fabric-2026-08-26-004
STATUS=READY
REPO=DonMassa84/shadowops-mission-control-v2
BASE_REF=feat/chatgpt-source-evidence
WORK_BRANCH=automation/opencode-work
HANDOFF_BRANCH=ai-handoff/state
ISSUE=8
PR=7
REVIEWED_RESULT_SHA=NONE

## Primary requirement
Connect all useful local ShadowOps capabilities and evidence into one governed Local Fabric while preserving uninterrupted access to the last-known-good stable runtime on port 4013.

Read and obey `AI_HANDOFF/LOCAL_FABRIC_SCOPE.md` before implementation.

## Non-negotiable runtime lanes

### Stable lane
- port `4013`
- last-known-good immutable validated release only
- must remain usable during normal development
- do not develop in its checkout
- do not restart/stop/rebuild it for ordinary development/tests
- preserve stable state/config
- keep current + previous known-good releases and rollback readiness

### Development lane
- dedicated worktree: `~/Projects/shadowops-mission-control-v2-dev`
- branch: `automation/opencode-work`
- port `4014`
- state: `~/.local/state/shadowops-dev`
- separate build/temp/log/config paths
- never bind development to 4013

## Existing architecture to extend, not bypass
Use and consolidate the current primitives where appropriate:
- `ShadowOpsCore.RuntimeSources`
- `ShadowOpsCore.OperationalSources`
- `ShadowOpsCore.ConnectorState`
- `ShadowOpsCore.PrivacyGate`
- `ShadowOpsCore.Truthfulness`
- `ShadowOpsWeb.SourceRegistry`
- `ShadowOpsWeb.IntegrationCatalog`
- existing ProjectCatalog/domain/import evidence

Do not build a second source registry or parallel truth model unless an evidenced architectural gap requires a small compatibility layer.

## Goal
Implement a unified local inventory/evidence plane that discovers and represents everything useful locally without blindly ingesting private raw data.

Target conceptual path:

`Local Source -> Discovery -> Authorization -> PrivacyGate -> Normalization -> Truthfulness -> Audit/Evidence -> Query -> UI`

## Phase 1 — Runtime and safety baseline
1. Record stable 4013 PID/CWD/ExecStart/deployed SHA if derivable.
2. Verify 4013 health/ready and do not mutate it.
3. Preserve any uncommitted local changes before Git/worktree mutations.
4. Create/use isolated dev worktree on `automation/opencode-work`.
5. Record exact candidate SHA and source parity.

## Phase 2 — Local discovery inventory
Create one bounded local inventory model and discovery service. Reuse existing data sources whenever possible.

Inventory these classes when available:

### A. Host / OS
- hostname / OS / kernel metadata
- uptime/load
- CPU model/core count and bounded utilization metadata
- memory/swap totals and bounded current usage
- mounted filesystem capacity/usage
- network interfaces and address/reachability metadata
- listening localhost/service ports with bounded owning process metadata
- GPU/NVIDIA device/driver/VRAM metadata if available

Do not capture packet contents or arbitrary process environment variables.

### B. Services / containers
Reuse existing systemd + Docker discovery.
- user/system services
- Docker containers
- bounded health/state/PID/restart metadata
- retain current mutation allowlist; discovery must not broaden write permissions

### C. Local AI / developer tools
- Ollama installed/reachable
- installed Ollama model metadata: model name/tag/size/modified, no prompts/history
- OpenCode installed/version/availability
- Git, Elixir, Erlang and other project-critical toolchain versions
- ShadowOps stable/dev runtime identities

### D. Nodes
- main Ryzen host as local node
- optional i7 node using current declared host/reachability mechanisms
- do not fake online state
- capabilities only from real probe/config evidence

### E. Git repositories / local projects
Discover repositories only under configurable allowlisted roots, initially sensible user project roots such as `$HOME/Projects` and any already configured ShadowOps project roots.
For each repo expose bounded metadata only:
- path label/basename, not secret-bearing content
- branch
- HEAD SHA
- dirty/clean
- remote host/name when safe
- last commit timestamp
- repo reachable/readable

Do not automatically ingest source-code file contents into the Local Fabric inventory.

### F. Knowledge / file roots
Replace hard-coded-only discovery with configurable allowlisted roots while preserving existing defaults where they are real.
For each root expose by default:
- availability
- file/document count
- type distribution
- last update
- optional evidence hashes
- classification

Do not content-index arbitrary home-directory data.
Content indexing requires an explicit governed importer.

### G. ShadowOps state/evidence
Inventory:
- import evidence manifests
- project/domain manifests
- workflow registry / workflow IDs
- audit/run/approval state presence and counts
- backup artifacts and restore verification state
- release history / stable SHA / previous stable SHA
- evidence directory metadata

Never return secret values or raw audit/private payloads through a general inventory endpoint.

### H. Existing local/provider adapters
Surface truthfully through the same inventory/status model where possible:
- Gmail
- Calendar
- Drive
- GitHub
- ChatGPT project
- WhatsApp
- Telegram
- Obsidian
- Finance
- i7

Important: adapter presence is not READY. Existing import/source evidence rules remain authoritative.

## Phase 3 — Canonical normalized schema
Define one normalized Local Fabric record schema with at least:

```text
id
name
kind
scope
source_type
status
health
discovered
reachable
real_data
synthetic
content_ingested
record_count
last_success_at
classification
capabilities
error_code
error_message
metadata
```

Requirements:
- deterministic IDs
- deterministic sorting
- no duplicate provider/source records
- no secret values
- no raw session/token/cookie values
- no arbitrary environment dump
- fail closed
- positive states require evidence

## Phase 4 — Sensitive-path deny policy
Add a tested deny policy preventing generic automatic ingestion of:
- `~/.ssh`
- browser cookie/session/login databases
- password/keyring stores
- token/credential stores
- shell-history secret material
- arbitrary messenger application databases
- arbitrary raw health/legal/financial content

Purpose-specific existing governed connectors may access scoped data only through their own explicit policy path.

## Phase 5 — API and UI
Expose one read-only Local Fabric surface in Mission Control.

Preferred outcome:
- `/local` or `/sources/local` UI
- corresponding protected read API such as `/api/local` or `/api/sources/local`

Show grouped cards/tables for:
- Host
- Services
- Containers
- AI/models
- Nodes
- Repositories
- Knowledge/file roots
- ShadowOps state/evidence
- Provider/source adapters

UI must visibly distinguish:
- READY
- DEGRADED
- NOT_CONFIGURED
- UNAVAILABLE
- UNKNOWN

Also visibly distinguish:
- discovered metadata
- real source evidence
- content ingested/not ingested

No mutation controls are required in this task.

## Phase 6 — Configuration
Add local-only configuration for allowlisted discovery roots and optional probes.

Requirements:
- defaults are safe and bounded
- config containing local paths may live in ignored local state/config where appropriate
- no secrets committed
- no hard requirement that optional source exists
- avoid machine-specific absolute paths in committed production logic when a configurable root can be used

## Phase 7 — Tests
Add tests for at least:
- normalized schema
- deterministic IDs/order
- missing sources fail closed
- unreadable source fail closed
- sensitive directories are denied
- arbitrary env values are never emitted
- generic repo discovery does not ingest file content
- model discovery does not expose prompts/history
- provider NOT_CONFIGURED is not promoted to READY
- existing service mutation allowlist is not broadened
- stable/dev port isolation remains enforced where testable
- UI renders unavailable/not-configured states without crashing

Run applicable gates:
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- full tests with fixed seed
- Credo strict on changed code
- registry validation
- workflow IDs validation
- dependency audit
- diff check
- production acceptance
- production release build

## Phase 8 — Dev runtime proof
Run candidate only on port 4014 with isolated state.
Verify at minimum:
- health
- ready
- Local Fabric UI
- protected Local Fabric API behavior
- existing core routes still work
- stable 4013 remains running and unchanged

## Phase 9 — No automatic stable promotion yet
For this task, do NOT automatically promote the Local Fabric candidate to 4013 merely because development gates pass.

Report it as `PROMOTION_READY=YES|NO` with exact blocker if NO.
Keep the existing last-known-good stable implementation available.

## Git / publishing
- code changes only on `automation/opencode-work` or a dedicated child branch
- push sanitized code/tests/docs only
- never commit local raw data, state, secrets, exports, tokens, cookies, messages or credentials
- never auto-merge `main`
- update `AI_HANDOFF/OPENCODE_TO_CHATGPT.md` on `ai-handoff/state`
- optionally mirror bounded result in Issue #8

## Result schema
Return at least:

```text
[OPENCODE_RESULT]
TASK_REF=shadowops-local-fabric-2026-08-26-004
BRANCH=
HEAD=
STABLE_SHA=
STABLE_4013=
DEV_4014=
LOCAL_FABRIC_RECORDS=
HOST=
SERVICES=
CONTAINERS=
OLLAMA=
OLLAMA_MODELS=
OPENCODE=
NODES=
REPOSITORIES=
KNOWLEDGE_ROOTS=
SHADOWOPS_STATE=
PROVIDER_SOURCES=
SENSITIVE_DENY_POLICY=
FORMAT=
COMPILE=
TESTS=
CREDO=
REGISTRY=
WORKFLOW_IDS=
HEX_AUDIT=
PRODUCTION_ACCEPTANCE=
RELEASE_BUILD=
LOCAL_UI_HTTP=
LOCAL_API_HTTP_UNAUTH=
PROMOTION_READY=
BLOCKERS=
FINAL_STATUS=PASS|PARTIAL|BLOCKED_<reason>|FAIL
```

## Operating rules
FINISH BEFORE EXPAND.
STABLE WHILE DEVELOPING.
LAST-KNOWN-GOOD ALWAYS AVAILABLE.
LOCAL DATA STAYS LOCAL.
EVIDENCE BEFORE READY.
