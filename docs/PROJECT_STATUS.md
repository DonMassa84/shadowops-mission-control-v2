# ShadowOps Project Status

**Snapshot date:** 2026-08-26

This is a dated orientation document, not a live health endpoint. Future humans/AIs must verify the current branch, HEAD, CI and runtime before relying on any status below.

## How to interpret this file

Use these confidence labels:

- `VERIFIED_CURRENT` — directly checked against the branch/code at snapshot time.
- `VERIFIED_HISTORICAL` — previously proven, but not automatically valid for a later HEAD.
- `DOCUMENTED` — implemented/described in repository docs/scripts, runtime proof may still be required.
- `OPEN` — known unresolved item.
- `UNKNOWN` — insufficient evidence.

## Canonical development line

```text
branch: local/all-developments
code baseline before the documentation-only commits in this snapshot:
8082343d412d7631f27a0a10f6be46fccfec182f
```

`local/all-developments` is the rolling local integration candidate.

Do not resume development on the older `chatgpt/phase-b-c-integration-2026-08-26` branch. That branch is an ancestor of the rolling branch and was already materially behind it during this snapshot.

## Runtime lifecycle

`DOCUMENTED` and repo-implemented:

```text
4014 = development / preview
4015 = isolated production release smoke
4013 = stable production
```

Entry point:

```bash
scripts/shadowops-local.sh status
scripts/shadowops-local.sh setup
scripts/shadowops-local.sh certify
SHADOWOPS_PROMOTE_STABLE=YES scripts/shadowops-local.sh promote
```

Promotion requires a matching certificate/artifact hash and includes rollback logic. A real successful promotion/rollback drill must still be evidenced before treating the release lifecycle as operationally proven.

## Engineering baseline

`VERIFIED_HISTORICAL` on recent predecessor/current-development commits:

```text
ShadowOps Core       110 tests
Workflow Engine       32 tests
Agent Runtime          9 tests
ShadowOps Web          74 tests
TOTAL                 225 tests
```

A previous full test run reported 225 passing / 0 failing.

A previous static diagnostic run on the rolling development line reported:

```text
COMPILE=PASS
CREDO_STRICT=PASS
DIALYZER=PASS
SOBELOW=PASS
```

These are historical evidence only. Any code change after those runs requires relevant re-validation.

## MCP state

`VERIFIED_CURRENT` code contract:

- read-only MCP gateway exists under `ops/mcp/`;
- fixed status/collection/detail API maps are used;
- arbitrary generic URL forwarding is not exposed;
- tokens remain in authorization headers rather than URLs;
- remote upstream is fail-closed unless explicitly allowed;
- sensitive keys/known token patterns are redacted;
- write/action routes are rejected.

At code baseline `8082343...`, the write-route regex was tightened to reject explicit action suffixes including:

```text
start
stop
restart
pause
resume
run
approve
reject
```

Do not reopen/refactor MCP during unrelated tasks if its contract tests are green.

## Project Catalog / truthfulness

`DOCUMENTED` / implemented:

- metadata-only project catalog seeding;
- deterministic known-project identities;
- truthfulness fields such as `real_data`, `synthetic`, `reachable`;
- fail-closed `NOT_CONFIGURED` behavior for missing source configuration.

Known design hardening opportunity:

- positive `READY` semantics should remain explicitly evidence-backed; inspect the current `Truthfulness` and Project Catalog normalization before modifying this.

## Workflow registry

`VERIFIED_HISTORICAL` canonical registry scope:

```text
9 canonical workflows
immutable ID pattern: so:wf:v1:<slug>
```

The established workflow names are:

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

The current registry file and validator are authoritative; do not assume this count forever.

Generic agent/workflow contracts were added to validate executor/capability/risk/input/runtime/approval/evidence semantics. Re-run registry tests before claiming 9/9 on a later HEAD.

## Local integration discovery

`DOCUMENTED` candidate families include:

```text
Bot Gateway
System Healer
Documentation Factory
Voice Agent
Research Agent
Moving Material Workflow
```

These are discovery candidates, not automatically executable workflows.

Rule:

```text
artifact absent  -> NOT_CONFIGURED
artifact present -> DISCOVERED / evidence-backed candidate
DISCOVERED       != READY
```

Do not add discovered services to runtime action allowlists without explicit review.

## Real source coverage

This remains the primary product gap.

Known/target source families:

```text
GitHub
Gmail
Google Calendar
Google Contacts
Documents metadata
ChatGPT local export
```

At snapshot time, the ChatGPT source was intentionally fail-closed when no authorized local export existed.

Do not mark any source connected/ready because a connector exists in code or because an external AI session can access that service.

The ShadowOps runtime requires its own authorized adapter/configuration/evidence.

## P0 — Governance correctness

`IMPLEMENTED_PENDING_CURRENT_HEAD_CI` on the product-release line.

`ApprovalStore.consume/5`, `Approval.consume/2` and the canonical event/audit path now implement terminal `APPROVED -> CONSUMED` semantics. Focused tests cover:

```text
PrivacyGate succeeds before consumption
APPROVED -> CONSUMED is atomic
consumed_at is persisted
consumed_by is persisted
same approval cannot be consumed twice
wrong action/resource/risk does not consume
expired/rejected approvals cannot consume
privacy failure does not burn approval
concurrent consume attempts yield at most one success
approval_consumed is audited
audit chain remains valid
```

The implementation must still be treated as unverified on any new HEAD until the focused approval suite and the full quality gate pass for that exact commit.

## P0/P1 — Production proof still required

Before claiming `PRODUCTION_READY=YES`, obtain current evidence for:

1. governance/single-use approval correctness;
2. complete `scripts/shadowops-local.sh certify` success;
3. successful 4015 release smoke for the exact candidate;
4. certified artifact + SHA256 creation;
5. deliberate rollback drill or equivalent verified rollback evidence;
6. at least one real authorized source end-to-end;
7. one complete Source -> Entity/Timeline -> Signal -> Decision -> Approval -> Action -> Audit use case;
8. controlled promotion to 4013 only after certification.

## Recommended first real E2E source

GitHub is a good first engineering proof because repository/commit/CI metadata can demonstrate the full data path without first solving Google OAuth.

Example target:

```text
GitHub event
 -> bounded ingest
 -> normalization
 -> project/entity association
 -> timeline event
 -> signal
 -> Mission Control decision
 -> proposed governed workflow action
 -> approval
 -> action
 -> audit
```

After the architecture is proven, Gmail/Calendar/Contacts can provide higher-value personal decision signals.

## Feature freeze

Do not add new feature families while the P0/production-proof items remain open.

Specifically avoid adding more:

- top-level workflow families;
- messaging integrations;
- agent types;
- alternate control planes;
- ontology layers;
- dashboard families;

unless required to close a proven current use case.

## Historical/parallel components to review rather than blindly expand

- historical `shadowops:electron-mission-control` catalog identity — verify current desktop/Tauri scope before treating it as a separate product;
- messaging integrations without real runtime evidence — keep frozen/discovered rather than pretending readiness;
- ontology/federation breadth — preserve existing code, but do not expand before an end-to-end value path is proven.

## Next-action order for a future AI

```text
1. Verify current branch/HEAD/worktree.
2. Read AGENTS.md and docs/AI_CONTEXT.md.
3. Inspect whether atomic approval consumption is still open.
4. Run targeted governance tests.
5. Run relevant full quality gates.
6. Prove local certification on 4014 -> 4015.
7. Connect one real authorized source.
8. Prove one end-to-end governed use case.
9. Only then consider production promotion or new feature scope.
```

## Required status-report discipline

A future report should distinguish:

```text
CURRENT_HEAD_PASS
HISTORICAL_PASS
NOT_RUN
NOT_CONFIGURED
BLOCKED
UNKNOWN
```

Never summarize all of these as `PASS`.
