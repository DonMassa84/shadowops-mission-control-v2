# ShadowOps UI Master Finish — OpenCode Handoff

Date: 2026-08-27
Branch: `auto/opencode-work`

## Objective

Finish ShadowOps Mission Control V2 as a production-grade **MASTER-CANDIDATE** without promoting stable port 4013.

Execution order:

`UI hardcode/refinement -> targeted tests -> hermetic full tests -> Credo regression gate -> commit -> push -> immutable 4014 preview on final SHA -> official isolated 4015 certification -> certificate`

## Non-negotiable truth rule

Hardcode **presentation only**: layout, spacing, CSS tokens, responsive breakpoints, typography, semantic icons, status presentation, card sizing and visual hierarchy.

Never hardcode runtime truth: READY/DEGRADED/NOT_CONFIGURED, counts, health, evidence status, real_data, synthetic, reachable, workflow results, approvals, timestamps, mission state or fake demo data.

All operational truth must continue to come from the existing ShadowOps source-truth pipeline.

## Primary UI files

- `apps/shadowops_web/lib/shadow_ops_web/live/dashboard_live.ex`
- `apps/shadowops_web/lib/shadow_ops_web/mission_control_components.ex`
- `apps/shadowops_web/priv/static/assets/mission-control.css`
- `apps/shadowops_web/priv/static/assets/mission-control-command.css`
- relevant UI tests

## Design target

Professional SOC/NOC/operations-control-plane console:

- dark navy background
- restrained blue/cyan accent
- green only for genuine healthy/success
- purple for degraded/review
- amber for warning/action
- red only for real errors
- dense but readable typography
- crisp one-pixel borders
- restrained shadows
- no giant cards or decorative clutter
- efficient use of 1600-1900px desktop width
- responsive and keyboard-accessible

### Source-truth cards

Redesign the first dashboard source area into a compact operations status strip.

Wide desktop: roughly 7-8 compact cards per row where space permits.
Medium desktop: roughly 4 columns.
Tablet: 2 columns.
Mobile: 1 column.

Presentation hierarchy:

1. source icon
2. source label
3. status badge
4. primary value/state
5. short note
6. compact truth metadata

Preserve these fields in the DOM:

- health
- real_data
- synthetic
- reachable
- record_count
- source_type
- source attribution
- failure reason when present

Long `source_type` values must not break layout; visually truncate if needed while preserving the full value accessibly.

Use semantic source selectors/classes such as `[data-source-id="system"]`; do not bind semantic color to `nth-child` ordering.

Use deterministic presentation-only icons for system, security, audit, ihk, evidence, knowledge, services, social, career and backups. Prefer a map lookup to a high-complexity icon function.

## Shell/layout refinement

Keep existing routes and Phoenix/LiveView architecture.

- sidebar approximately 210-220px desktop
- tighter navigation rhythm
- strong active/focus state
- sticky sidebar/topbar retained
- compact topbar
- main workspace uses available width
- preserve skip link, aria-current, focus-visible and semantic headings

Improve Current Mission, Attention Required, Top 3 Next Actions and One-Click Control consistently. Failures/unavailable actions must remain visible.

## Governance boundaries

Do not change truth semantics in RuntimeOverview, DailyControl, ProjectDomains, OperationalSources, RuntimeSources, Truthfulness, PrivacyGate, approval/audit/execution logic, workflow registry, workflow IDs or risk policy unless a directly caused regression demands a minimal fix.

Do not invent workflows, bulk-import discovered files, expose private local paths, expose secret values, add arbitrary shell execution, touch `main`/`master`, force-push or promote 4013.

## Credo certification blocker

The prior certification reached the full ShadowOpsWeb suite with 117 passing tests, then failed at repository-wide `mix credo --strict` because of existing legacy findings.

Do not weaken Credo with `|| true`, global disabling or broad excludes.

Implement a deterministic **Credo regression gate** only after verifying the findings are pre-existing:

- checked-in exact legacy finding fingerprints
- dedicated script such as `scripts/credo_regression_gate.sh`
- run full strict Credo analysis
- compare current findings against baseline
- fail on any new finding
- pass only if remaining findings are exact known legacy debt
- report `CREDO_LEGACY`, `CREDO_NEW`, `CREDO_RESOLVED`, `CREDO_REGRESSION_GATE`
- changed UI files must introduce zero new Credo findings
- remove resolved fingerprints instead of keeping stale debt
- keep full Credo report visible
- update `scripts/certify_all_developments.sh` to invoke the regression gate and record explicit certificate semantics such as `CREDO_MODE=REGRESSION_GATE` and `CREDO_NEW=0`

Do not weaken any other certification gate.

## Required verification loop

Run and repair until green or a genuine external/safety blocker is proven:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
# relevant dashboard/component tests

env -i \
  HOME="$HOME" \
  USER="${USER:-$(id -un)}" \
  LOGNAME="${USER:-$(id -un)}" \
  PATH="$PATH" \
  LANG="${LANG:-C.UTF-8}" \
  MIX_ENV=test \
  SHADOWOPS_START_PERSISTENCE=false \
  mix test --seed 12345

bash scripts/credo_regression_gate.sh
mix dialyzer
mix sobelow --exit
mix shadowops.registry validate
mix shadowops.workflow_ids.validate
mix hex.audit
git diff --check
```

Verify rendered UI/API output does not leak private absolute local paths.

## Commit and push authorization

The user explicitly authorizes staging task-related files, commit and push to `auto/opencode-work`.

Before commit inspect `git diff`, `git diff --check` and `git status`; stage no secrets, build outputs, temporary files or unrelated changes.

Preferred coherent commits:

- `fix: enforce credo regression certification`
- `feat: refine mission control operations UI`

One combined commit is acceptable if cleaner.

Push with normal fast-forward semantics only:

```bash
git push origin auto/opencode-work
```

After push local HEAD must equal `origin/auto/opencode-work`.

## Immutable 4014 preview

After the final commit is pushed, build exactly that SHA outside `/tmp` under:

`$HOME/.local/lib/shadowops-preview/<FINAL_GIT_SHA>/source`

Use a detached worktree, build the prod release there and point only `shadowops-preview.service` to the immutable release.

Preserve hardening:

- `PrivateTmp=true`
- `NoNewPrivileges=true`
- `ProtectSystem=full`

Verify `/health`, `/ready` and `/` return 200, preview identity matches the final SHA, no private path leak exists, and the stable 4013 PID is unchanged.

## Safe 4015 certification

4015 is ephemeral certification only.

If already occupied, prove exact listener ownership before TERM. Never generic-kill `beam.smp` or `shadowops`; never auto-escalate to KILL. If ownership cannot be proven, stop with `4015_UNKNOWN_PROCESS`.

Then run exactly:

```bash
SHADOWOPS_CERT_BRANCH=auto/opencode-work \
SHADOWOPS_CERT_REMOTE_REF=origin/auto/opencode-work \
SHADOWOPS_CERT_PREVIEW_PORT=4014 \
SHADOWOPS_CERT_SMOKE_PORT=4015 \
bash scripts/certify_all_developments.sh
```

If certification fails, repair only the exact legitimate gate, commit/push if source changes, rebuild 4014 for the new final SHA, then rerun 4015. Local HEAD, remote HEAD, 4014 preview SHA and certificate SHA must all match.

## Stable 4013 prohibition

Never run `scripts/promote_stable_4013.sh` and never set `SHADOWOPS_PROMOTE_STABLE=YES`.

Do not restart, stop, deploy to or otherwise mutate 4013. Stable promotion requires a separate explicit user instruction.

## Final acceptance

Only declare `FINAL_STATUS=SHADOWOPS_MASTER_CANDIDATE_CERTIFIED` when all of these are proven:

- design refinement complete
- source truth unchanged
- fake data added = no
- private path leak = no
- format/compile/targeted/full tests pass
- Credo regression gate pass with `CREDO_NEW=0`
- Dialyzer/Sobelow/registry/workflow IDs/Hex audit/diff check pass
- commit created and pushed
- local HEAD = remote HEAD
- 4014 runs exact final HEAD and health/ready/root pass
- official 4015 certification pass
- certificate exists for final HEAD
- 4013 PID unchanged
- 4013 promotion not performed

Final stdout should be a concise evidence block with exact pass/fail values and `FAIL_REASON` if blocked.
