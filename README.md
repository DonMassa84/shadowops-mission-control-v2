# ShadowOps Mission Control V2

Local-first, fail-closed operations and decision-support control plane built with Elixir/Phoenix/LiveView.

ShadowOps is not a generic chatbot and not an unrestricted automation runner. It is a governed control plane for local infrastructure, projects, workflows, evidence, AI tooling and selected personal data sources. Every positive state should be backed by evidence; missing evidence must remain `NOT_CONFIGURED`, `DISCOVERED`, `DEGRADED`, `UNAVAILABLE` or `UNKNOWN` rather than being promoted to `READY`.

## Start here

For humans and coding agents, read these files before changing code:

1. [`AGENTS.md`](AGENTS.md) — non-negotiable repository and safety rules for AI/coding agents.
2. [`docs/AI_CONTEXT.md`](docs/AI_CONTEXT.md) — architecture, terminology, trust boundaries and canonical concepts.
3. [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) — dated status snapshot, verified facts and current priorities.
4. [`docs/LOCAL_ALL_DEVELOPMENTS.md`](docs/LOCAL_ALL_DEVELOPMENTS.md) — local development/certification/promotion lifecycle.
5. [`docs/PRODUCTION.md`](docs/PRODUCTION.md) and [`docs/SECURITY.md`](docs/SECURITY.md) — production and security contracts.
6. [`docs/REMOTE_AI_POLICY.md`](docs/REMOTE_AI_POLICY.md) — canonical remote-only AI execution policy.
7. [`docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md`](docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md) — deterministic OpenCode/Nemotron handoff.

Do not treat documentation as stronger evidence than the repository, CI and runtime. Re-check `git status`, branch/HEAD, tests and runtime before claiming a state is current.

## Architecture

The target data and control flow is:

```text
Sources
  -> bounded/raw ingest
  -> normalization
  -> canonical data
  -> entity resolution
  -> ontology objects + relationships
  -> timeline
  -> signals
  -> decision views
  -> governed actions
```

Conceptually:

```text
                   SHADOWOPS
                       |
           +-----------+-----------+
           |                       |
       DATA PLANE              CONTROL PLANE
           |                       |
       Sources                 Governance
       Canonical Data          Privacy Gate
       Entities                Risk Policy
       Relationships           Approvals
       Timeline                Audit
       Signals                 Execution
           |                       |
           +-----------+-----------+
                       |
                 DECISION PLANE
                       |
                 Mission Control
```

Important design rules:

- local-first and privacy-preserving;
- read-first, mutate-rare;
- fail closed on missing configuration/evidence;
- server-side governance is authoritative;
- the UI/client is never authoritative for actor, executor, capability, risk or approval;
- no free shell-command execution from workflow/source configuration;
- no raw secrets/private source data in Git, HTML, logs or test fixtures;
- source provenance and truthfulness are part of the data model;
- AI suggestions are non-authoritative.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/AI_CONTEXT.md`](docs/AI_CONTEXT.md).

## Canonical local development lifecycle

The rolling integration branch is:

```text
local/all-developments
```

The runtime lifecycle deliberately separates development, certification and stable production:

```text
4014  DEVELOPMENT / PREVIEW
  |
  | full certification
  v
4015  EPHEMERAL RELEASE SMOKE
  |
  | certified artifact + SHA256 + explicit operator promotion
  v
4013  STABLE PRODUCTION
```

`4013` must not be changed just because a development branch is green. Promotion requires the exact certified commit and explicit operator opt-in, with rollback support.

One local entrypoint:

```bash
cd ~/Projects/shadowops-mission-control-v2
git fetch origin --prune
git switch local/all-developments
git pull --ff-only

scripts/shadowops-local.sh status
scripts/shadowops-local.sh setup
scripts/shadowops-local.sh certify
```

Only after certification:

```bash
SHADOWOPS_PROMOTE_STABLE=YES scripts/shadowops-local.sh promote
```

Full details: [`docs/LOCAL_ALL_DEVELOPMENTS.md`](docs/LOCAL_ALL_DEVELOPMENTS.md).

## Remote coding agent

ShadowOps may use OpenCode as a guarded coding-agent shell, but **AI model execution is remote-only**. Local language models are not permitted for coding tasks.

Canonical policy:

```text
AI_EXECUTION_POLICY=REMOTE_ONLY
```

The repository no longer configures local Ollama models or a local AI default. `scripts/shadowops-coder.sh` requires an explicit remote `provider/model` identifier and fails closed if a known local provider such as `ollama/*`, `lmstudio/*` or `llamacpp/*` is selected.

Preferred entrypoint:

```bash
opencode models

SHADOWOPS_CODER_MODEL='provider/model' \
  scripts/shadowops-coder.sh --next
```

The agent must not work directly on `main`/`master`, mutate stable port `4013`, run deployments, use destructive Git commands, or invent evidence. The ShadowOps MCP gateway may remain local because it is a read-only runtime interface, not an AI model.

See [`docs/REMOTE_AI_POLICY.md`](docs/REMOTE_AI_POLICY.md) and [`AGENTS.md`](AGENTS.md).

## Workflow governance

Canonical workflow identifiers use:

```text
so:wf:v1:<slug>
```

The workflow registry, capability registry, risk policy, approval policy and audit trail are separate responsibilities. Do not create parallel registries for the same responsibility.

Risk semantics use `L0`–`L3` in the governed execution path. Approval-required operations must not bypass the approval/audit path.

Evidence/truthfulness and operational state are different axes. Do not collapse them into one ambiguous status enum.

## Project/source truthfulness

A component being present in source code does not make it operational:

```text
known only               -> DISCOVERED / NOT_CONFIGURED
local evidence present   -> evidence-backed candidate
preview gates pass       -> preview accepted
all certification passes -> certified artifact
promotion + runtime pass -> stable
```

For source-backed positive claims, prefer explicit evidence such as:

```text
real_data=true
synthetic=false
reachable=true
```

A configured source reports facts; that does not independently prove external truth.

## Useful routes

When a runtime is active, useful routes include:

- `/` — Mission Control overview
- `/projects` — project catalog/domains
- `/projects/federated` — federated project view
- `/projects/chatgpt` — ChatGPT project/source status
- `/career` — career module
- `/workflows` — workflow inventory
- `/runs` — durable runs
- `/services` — services and discovery candidates
- `/security` — security status
- `/audit` — audit view
- `/evidence` — evidence view
- `/display/i7` — i7 display compatibility path
- `/health` — health probe
- `/ready` — readiness probe

Use port `4014` for the current development candidate, `4015` for release smoke and `4013` only for stable production.

## Quality gates

The production path is expected to prove, as applicable:

```text
FORMAT
COMPILE --warnings-as-errors
FULL TESTS
CREDO --strict
DIALYZER
SOBELOW
WORKFLOW REGISTRY
WORKFLOW IDS
HEX AUDIT
git diff --check
PROJECT CATALOG / PRODUCTION ACCEPTANCE
LOCAL CODER CONTRACT
READ-ONLY MCP TESTS
PRODUCTION RELEASE BUILD
4015 RELEASE SMOKE
```

A previous green result is historical evidence, not proof that the current HEAD is green. Re-run relevant gates after changes.

## Repository data policy

This repository must not contain:

- API tokens, passwords or OAuth client secrets;
- SSH/private keys;
- financial or legal raw data;
- private message bodies/attachments;
- local runtime databases/state;
- copied credential files;
- synthetic data represented as real source data.

Runtime data remains local and is consumed only through bounded adapters/manifests.

## Current development priorities

Keep feature breadth frozen until the existing system is proven end-to-end. The priority order is documented in [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md). In general:

1. close governance/security correctness gaps;
2. prove full local certification and rollback;
3. connect a small number of real authorized sources;
4. prove one complete Source -> Signal -> Decision -> Approval -> Action -> Audit use case;
5. only then consider new feature families.

## License / usage

No proprietary third-party implementation or branding is implied by architectural inspiration. Keep all integrations compliant with their own APIs, licenses and authorization models.
