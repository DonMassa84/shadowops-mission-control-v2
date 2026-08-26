# ShadowOps Local All Developments

## Goal

Run every currently integrated ShadowOps development locally without mutating the stable runtime until the exact candidate commit has passed full production certification.

The lifecycle is deliberately split into three ports and three trust levels:

```text
Remote AI + OpenCode + source tree
              |
              v
4014  DEVELOPMENT / PREVIEW
      complete local candidate
      project catalog
      workflow registry
      agent contracts
      local integration discovery
      read-only runtime MCP
              |
              | full static/security/release certification
              v
4015  EPHEMERAL RELEASE SMOKE
      exact production release artifact
              |
              | signed-by-evidence local certificate + SHA256
              v
4013  STABLE
      promotion only with explicit operator opt-in
      automatic rollback on failed health/readiness/routes
```

## Canonical branch

```text
local/all-developments
```

This is the rolling local integration candidate. `main` is not changed by the local lifecycle.

## One entrypoint

```bash
cd ~/Projects/shadowops-mission-control-v2
git fetch origin
git switch local/all-developments
git pull --ff-only

scripts/shadowops-local.sh status
scripts/shadowops-local.sh setup
scripts/shadowops-local.sh certify
SHADOWOPS_PROMOTE_STABLE=YES scripts/shadowops-local.sh promote
```

### `setup`

`setup` runs `scripts/local_all_developments.sh` and requires:

- clean branch exactly synced with `origin/local/all-developments`;
- Elixir/Erlang/Mix toolchain;
- OpenCode only when the optional coder-contract validation is explicitly requested;
- an explicit remote `provider/model` when the guarded coder is launched;
- read-only MCP dependencies available through `uv`, or local Python `mcp` + `httpx` packages.

It then:

1. resolves dependencies without allowing a `mix.lock` drift;
2. creates/merges the metadata-only Project Catalog with `mix shadowops.projects.seed`;
3. validates the guarded local ShadowOps OpenCode agent;
4. runs the read-only MCP unit tests;
5. invokes the existing full `configure_local_all.sh` quality gate;
6. builds a production release;
7. configures `shadowops-preview.service` on port 4014;
8. checks health/readiness and core UI routes;
9. verifies the OpenCode MCP configuration.

Port 4013 is explicitly excluded from this phase.

## Local coder

```bash
scripts/shadowops-local.sh coder \
  "Implement the next verified ShadowOps task, run targeted tests, then the relevant quality gates."
```

The guarded coder requires:

```text
AI execution:  REMOTE_ONLY
model:         explicit remote provider/model
runtime MCP:   http://127.0.0.1:4014 (read-only)
local fallback: forbidden
```

The guarded coder blocks protected branches, rejects local-model providers and denies destructive Git/runtime operations through its agent policy.

## `certify`

`certify` runs `scripts/certify_all_developments.sh`.

It first requires the 4014 preview to be healthy and then runs the full production blockers:

```text
FORMAT
COMPILE --warnings-as-errors
FULL TESTS
CREDO --strict
DIALYZER
SOBELOW --exit
WORKFLOW REGISTRY
WORKFLOW IDS
HEX AUDIT
git diff --check
LOCAL CODER CONTRACT
READ-ONLY MCP TESTS
PRODUCTION HANDOFF
RELEASE RUNTIME SMOKE on 4015
```

If any required gate fails, no certificate is written.

On success it packages the exact tested release under:

```text
~/.local/state/shadowops/certified-releases/
```

and writes:

```text
<HEAD>.env
shadowops-<HEAD>.tar.gz
shadowops-<HEAD>.tar.gz.sha256
```

The certificate contains no secrets. It records the Git HEAD and required PASS states.

## `promote`

Promotion is intentionally impossible without explicit operator consent:

```bash
SHADOWOPS_PROMOTE_STABLE=YES scripts/shadowops-local.sh promote
```

The promotion script requires:

- local branch == `local/all-developments`;
- local HEAD == remote HEAD;
- clean worktree;
- matching certification file for the exact HEAD;
- PASS for Credo, Dialyzer, Sobelow, registry, IDs, audits, production handoff, MCP and coder contracts;
- matching SHA256 of the certified release artifact;
- the 4014 candidate still healthy;
- current 4013 stable service healthy before mutation.

It does **not** switch the source branch under the running stable runtime.

Instead it creates an immutable detached worktree:

```text
~/Projects/shadowops-releases/<HEAD>/source
```

and extracts the exact certified release artifact there.

A high-priority user-systemd drop-in then points `shadowops-phoenix.service` to that immutable source/release while preserving the existing secret/state configuration.

## Automatic rollback

Before promotion, the current systemd unit and prior certified-release drop-in are stored under:

```text
~/.local/state/shadowops/promotions/<timestamp>/
```

If the new stable runtime fails health, readiness, a required route, or WorkingDirectory verification, the script automatically restores the prior drop-in and restarts the previous stable service.

## Stable state

The promotion drop-in changes only:

- `WorkingDirectory`;
- release `ExecStart` / `ExecStop`;
- `PORT=4013`;
- `SHADOWOPS_PROJECT_CATALOG` path.

Existing secrets and persistent state configuration remain in the existing stable systemd environment/drop-ins.

## Status

```bash
scripts/shadowops-local.sh status
```

shows:

- Git branch/HEAD;
- listeners on 4013/4014/4015;
- stable and preview systemd status;
- HTTP health/readiness;
- latest production certificate.

## Non-negotiable truthfulness

A local component is never promoted merely because it exists in the source tree.

```text
known only               -> DISCOVERED / NOT_CONFIGURED
local evidence present   -> evidence-backed candidate
preview gates pass       -> preview accepted
all certification passes -> certified artifact
promotion + runtime pass -> stable 4013
```

`READY` and `PASS` remain evidence states, not intentions.
