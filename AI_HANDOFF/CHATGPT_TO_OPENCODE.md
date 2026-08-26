# ChatGPT → OpenCode

TASK_ID=shadowops-runtime-gate-2026-08-26-001
STATUS=READY
REPO=DonMassa84/shadowops-mission-control-v2
BASE_REF=feat/chatgpt-source-evidence
WORK_BRANCH=automation/opencode-work
HANDOFF_BRANCH=ai-handoff/state
ISSUE=8
PR=7
REVIEWED_RESULT_SHA=NONE

## Goal
Close the current ShadowOps ChatGPT source/runtime gate without feature expansion.

## Required work
1. Work only in an isolated/dedicated worktree; do not overwrite the user's primary checkout.
2. Synchronize `automation/opencode-work` with the current `feat/chatgpt-source-evidence` head by fast-forward/rebase only when safe.
3. Diagnose the local runtime drift and `/projects` HTTP 500 using code + runtime evidence.
4. Keep ChatGPT source fail-closed when no real export exists. Never fabricate READY/real_data evidence.
5. Run relevant format/compile/test/Credo and production acceptance gates.
6. If code changes are required, commit and push only to `automation/opencode-work`.
7. Never merge `main`.
8. Publish a sanitized result by updating `AI_HANDOFF/OPENCODE_TO_CHATGPT.md` on branch `ai-handoff/state` and optionally Issue #8.

## Acceptance
- no secrets/raw private data committed or posted
- `main` unchanged
- root cause evidenced, not guessed
- tests and gate results reported precisely
- missing ChatGPT export remains `NOT_CONFIGURED`
- final status is `PASS`, `PARTIAL`, or `BLOCKED_<reason>`

## Operating rule
FINISH BEFORE EXPAND.
