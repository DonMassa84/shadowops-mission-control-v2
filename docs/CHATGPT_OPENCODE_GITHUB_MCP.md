# ChatGPT ↔ OpenCode via GitHub MCP

## Purpose

Use GitHub as the shared, auditable source of truth between ChatGPT and OpenCode.

- ChatGPT: analysis, review, prioritization, architecture, evidence checks.
- OpenCode: local implementation, tests, refactoring, commits and PR preparation.
- GitHub: repository state, issues, pull requests, Actions and durable handoff evidence.
- Local ShadowOps runtime: remains local; secrets and private/raw data must never be committed.

## Security model

The project OpenCode configuration connects to the official GitHub MCP endpoint in read-only mode.

The GitHub token must be supplied only through the environment variable:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN='...'
```

Never place the token in `opencode.jsonc`, shell history, repository files, logs or evidence artifacts.

The MCP connection is deliberately read-only. OpenCode may still make local code changes and use the normal local `git` workflow. Publishing changes to GitHub remains an explicit operation.

## Startup verification

From the repository root:

```bash
opencode mcp list
opencode mcp debug github
```

Expected result: the `github` MCP server is available and exposes repository, pull-request, issue and Actions read tools.

## Handoff protocol

### ChatGPT → OpenCode

A task handed to OpenCode should contain:

1. Repository and target branch.
2. Goal and acceptance criteria.
3. Files or components in scope.
4. Required tests/checks.
5. Explicit non-goals and safety constraints.
6. Expected evidence: diff, test output, commit SHA and PR URL when applicable.

### OpenCode → ChatGPT

OpenCode should return or publish:

1. Branch name.
2. Commit SHA.
3. Changed files.
4. Test/format/compile results.
5. Remaining blockers or assumptions.
6. Pull request number/URL when created.

ChatGPT can then independently inspect the GitHub state and review the implementation.

## Default execution policy

- Do not mutate production runtime as part of repository review.
- Do not restart productive services unless the task explicitly requires it.
- Do not commit secrets, tokens, OAuth material, private messages, financial raw data, legal raw data or local runtime state.
- Prefer isolated branches and pull requests over direct changes to `main`.
- Treat GitHub Actions and committed evidence as verification, not as a substitute for local runtime evidence.
- Fail closed when required runtime facts are unavailable.

## Recommended OpenCode task

```text
Use the github MCP server and the local repository.

Inspect the current repository state and the requested task.
Work only on an isolated branch.
Do not modify production runtime.
Do not expose or commit secrets or private runtime data.

Implement the task, run the relevant format/compile/tests, and report:
- branch
- commit SHA
- changed files
- test results
- blockers
- PR URL if one is created
```

## ChatGPT review task

```text
Inspect the ShadowOps repository on GitHub.
Review the latest implementation branch/PR against its acceptance criteria.
Check the diff, CI state, tests and security constraints.
Return PASS / PARTIAL / FAIL with concrete remediation items.
```
