# WhatsApp operations — reproducible development handoff

## Scope

The existing `/social/whatsapp` route becomes a read-only operations view.
It reuses `ShadowOpsApi.whatsapp/0`, `WorkflowEngine.Registry` and
`WorkflowEngine.Inventory`. It introduces no executor or parallel registry.

The view separates imported source evidence from agent runtime evidence,
shows the registered WhatsApp pack and links to existing runs, approvals,
audit and integration views. Unknown runtime state remains unknown.
Registry failure must not be presented as a verified empty inventory.

## Reproduce

Use Elixir 1.17.3 and OTP 27.3, as pinned in the verification workflow.
Check out the PR branch `feat/whatsapp-operations-20260928` in an isolated
working directory. Record the resolved commit with `git rev-parse HEAD`.

```bash
export MIX_ENV=test
export SHADOWOPS_START_PERSISTENCE=false
mix deps.get
git diff --exit-code -- mix.lock
mix compile --warnings-as-errors
mix test apps/shadowops_web/test/whatsapp_operations_ui_test.exs
mix test --seed 12345
mix format --check-formatted apps/shadowops_web/lib/shadow_ops_web/live/social_unavailable_live.ex apps/shadowops_web/test/whatsapp_operations_ui_test.exs
```

`.github/workflows/whatsapp-operations.yml` runs these checks on GitHub.
It does not deploy or start operator-host services.

## Acceptance

- The WhatsApp page shows its workflow inventory without executing anything.
- Registry-only entries do not become executable or acquire invented runs.
- A missing registry leaves connector diagnostics usable and shows a blocker.
- Other social connector pages do not display the WhatsApp pack.
- Raw messages and contacts are not introduced into the interface or fixtures.

## Operator-host release

The live operator-host commit and state were not accessible from this workspace.
Before integration, compare the operator's actual checkout and pending changes
with this PR. Do not replace an unknown live branch wholesale.
After review, integrate the small change into the development candidate,
validate on 4014, then follow the repository's 4015 certification and rollback
procedure. Promotion to 4013 is a separate operator action.

## Lessons retained

- A registered workflow is not evidence of an operating worker.
- An imported archive is not evidence of a connected messaging session.
- Missing run evidence must remain explicit.
- A broken registry is an unavailable inventory, not zero workflows.
- Keep code, runtime state and certification evidence separate.
- Use actual test results; a prepared test or historical green run is insufficient.

## Current verification

Implementation and CI verification are tracked in PR #64. Read the checks for
the exact head commit; this runbook does not assert a permanent PASS.
Local tests require a toolchain unavailable in the editing environment.
