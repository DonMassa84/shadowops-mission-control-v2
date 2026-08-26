# OpenCode / Nemotron deterministic execution handoff

This file is the canonical local task contract for OpenCode on `local/all-developments`.

## Objective

Finish ShadowOps production hardening in small, evidence-backed steps. Do not rediscover or redesign the project. Do not add feature breadth.

## Non-negotiable boundaries

- Work only in the current `local/all-developments` worktree.
- Never edit `main` or `master`.
- Never push, merge, rebase, reset, clean, deploy, restart systemd, mutate port 4013, or trigger productive GitHub Actions.
- Port 4013 is stable production and must remain untouched.
- Port 4014 is development/preview.
- Port 4015 is certification smoke only.
- The runtime MCP is read-only evidence infrastructure.
- Missing evidence stays `NOT_CONFIGURED`, `UNAVAILABLE`, `DEGRADED`, or `UNKNOWN`; never invent `READY`.
- Never expose secrets, tokens, message bodies, raw private data, browser cookies, or implicit sessions.
- Never write outside the current repository worktree through edit/write tools.
- Never create report/plan/scratch/example files during this task. The completion report is text on stdout only.

## Editing discipline for Nemotron

1. Never replace an existing source file wholesale with `cat > file`, heredoc, generated rewrite, or copy-paste reconstruction unless the task explicitly says the entire file is disposable.
2. For existing files, inspect the current file first and make the smallest targeted edit.
3. Do not duplicate constants, functions, modules, path maps, configuration blocks, or imports.
4. After each file edit, run the smallest relevant syntax/targeted test before touching another file.
5. If a test fails twice for different reasons after your own edits, STOP, restore only your last touched file from the pre-edit backup or Git diff, and report the failure. Do not enter a rewrite loop.
6. Never change a passing subsystem to make an unrelated failing test green.
7. Do not refactor while fixing a security gate. Fix only the verified defect.
8. Do not create `execution_report.md`, `report.md`, `notes.md`, `plan.md`, `handoff/*`, or equivalent artifacts.
9. Do not attempt placeholder/example paths such as `/path/to/your/...`, `/home/user/...`, or `/tmp/example/...`.
10. If an edit/write tool requests external-directory permission, reject that write and continue only inside the allowed repository files. Do not ask for a broader permission.

## Canonical truths already proven

### Runtime MCP

`ops/mcp/shadowops_runtime_mcp.py` on `origin/local/all-developments` is canonical and passing in repository CI. It already has:

- `SENSITIVE_KEY` for sensitive dictionary keys,
- `SENSITIVE_VALUE_PATTERNS` for sensitive string values,
- recursive `_sanitize()` handling dict/list/string values,
- fixed read-only endpoint maps,
- URL-encoded detail identifiers,
- write-route rejection,
- loopback-only upstream by default,
- no exposed workflow/service/node mutation tools.

Do **not** rewrite or refactor this file during the current P0 task. If it differs locally from `origin/local/all-developments`, the preflight must restore only this file after backing it up.

### Static security gates

The repository diagnostic workflow has already demonstrated on the canonical branch state:

- Compile = PASS
- full Credo strict = PASS
- Dialyzer = PASS
- Sobelow = PASS

Do not spend time re-implementing these systems unless a new change causes a regression.

### Branch topology

`local/all-developments` already contains `hardening/production-ready-2026-08-25` in full. There is no hardening-branch merge task.

### Approval TTL

Approval expiry already exists (`expires_at`, `expired?/1`, `EXPIRED`). Do not add a second TTL system.

### Correlation IDs

`ShadowOpsCore.Correlation` already exists and Approval/Run/Audit structures already carry correlation IDs in multiple paths. Do not create a second correlation mechanism.

### Risk vocabulary

The authoritative core risk vocabulary is `L0`, `L1`, `L2`, `L3` in `ShadowOpsCore.RiskPolicy`. Do not introduce another operational risk enum.

## CURRENT TASK — P0: atomic single-use approval consumption

This is the only implementation task until its acceptance criteria pass.

### Verified current defect

Current code authorizes approval-required actions through `ApprovalStore.validate(...)`. `ApprovalStore.consume(id)` is only an alias for `get(id)` and does not persist a consumed state. Therefore an approved authorization can be replayed.

### Required behavior

1. Privacy validation must succeed **before** an approval is consumed.
2. A valid approval-required authorization must atomically transition the approval from `APPROVED` to `CONSUMED`.
3. Persist `consumed_at` and `consumed_by`.
4. Consumption must match the exact `action/capability`, `resource`, and `risk`.
5. A second consumption attempt must fail closed.
6. Wrong action, resource, or risk must not consume the approval.
7. Expired, pending, rejected, or already consumed approvals must not consume.
8. PrivacyGate failure must leave an approved approval still `APPROVED` and reusable for a later valid request.
9. Two concurrent consume attempts against the same approval must yield at most one success.
10. Successful consumption must append an `approval_consumed` audit event with approval id, action, risk, correlation id, and actor metadata.
11. The append-only approval store and audit hash chain must remain valid.

## Allowed implementation surface

Inspect first; modify only where required:

- `apps/shadowops_core/lib/shadow_ops_core/approval.ex`
- `apps/shadowops_core/lib/shadow_ops_core/approval_store.ex`
- `apps/shadowops_core/lib/shadow_ops_core/governance_gate.ex`
- `apps/shadowops_core/lib/shadow_ops_core/audit.ex`
- `apps/shadowops_core/test/durable_governance_test.exs`
- optionally one new focused test file under `apps/shadowops_core/test/` whose filename contains `approval` and ends in `_test.exs`

Do not change unrelated adapters, UI, MCP, workflow registry, Project Catalog, source registry, release scripts, systemd integration, docs, handoff files, or reports for this task.

## Intended implementation shape

Use the existing append-only transaction model rather than inventing another store.

### `Approval`

Add state data fields only if not already present:

- `consumed_at`
- `consumed_by`

Add a narrow transition helper such as `consume/2` that permits only `APPROVED -> CONSUMED`, rejects expired approvals, requires a valid non-empty actor, and rejects all other states.

Do not weaken `evaluate/4` matching of action/resource/risk.

### `ApprovalStore`

Replace the misleading no-op `consume(id) -> get(id)` behavior with one atomic transaction API, e.g.:

`consume(id, action, resource, risk_level, actor)`

Inside the existing `transact` lock:

1. load current approval,
2. validate current approval against action/resource/risk,
3. transition `APPROVED -> CONSUMED`,
4. record `:approval_consumed` in Audit,
5. append the consumed approval record,
6. publish an approval-consumed event if the existing EventBus contract supports it,
7. return the consumed record.

Any validation/transition/audit/append failure must return an error and must not report successful consumption.

### `GovernanceGate`

For approval-required capabilities, enforce this ordering:

`actor -> capability -> policy -> policy audit -> PrivacyGate -> atomic approval consume -> authorization result`

The important invariant is: **PrivacyGate failure must happen before the approval is consumed.**

For capabilities that do not require approval, PrivacyGate still applies before authorization succeeds.

### `Audit`

Add `:approval_consumed` to the canonical audit event types if absent. Reuse the existing redaction and hash-chain behavior.

## Required tests before broad suite

Add/adjust tests to prove all of these, not just happy path:

1. approved approval consumes once and persists `CONSUMED`, `consumed_at`, `consumed_by`;
2. second consume is blocked;
3. wrong action leaves state `APPROVED`;
4. wrong resource leaves state `APPROVED`;
5. wrong risk leaves state `APPROVED`;
6. expired approval cannot consume;
7. rejected approval cannot consume;
8. PrivacyGate failure leaves state `APPROVED`;
9. two concurrent consume attempts yield exactly one success and one failure;
10. audit contains `approval_consumed` and `Audit.verify()` remains valid.

## Exact work sequence

Before editing:

```bash
bash scripts/opencode-preflight.sh
```

Then:

```bash
git status --short --branch
git diff --check
```

Inspect the five allowed implementation files. Do not edit yet until you can state where the current no-op/replay behavior occurs.

Edit one file at a time.

After `approval.ex` / `approval_store.ex` changes:

```bash
mix format apps/shadowops_core/lib/shadow_ops_core/approval.ex apps/shadowops_core/lib/shadow_ops_core/approval_store.ex
mix compile --warnings-as-errors
MIX_ENV=test mix test apps/shadowops_core/test/durable_governance_test.exs
```

After GovernanceGate/Audit changes:

```bash
mix format apps/shadowops_core/lib/shadow_ops_core/governance_gate.ex apps/shadowops_core/lib/shadow_ops_core/audit.ex
mix compile --warnings-as-errors
MIX_ENV=test mix test apps/shadowops_core/test/durable_governance_test.exs
```

After all focused tests pass:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test --seed 12345
mix credo --strict
mix dialyzer
mix sobelow --exit
mix shadowops.registry validate
mix shadowops.workflow_ids.validate
mix hex.audit
git diff --check
```

Do not run promotion, systemd, deployment, or port-4013 commands.

## STOP conditions

STOP immediately and report without further editing if any of these occurs:

- current branch is `main` or `master`;
- unresolved Git conflict/rebase/cherry-pick state;
- the canonical MCP file differs after preflight recovery;
- a required existing function/module cannot be found;
- an edit would require changing files outside the allowed implementation surface;
- a security test is made green only by deleting/weakening the assertion;
- the same focused test still fails after two distinct fixes;
- `mix.lock` changes unexpectedly;
- any secret/private raw data appears in output or diff;
- runtime/systemd mutation would be required;
- an external-directory write permission is requested;
- a report/scratch/example file would be needed.

## Completion report — exact format

Return this block as text on stdout. Do not write it to a file. Do not write prose before this block.

```text
OPENCODE_P0_APPROVAL_SINGLE_USE_RESULT
BRANCH=
HEAD=
WORKTREE=
MCP_CANONICAL=

PRIVACY_BEFORE_CONSUME=
APPROVED_TO_CONSUMED=
CONSUMED_AT=
CONSUMED_BY=
SECOND_CONSUME_BLOCKED=
WRONG_ACTION_NOT_CONSUMED=
WRONG_RESOURCE_NOT_CONSUMED=
WRONG_RISK_NOT_CONSUMED=
EXPIRED_NOT_CONSUMED=
REJECTED_NOT_CONSUMED=
PRIVACY_FAILURE_NOT_CONSUMED=
CONCURRENT_SINGLE_WINNER=
APPROVAL_CONSUMED_AUDIT=
AUDIT_CHAIN=

TARGET_TESTS=
FULL_TESTS=
FORMAT=
COMPILE=
CREDO=
DIALYZER=
SOBELOW=
REGISTRY=
WORKFLOW_IDS=
HEX_AUDIT=
DIFF_CHECK=

MAIN_CHANGED=NO
RUNTIME_4013_CHANGED=NO
DEPLOY_TRIGGERED=NO
FINAL_STATUS=
```

`FINAL_STATUS=PASS` is allowed only if every P0 invariant and all listed gates are PASS. Otherwise use `BLOCKED` or `FAIL` with the exact failing field.
