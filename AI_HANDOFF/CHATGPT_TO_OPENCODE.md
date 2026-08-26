# ChatGPT → OpenCode

TASK_ID=shadowops-stable-dev-2026-08-26-003
STATUS=READY
REPO=DonMassa84/shadowops-mission-control-v2
BASE_REF=feat/chatgpt-source-evidence
WORK_BRANCH=automation/opencode-work
HANDOFF_BRANCH=ai-handoff/state
ISSUE=8
PR=7
REVIEWED_RESULT_SHA=NONE

## Primary requirement
The user must always have the last known-good ShadowOps implementation available locally while development continues.

This requirement is stronger than merely keeping port 4013 running: stable must be pinned to a specific validated commit/release and must never track an unvalidated mutable development checkout.

## Runtime lanes

### Stable lane — always usable
- canonical port: `4013`
- contains the most recent locally validated stable release only
- stable release is identified by exact commit SHA
- stable runtime must not execute from the mutable OpenCode development worktree
- stable state/configuration is preserved across release rotation
- normal development must not stop/restart/rebuild stable
- keep at least `current` and `previous` known-good releases locally; prefer retaining the last 3 releases
- expose the deployed stable SHA in local evidence/status

Recommended managed layout:

```text
~/.local/opt/shadowops/
  releases/<commit-sha>/
  stable/current  -> ../releases/<current-sha>
  stable/previous -> ../releases/<previous-sha>
```

### Development lane — OpenCode
- dedicated worktree: `~/Projects/shadowops-mission-control-v2-dev`
- branch: `automation/opencode-work`
- smoke/runtime port: `4014`
- separate state: `~/.local/state/shadowops-dev`
- separate build/temp/log paths
- never bind to 4013

## Goal
1. Preserve uninterrupted access to the current last-known-good 4013 implementation.
2. Establish isolated OpenCode development on 4014.
3. Establish deterministic promotion of a validated candidate to stable.
4. Establish deterministic rollback to the previous stable release.
5. Continue closing the ChatGPT source/runtime gate without feature expansion.

## Required work
1. Discover the current 4013 runtime PID, CWD, ExecStart, WorkingDirectory, source/release SHA if derivable, and non-secret configuration.
2. Preserve all local uncommitted files before Git/worktree changes.
3. Do not stop/restart 4013 during normal development or diagnosis.
4. Create/use the dedicated development worktree for `automation/opencode-work`.
5. Synchronize the dev branch with the current target source only when safe.
6. Diagnose `/projects` and runtime drift using code + runtime evidence; distinguish defects in stable from defects in current development source.
7. Keep missing ChatGPT source `NOT_CONFIGURED`; never fabricate READY/real_data.
8. Run required static gates in the dev worktree.
9. Run candidate runtime smoke on 4014 with isolated state/configuration when runtime behavior is affected.
10. Produce an immutable `shadowops` production release for the exact candidate SHA.
11. Only after all required candidate gates pass, stage the release under a SHA-addressed local release path.
12. Before promotion, record the current stable SHA/path as rollback target.
13. Promotion must atomically move `stable/current` to the candidate and `stable/previous` to the former current release (or an equivalent deterministic mechanism).
14. Only during this promotion step may the stable 4013 service be restarted.
15. Immediately verify 4013 `/health`, `/ready`, `/projects`, `/projects/federated`, `/projects/chatgpt` as applicable.
16. If mandatory stable verification fails, automatically restore the previous stable target and restart 4013 on that previous release; report `ROLLBACK=PASS|FAIL`.
17. Never auto-merge `main`.
18. Code changes are committed/pushed only to `automation/opencode-work` or a dedicated automation branch.
19. Publish a sanitized result to `AI_HANDOFF/OPENCODE_TO_CHATGPT.md` and optionally Issue #8.

## Promotion gate
A candidate may become stable only when all applicable items are true:

- candidate commit SHA is explicit
- source/worktree parity is proven
- format PASS
- compile with warnings-as-errors PASS
- tests PASS
- registry/workflow IDs/audit/production acceptance PASS when present
- production release build PASS
- 4014 release smoke PASS when runtime behavior changed
- no unresolved security/privacy/truthfulness blocker
- rollback target recorded

GitHub CI may support the decision, but does not by itself prove the local 4013 runtime.

## Stable guarantee
At every point in time one of these must hold:

```text
STABLE_4013=RUNNING_LAST_KNOWN_GOOD
```

or, during the short controlled promotion transaction:

```text
STABLE_4013=PROMOTING_WITH_ROLLBACK_READY
```

The autonomous loop must never intentionally leave the user with only an unvalidated development build.

## Result evidence
Include:

```text
STABLE_SHA_BEFORE=
CANDIDATE_SHA=
DEV_4014=
PROMOTION=
STABLE_SHA_AFTER=
STABLE_4013=
PREVIOUS_STABLE_SHA=
ROLLBACK_READY=
ROLLBACK=
```

along with the existing test/runtime/source evidence fields.

## Operating rules
FINISH BEFORE EXPAND.
STABLE WHILE DEVELOPING.
LAST-KNOWN-GOOD ALWAYS AVAILABLE.
