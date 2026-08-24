# ShadowOps deploy observability

The safe local Mission Control deployment remains fail-closed and rollback-protected.

A companion `workflow_run` observer publishes the completed deployment result to the deployed commit as the GitHub status context `shadowops/deploy`.

This status is evidence only. It does not bypass or replace the existing runtime gates, privacy checks, route checks, rollback guard, or release retention logic.

Expected terminal states:

- `success` — the safe deploy workflow completed successfully.
- `failure` — the safe deploy workflow failed or timed out.
- `error` — the deploy was cancelled, skipped, or ended in another non-success state.

The observer runs only for deploy workflow runs whose head branch is `main`.
