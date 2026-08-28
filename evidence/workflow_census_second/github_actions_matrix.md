# GitHub Actions Workflow Matrix (independent audit)

Source: `.github/workflows/` on base `fda310a` (audit branch `audit/workflow-census-second-instance`)

| File | Name | Triggers | Branches | Category | Starts 4013? | Safe manual trigger? |
|------|------|----------|----------|----------|--------------|----------------------|
| ci_hardening.yml | ShadowOps Hardening CI | push, PR | hardening/**, feat/mission-control-v2, local/all-developments; PR main | CI-only / quality gate | No | Yes (static checks only) |
| elixir.yml | ShadowOps Production Gate | push, PR, workflow_dispatch | main, hardening/production-ready-2026-08-25 | product gate | **YES** (release_runtime_gate step) | **NO** — would start PORT 4013 |
| local-all-developments-contract.yml | Local All Developments Contract | push, PR (path) | local/all-developments; PR main | local contract | No | Yes (read-only) |
| local-coder-contract.yml | ShadowOps Local Coder Contract | push, PR (path) | local/all-developments; PR main | local contract / read-only MCP | No | Yes (read-only MCP unittest) |
| local-static-diagnostics.yml | Local Static Diagnostics | push, PR | local/all-developments; PR main | diagnostics | No | Yes (credo/dialyzer/sobelow) |
| opencode-handoff-contract.yml | OpenCode Handoff Contract | push, PR (path) | local/all-developments; PR main | local contract | No | Yes (marker/grep) |
| remote-ai-policy.yml | Remote AI Policy | push, PR (path) | local/all-developments; PR main | remote AI policy | No | Yes (policy checks) |
| verified-app-product.yml | ShadowOps Verified Product Gate | push, PR, workflow_dispatch | feature/shadowops-verified-app, product/**; PR main | product gate / verified app | No (checks before/after) | Yes (tests only, no 4013 start) |

## Classification
- **CI-only / quality gate:** ci_hardening.yml
- **Product gate:** elixir.yml, verified-app-product.yml
- **Diagnostics:** local-static-diagnostics.yml
- **Local contract (safe):** local-all-developments-contract.yml, local-coder-contract.yml, opencode-handoff-contract.yml, remote-ai-policy.yml
- **Remote AI policy:** remote-ai-policy.yml
- **Deployment-related:** none directly deploy (release build is `--overwrite` only, no publish/deploy step)
- **Safe workflow candidate (manual, read-only):** all except elixir.yml

## Trigger reach for feature/shadowops-verified-app
- `verified-app-product.yml` runs on `feature/shadowops-verified-app` push (this is the failing gate, run 33193759820 FAILURE).
- `elixir.yml` does NOT trigger on feature/shadowops-verified-app (only main + hardening branch).
- `ci_hardening.yml` does NOT trigger on feature/shadowops-verified-app.
- The 4 local-contract / diagnostics / policy workflows trigger only on `local/all-developments` or PRs to `main`.

## Action taken
No workflow was manually triggered. No side effects produced.

