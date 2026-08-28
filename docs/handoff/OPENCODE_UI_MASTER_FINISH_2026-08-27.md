# OpenCode UI Master Finish — ShadowOps Mission Control V2

Datum: 2026-08-27

## Scope

This document records the master finish state of the ShadowOps Mission Control UI implementation.
It is the authoritative reference for agents reviewing or certifying the UI layer.

## Implementation summary

The Mission Control is a Phoenix LiveView/HEEx interface around the existing control-plane contexts.
`ShadowOpsWeb.MissionControlComponents` supplies the application shell, grouped sidebar, top bar,
badges, metrics, panels, source metadata and unavailable states. `/assets/mission-control.css`
defines the dark operations palette, responsive layout, semantic focus treatment and reduced-motion
behavior. No second frontend framework was added.

## Hard boundaries (must not be violated)

- Never switch to, edit, merge into, rebase onto, reset, or push `main`/`master`.
- Never run deploy workflows or mutate the stable ShadowOps runtime.
- Never invent READY/CONNECTED/REAL_DATA states. Missing evidence stays NOT_CONFIGURED, UNAVAILABLE, DEGRADED, DISCOVERED, or BLOCKED.
- Never commit secrets, tokens, browser cookies, credentials, private raw exports, or local absolute private paths.
- Never touch, restart, stop, kill, deploy or promote port 4013.
- Client/model-provided actor, risk, approval, executor, runtime, adapter, capability, service, command, or policy values are never authoritative.

## UI architecture

### Shell
- `ShadowOpsWeb.MissionControlComponents` — application shell, grouped sidebar, top bar, badges, metrics, panels, source metadata, unavailable states.
- `/assets/mission-control.css` — dark operations palette, responsive layout, semantic focus, reduced-motion.
- Skip link, semantic navigation, current-page state, semantic tables, visible keyboard focus, text labels in every status badge.

### Routes (verified 2026-08-23 via `mix phx.routes ShadowOpsWeb.Router`)
| Screen | Route | Classification |
|---|---|---|
| Mission Control | `/` | CONNECTED |
| Workflows | `/workflows` | CONNECTED |
| Workflow detail | `/workflows/:id` | CONNECTED |
| Runs | `/runs`, `/runs/:id` | CONNECTED |
| Services | `/services` | CONNECTED |
| Nodes | `/nodes` | NOT_CONNECTED |
| Agents | `/agents` | NOT_CONNECTED |
| AI | `/ai` | CONNECTED |
| Knowledge | `/knowledge` | CONNECTED |
| Facebook | `/social/facebook` | CONNECTED |
| Approvals | `/approvals`, `/approvals/:id` | CONNECTED |
| Security | `/security` | CONNECTED |
| Audit | `/audit` | CONNECTED |
| Evidence | `/evidence` | CONNECTED |
| i7 learning display | `/display/i7` | CONNECTED |
| Health/readiness | `/health`, `/ready` | CONNECTED |

### State semantics
- `CONNECTED` — real values or explicit source state only.
- `NOT_CONNECTED` — optional areas without a source render a reasoned unavailable state.
- `UNAVAILABLE`, `DEGRADED`, `DISCOVERED`, `BLOCKED` — missing evidence stays in these states.
- Dashboard refreshes high-changing summary state every 15 seconds after LiveView connection.
- Registry data loaded once per workflow view; knowledge/evidence metadata loaded once per page request.
- No per-component runtime commands.

## Certification boundaries

- Do not redesign the UI. Fix only genuine certification/security or concrete UI defects.
- Do not fabricate READY states, runtime truth, evidence, counts or fake data.
- Do not expose private paths or secrets.
- Only make changes when you can identify a concrete defect.
- Commit and push fixes only to your own branch.
- Never force push. Never modify main/master.

## Reference docs

- `docs/ui/SHADOWOPS_MISSION_CONTROL.md`
- `docs/ui/UI_ROUTE_INVENTORY.md`
- `docs/ui/UI_BACKEND_CONTRACT.md`
- `.opencode/SHADOWOPS_CODER_RULES.md`
- `docs/handoff/OPENCODE_NEMOTRON_EXECUTION.md`

## Authoritative implementation branch

The canonical implementation branch is `origin/auto/opencode-work`.
All fixes must be compared against the latest `origin/auto/opencode-work` before final validation.
