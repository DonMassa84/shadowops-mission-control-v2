# ShadowOps Documentation Map

Use this file as the navigation index for humans and AI systems.

## First read

| Document | Purpose |
|---|---|
| `../README.md` | Product overview, local lifecycle, high-level rules |
| `../AGENTS.md` | Binding AI/coding-agent operating contract |
| `AI_CONTEXT.md` | Durable architecture, terminology and trust boundaries |
| `PROJECT_STATUS.md` | Dated evidence/status snapshot and current priorities |
| `ARCHITECTURE.md` | Canonical subsystem/plane responsibilities |

## Local development and production

| Document | Purpose |
|---|---|
| `LOCAL_ALL_DEVELOPMENTS.md` | 4014 -> 4015 -> 4013 development/certification/promotion lifecycle |
| `LOCAL_ACCEPTANCE.md` | Local acceptance notes |
| `PRODUCTION.md` | Production environment/build/runtime guidance |
| `SECURITY.md` | Security rules and hardening context |
| `acceptance_status.md` | Historical acceptance evidence; verify freshness before use |

## Sources and project integration

| Document | Purpose |
|---|---|
| `MISSION_CONTROL_V2_IMPORTS.md` | Mission Control import/source context |
| `CHATGPT_SOURCE_EVIDENCE.md` | ChatGPT local-source evidence contract |
| `chatgpt-project-integration.md` | ChatGPT project integration notes |
| `PROJECT_DOMAIN_MANIFESTS.md` | Project/domain manifest conventions |

## AI / coding handoffs

| Document | Purpose |
|---|---|
| `handoff/OPENCODE_NEMOTRON_EXECUTION.md` | Deterministic current-task contract for OpenCode/Nemotron |
| `../.opencode/agent/shadowops-coder.md` | OpenCode agent permissions/discipline |
| `../opencode.jsonc` | Project OpenCode/MCP/model configuration |

## Decisions and evidence

- `decisions/` — architectural/operational decisions when recorded.
- `evidence/` — repository-safe evidence artifacts when present.
- `acceptance_status.md` and generated reports — historical proof, never automatically current proof.

## Reading rule for future AI systems

Documentation has different freshness characteristics.

### Durable contracts

Usually stable until deliberately changed:

```text
AGENTS.md
AI_CONTEXT.md
ARCHITECTURE.md
SECURITY.md
LOCAL_ALL_DEVELOPMENTS.md
```

### Dated/historical evidence

Must be revalidated:

```text
PROJECT_STATUS.md
acceptance_status.md
CI reports
handoff results
runtime snapshots
```

### Authoritative current truth

Always prefer:

```text
current Git branch + HEAD
current implementation
current tests
current CI
current runtime evidence
```

over stale prose.

## Updating documentation

When a change alters a durable contract, update the relevant durable document in the same branch.

Examples:

- changing runtime ports/lifecycle -> update `LOCAL_ALL_DEVELOPMENTS.md` and `README.md`;
- changing governance semantics -> update `AI_CONTEXT.md`/`ARCHITECTURE.md` and tests;
- changing AI permissions -> update `AGENTS.md` and `.opencode/agent/shadowops-coder.md`;
- closing/opening a production blocker -> update `PROJECT_STATUS.md` with a new dated snapshot.

Do not rewrite historical evidence to make the past look green. Add a new status/evidence record instead.
