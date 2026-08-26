# ShadowOps local stable/dev runtime model

## Objective

ShadowOps must remain locally usable while development continues.

Development is therefore isolated from the user-facing local runtime.

## Runtime lanes

| Lane | Purpose | Port | Git/worktree | State |
| --- | --- | ---: | --- | --- |
| Stable | Daily local use | 4013 | existing known-good runtime / immutable promoted release | `~/.local/state/shadowops` |
| Development | OpenCode implementation and smoke tests | 4014 | `~/Projects/shadowops-mission-control-v2-dev` on `automation/opencode-work` | `~/.local/state/shadowops-dev` |

## Non-negotiable rules

1. OpenCode must not develop inside the checkout used by the active stable runtime.
2. Normal development must not stop, restart, reconfigure, or rebuild the stable 4013 service.
3. Development must never bind to port 4013.
4. Stable and development state/build/temp/log paths must not overlap.
5. A source defect found in development is fixed in the development lane first.
6. A stable-runtime defect is not repaired by ad-hoc editing of files under the active runtime checkout.
7. Promotion to stable is a distinct operation after validation.
8. `main` is never auto-merged by the autonomous loop.

## Development workflow

```text
GitHub handoff task
    ↓
automation/opencode-work
    ↓
dedicated dev worktree
    ↓
format / compile / tests / security gates
    ↓
optional dev runtime on 4014
    ↓
commit + push
    ↓
GitHub handoff result
    ↓
review
```

The 4013 runtime stays available throughout this cycle.

## Promotion workflow

Promotion is allowed only when all required gates for the candidate commit are satisfied.

Required promotion evidence:

- exact candidate commit SHA
- exact current stable/rollback SHA or release identifier
- required CI and local gates PASS
- 4014 smoke PASS when runtime behavior changed
- no unresolved security/privacy/truthfulness blocker
- migration/state compatibility reviewed when applicable

Preferred stable deployment model:

```text
~/.local/opt/shadowops/releases/<commit-sha>/
~/.local/opt/shadowops/stable/current -> ../releases/<commit-sha>/
```

The stable service should eventually execute an immutable promoted release, not a mutable development worktree.

A controlled stable restart is part of promotion only. The previous release remains the rollback target.

## Truthfulness

A successful development test does not mean the stable 4013 runtime has been upgraded.

Report states separately:

- `DEV_VERIFIED`
- `STABLE_VERIFIED`
- `PROMOTED`
- `NOT_CONFIGURED`
- `BLOCKED_<reason>`

No source or connector may be marked `READY` solely because code exists.

## Privacy and secrets

Stable/dev isolation does not permit copying raw private data into Git. Secrets remain outside repository files. Development should use separate local environment/configuration and only minimum required private test evidence.

## Operating rules

`FINISH BEFORE EXPAND`

`STABLE WHILE DEVELOPING`
