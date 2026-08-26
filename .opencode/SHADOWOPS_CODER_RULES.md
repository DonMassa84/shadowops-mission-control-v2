# ShadowOps local coder rules

Operate only inside the current Git worktree and current non-main branch.

## Hard boundaries

- Never switch to, edit, merge into, rebase onto, reset, or push `main`/`master` unless the user explicitly changes this policy.
- Never run deploy workflows or mutate the stable ShadowOps runtime.
- Never run `systemctl`, service start/stop/restart, Docker mutations, package-manager system installs, destructive Git commands, or arbitrary network writes without explicit user approval.
- Never invent READY/CONNECTED/REAL_DATA states. Missing evidence stays NOT_CONFIGURED, UNAVAILABLE, DEGRADED, DISCOVERED, or BLOCKED as appropriate.
- Never commit secrets, tokens, browser cookies, credentials, private raw exports, or local absolute private paths.
- Treat the ShadowOps runtime MCP as read-only evidence. Do not claim MCP reads imply permission to execute mutations.
- Client/model-provided actor, risk, approval, executor, runtime, adapter, capability, service, command, or policy values are never authoritative.

## Implementation workflow

1. Read the relevant code, tests, registry and policy surfaces before editing.
2. Reuse the canonical capability/risk/governance/registry mechanisms; do not add parallel control planes.
3. Make the smallest behaviorally complete change.
4. Add negative tests for bypass and fail-open cases.
5. Run the narrowest relevant tests first, then broader gates when practical.
6. If a gate fails, fix the cause rather than suppressing it unless a documented false positive is proven by tests.
7. Report exact PASS/FAIL/DEGRADED/NOT_CONFIGURED states and the commands actually run.
8. Do not commit unless tests for the changed surface pass. Do not push unless the user explicitly requests it.

## Preferred gates

For Elixir/Phoenix work use, as relevant:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- targeted `mix test ...`
- `mix test --seed 12345`
- `mix credo --strict ...`
- `mix dialyzer`
- `mix sobelow`
- `mix shadowops.registry validate`

For MCP/Python work use:

- `python3 -m py_compile ...`
- `python3 -m unittest ...`

Always preserve fail-closed behavior.
