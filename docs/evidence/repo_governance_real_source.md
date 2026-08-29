# Repo Governance — Real Local Source Evidence

**Source:** `repo_governance`
**Adapter:** `ShadowOpsCore.OperationalSources.repo_governance/0` (+ `repo_governance_at/2`)
**Branch:** `integration/real-local-governance-sources-2026-08-27`
**Date:** 2026-08-27
**Scope:** read / status / evidence source. Repository mutation is permanently disabled.

## Source location / fail-closed check

- Canonical base: `/home/schattenmacher/openclaw_training`
- Real source: `/mnt/nvme-data/openclaw_training`
- Symlink check (`readlink -f` of both paths): identical resolved target → `same_dataset=true`
- Fail-closed: if the two paths ever resolved to different datasets, the source returns DEGRADED with `reachable=false`.

## Status JSON

- Path: `data/workflow_status/repo_governance_status.json`
- Parses: yes

## Artifacts (6/6 present) + SHA256

```text
GITHUB_REPO_CHANNEL_ASSIGNMENT.md   91d611b5f67826d96b9643362c99bb6286d48fa04cdaf77ae70cfa1ab14e4f96
github_repo_channel_assignment.json  156f00f5f5613a890828b06eb46d74a70db912fbf187b168abc2d62f0c8040ff
GITHUB_REPO_CANONICAL_INDEX.md      f46a9b8af8d9fa1a48bc85be582750371e147d982f33a744b0b20221d91b36b4
github_repo_canonical_index.json    a7c0deaceb7de4f00de1d151c44492206a0d5112f66c91e6adce763ea3937158
REPO_CLEANUP_PRIORITY_BOARD.md      c925279a4aa3fa256cead598ed8c9f8a4605f0f26dec01eddc16b11cc800d6ae
repo_cleanup_priority_board.json    8879586651789b5bccbc9ac6570d15426402f645a21cfa6745c3d25e04f190a5
```

## Counts

```text
RAW_REPOS=225
CANONICAL_REPOS=130
MULTI_COPY=54
DIRTY=75
NO_REMOTE=26
P0=18  P1=38  P2=46  P3=28
SUM=130 == CANONICAL_REPOS=130  → priority_check=PASS
```

## Readiness evidence

```text
status=READY
real_data=true
synthetic=false
reachable=true
same_dataset=true
artifact_count=6 / artifact_required=6
priority_check=PASS
```

## Mutation / external-write guards (fail closed)

```text
deletion_allowed=false
mutation_allowed=false
discord_write_enabled=false
telegram_write_enabled=false
```

These are hard-coded false. The connector is read-only; it can never delete,
repoint, or mutate the preserved shadow repository set, and it cannot publish to
Discord or Telegram. Recovery of a mutated repository is intentionally left
untouched — this connector only evidences the current governance state.

## Verified commands

```bash
MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix run -e \
  'r = ShadowOpsCore.OperationalSources.repo_governance(); IO.puts("status=#{r.status} reachable=#{r.reachable} same_dataset=#{r.same_dataset} check=#{r.priority_check} canonical=#{r.canonical_repos}")'
# output: status=READY reachable=true same_dataset=true check=PASS canonical=130

MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix test apps/shadowops_core/test/governance_sources_test.exs
# READY / counter-mismatch-DEGRADED / missing-artifact-DEGRADED / synthetic-never-READY / mutation-disabled all pass
```
