# ShadowOps Status History

This directory is the chronological status ledger for ShadowOps Mission Control V2.

## Purpose

Git already answers **what changed**. This history layer answers **what the project state meant at that point in time**.

Each significant project state should record:

- timestamp and scope
- branch and commit SHA
- implemented capabilities
- source/connectivity state
- governance/security state
- format/compile/test/CI evidence
- runtime evidence when available
- blockers and explicit non-claims
- next required action

## Evidence classes

Every material claim should be tagged or described using one of these evidence classes:

- `REPO_VERIFIED` — directly supported by committed repository state, PR, issue, or commit metadata.
- `CI_VERIFIED` — directly supported by a GitHub Actions run/check.
- `LOCAL_VERIFIED` — supported by bounded runtime evidence published through the GitHub handoff channel.
- `LOCAL_REPORTED` — observed locally and reported in a handoff, but not independently reproducible from GitHub alone.
- `NOT_CONFIGURED` — capability exists but the real external/local source is not configured.
- `UNVERIFIED` — no sufficient evidence exists; must never be promoted to READY/PASS.

## Naming convention

New immutable snapshots use:

`YYYY-MM-DD-HHMM-<short-description>.md`

If exact time is unknown for a historical reconstruction, use:

`YYYY-MM-DD-<short-description>.md`

## Snapshot policy

1. Do not rewrite history to make an old state look better.
2. If an old snapshot is wrong, add a new correction snapshot and reference the prior entry.
3. Git commit SHA, PR number, workflow run, issue number, or sanitized runtime handoff should be recorded whenever available.
4. CI success proves repository/build state, not local source connectivity.
5. Local runtime success proves only the evidenced runtime instance and timestamp.
6. Missing real data must remain `NOT_CONFIGURED`, `UNAVAILABLE`, or equivalent fail-closed state.
7. Raw private data is never stored in this history.

## Security boundary

Never commit into status snapshots:

- tokens, passwords, cookies, OAuth material or secret environment values
- raw ChatGPT conversations/exports
- private messages or attachments
- raw health, legal or financial data
- full environment dumps
- private local credentials

Allowed evidence includes bounded metadata such as branch, SHA, status codes, test counts, source state, runtime component name, blocker code and sanitized root-cause summary.

## Canonical index

The human-readable timeline is maintained in:

`docs/SHADOWOPS_STATUS_HISTORY.md`

The current GitHub/OpenCode/ChatGPT handoff channel is Issue `#8`.

## Operating rule

`FINISH BEFORE EXPAND`

A new feature should not be described as production-ready while an existing evidence, runtime, governance or source gate remains open.
