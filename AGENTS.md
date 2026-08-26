# AGENTS.md — ShadowOps AI/Coding Agent Contract

This file is the repository-level operating contract for AI assistants, coding agents and autonomous tooling.

If instructions conflict, prefer the safer interpretation and stop rather than inventing state or mutating production.

## 1. Read before editing

Before changing code, read:

- `README.md`
- `docs/AI_CONTEXT.md`
- `docs/PROJECT_STATUS.md`
- `docs/LOCAL_ALL_DEVELOPMENTS.md`
- `docs/SECURITY.md`
- the files/tests directly relevant to the requested change

For OpenCode/Nemotron also read:

- `docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md`
- `.opencode/agent/shadowops-coder.md`

## 2. Canonical development branch

The rolling local integration branch is:

```text
local/all-developments
```

Do not work directly on `main` or `master` unless the human operator explicitly requests it.

Before work:

```bash
git status --short --branch
git fetch origin --prune
git diff --check
```

Do not silently discard local changes. Never use `git reset --hard` or `git clean` as a recovery shortcut unless the human operator explicitly authorizes that exact destructive action.

## 3. Runtime trust levels

```text
4014 = development / preview
4015 = ephemeral production release smoke
4013 = stable production
```

Rules:

- normal development targets 4014;
- certification may use 4015;
- do not mutate, restart, repoint or deploy 4013 during ordinary development;
- promotion to 4013 requires the repository's certification/promotion workflow and explicit operator opt-in;
- do not bypass the promotion certificate, artifact SHA256 or rollback mechanism.

## 4. Truthfulness rules

Never convert absence of evidence into success.

Use truthful states such as:

```text
DISCOVERED
NOT_CONFIGURED
DEGRADED
UNAVAILABLE
BLOCKED
UNKNOWN
```

Only claim `READY`, `PASS`, `CONNECTED`, `ONLINE` or equivalent positive states when the required evidence has actually been checked.

A file existing in the repository is not runtime evidence.
A previous CI run is not evidence that the current HEAD passes.
A documented capability is not proof that the runtime can execute it.
A source reporting a value does not independently prove external truth.

Do not represent synthetic/test data as real data.

## 5. Security and governance invariants

Preserve these invariants:

- fail closed;
- server-side authorization is authoritative;
- server-side privacy filtering is authoritative;
- clients/renderers do not choose authoritative actor, executor, capability, risk, approval or command;
- no arbitrary shell commands from registry/source/client input;
- no arbitrary filesystem paths from registry/source/client input;
- use fixed allowlists and canonical roots for local source paths;
- no secrets/tokens/raw private data in Git, API responses, UI, logs or fixtures;
- approval-required actions must use the approval path;
- privacy checks must not be bypassed;
- relevant mutation/execution decisions must be auditable;
- unknown executor/capability/runtime binding fails closed;
- local AI output is advisory, never authoritative.

## 6. Do not create parallel architecture

Reuse existing canonical responsibilities before adding new modules:

- Project Catalog -> projects and project truthfulness
- Source Registry/adapters -> source discovery/ingest boundaries
- Workflow Registry -> canonical workflows
- Capability Registry -> executable capabilities
- Risk Policy -> risk classification
- Approval Store/Governance Gate -> approvals and governed execution
- Audit -> append-only decision/action evidence
- MCP gateway -> read-only runtime access for coding/AI tooling

Do not create a second registry, second risk model, second approval store or second runtime-control path just to solve a local issue.

## 7. State axes are separate

Do not collapse different semantic axes into one enum.

Examples:

Operational state:
```text
READY / DEGRADED / UNAVAILABLE
```

Lifecycle/catalog state:
```text
DISCOVERED / BLOCKED / ARCHIVED
```

Evidence state:
```text
FACT / DERIVED / INFERRED / CANDIDATE / CONFIRMED
```

Risk state:
```text
L0 / L1 / L2 / L3
```

If a UI needs simpler labels, map them at presentation time rather than changing core semantics.

## 8. Workflow discipline

Canonical workflow IDs use:

```text
so:wf:v1:<slug>
```

Before adding a workflow:

1. prove it is not a duplicate of an existing workflow/service/subcomponent;
2. define executor, capability, risk, runtime binding, inputs, outputs, approval and evidence semantics;
3. validate against the existing agent/workflow contract;
4. add negative/fail-closed tests;
5. do not mark an external runtime READY without runtime evidence.

Subcomponents such as watchers/verifiers/request processors should not automatically become independent top-level workflows.

## 9. Local services and systemd

Discovery is not authorization.

A discovered systemd unit/script may be shown as metadata without becoming actionable.

Do not add discovered services to start/stop/restart allowlists unless explicitly justified and reviewed.

Coding agents must not invoke `sudo`, `systemctl`, deployment workflows or productive external actions during ordinary implementation/testing.

## 10. MCP discipline

The ShadowOps MCP gateway is read-only.

Do not expose write routes or generic URL forwarding.
Do not refactor the gateway into an execution surface.
Do not pass tokens in URLs.
Keep upstream access loopback by default.

If MCP tests pass, stop modifying MCP unless the active task is specifically about MCP.

## 11. Test cadence

After a relevant change, run the smallest meaningful test first, then broaden.

Typical order:

```bash
git diff --check
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test <target tests>
MIX_ENV=test mix test
mix credo --strict
```

For production/security work also run the relevant repository gates, including as applicable:

```text
Dialyzer
Sobelow
Workflow Registry validation
Workflow ID validation
Hex audit
Project Catalog / Production Acceptance
MCP tests
Local coder contract
Production release build
4015 smoke
```

Do not call a gate PASS if it did not run on the current HEAD.

## 12. Current strategic rule

No new feature breadth until the existing product is proven.

Priority:

1. governance correctness;
2. certification/release correctness;
3. a small number of real authorized sources;
4. one real end-to-end use case;
5. only then new feature families.

See `docs/PROJECT_STATUS.md` for the dated priority snapshot.

## 13. Expected final report from an AI change

End implementation work with a compact evidence report:

```text
BRANCH=
HEAD=
WORKTREE=

CHANGE_SCOPE=
FILES_CHANGED=

FORMAT=
COMPILE=
TARGET_TESTS=
FULL_TESTS=
CREDO=
DIALYZER=
SOBELOW=
REGISTRY=
WORKFLOW_IDS=
HEX_AUDIT=
PRODUCTION_ACCEPTANCE=
MCP_TESTS=

4013_MUTATED=NO
DEPLOY_TRIGGERED=NO
MAIN_CHANGED=NO

BLOCKERS=
FINAL_STATUS=PASS|DEGRADED|BLOCKED
```

Use `NOT_RUN` where a gate was not required or not executed. Do not hide skipped checks behind PASS.
