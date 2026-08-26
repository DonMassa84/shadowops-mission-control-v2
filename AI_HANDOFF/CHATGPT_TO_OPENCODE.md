# ChatGPT → OpenCode

TASK_ID=shadowops-runtime-gate-2026-08-26-002
STATUS=READY
REPO=DonMassa84/shadowops-mission-control-v2
BASE_REF=feat/chatgpt-source-evidence
WORK_BRANCH=automation/opencode-work
HANDOFF_BRANCH=ai-handoff/state
ISSUE=8
PR=7
REVIEWED_RESULT_SHA=NONE

## Primary requirement
ShadowOps must remain locally usable while development continues.

The stable runtime and development runtime MUST be isolated.

### Stable lane — user-facing local ShadowOps
- canonical port: `4013`
- must remain available during normal OpenCode development
- do not develop inside its active checkout
- do not restart/stop it merely to run tests
- do not reuse its build directory for development
- preserve its existing local state and configuration
- treat it as read-only from the development workflow except during an explicit promotion operation

### Development lane — OpenCode
- dedicated worktree outside the stable runtime checkout
- recommended worktree: `~/Projects/shadowops-mission-control-v2-dev`
- branch: `automation/opencode-work`
- development/smoke port: `4014`
- separate build output
- separate runtime state, for example `~/.local/state/shadowops-dev`
- separate temp/log paths
- must never bind to 4013

## Goal
Close the current ShadowOps ChatGPT source/runtime gate and establish stable/dev runtime isolation without feature expansion.

## Required work
1. First discover and record the current 4013 runtime PID, CWD, ExecStart, WorkingDirectory and relevant non-secret configuration.
2. Do not stop or restart the current 4013 runtime during diagnosis unless an explicit promotion step is reached and all gates pass.
3. Preserve all local uncommitted changes before touching Git/worktrees.
4. Create/use a dedicated development worktree for `automation/opencode-work`; do not switch the checkout used by the active 4013 service.
5. Synchronize the development branch with the current `feat/chatgpt-source-evidence` head only when safe.
6. Diagnose `/projects` and other runtime issues using code + runtime evidence. Distinguish stable-runtime drift from current-source defects.
7. Keep ChatGPT source fail-closed when no real export exists. Never fabricate READY/real_data evidence.
8. Run format/compile/test/Credo and production acceptance gates in the development worktree.
9. If runtime smoke is needed, run the development instance only on 4014 with isolated state/config. Never collide with 4013.
10. If code changes are required, commit and push only to `automation/opencode-work`.
11. Never merge `main` automatically.
12. Publish a sanitized result by updating `AI_HANDOFF/OPENCODE_TO_CHATGPT.md` on branch `ai-handoff/state` and optionally Issue #8.

## Promotion model
Promotion from development to the stable 4013 runtime is a separate operation.

A promotion is allowed only when:
- development branch/commit is explicitly identified
- required CI/gates pass
- local 4014 smoke passes where applicable
- no unresolved truthfulness/privacy/security blocker exists
- rollback target is recorded

Promotion should deploy an immutable built release or dedicated stable worktree. The stable runtime must not point at a mutable development worktree.

After promotion only, a controlled 4013 restart is allowed. Rollback must remain possible to the previous known-good release/commit.

## Acceptance
- 4013 stays usable during development
- OpenCode development occurs in an isolated worktree
- 4014 is used for development/smoke only
- stable and dev state/build paths do not overlap
- no secrets/raw private data committed or posted
- `main` unchanged unless separately approved
- root cause evidenced, not guessed
- tests and gate results reported precisely
- missing ChatGPT export remains `NOT_CONFIGURED`
- final status is `PASS`, `PARTIAL`, or `BLOCKED_<reason>`

## Operating rule
FINISH BEFORE EXPAND.
STABLE WHILE DEVELOPING.
