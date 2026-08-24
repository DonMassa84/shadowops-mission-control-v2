# Workflow overlay deploy orchestration

The machine-local workflow overlay is activated only after `Deploy ShadowOps Mission Control Safely` completes successfully on `main`.

Sequence:

1. Safe deploy validates and activates the isolated ShadowOps release with its existing rollback guard.
2. `ShadowOps Workflow Overlay Live Acceptance` is triggered by the completed safe-deploy workflow.
3. The overlay job validates the local registry file, adds the dedicated systemd environment drop-in, restarts the Phoenix service with rollback protection, and verifies `/health` and `/ready`.
4. `ShadowOpsCore.WorkflowSource` must report `local_overlay_status.status == "LOADED"` and exactly 192 merged workflows (9 canonical base workflows plus 183 machine-local workflows).
5. `/workflows` and `/api/workflows` must both return HTTP 200.
6. The result is published to the deployed commit as `shadowops/workflow-overlay-live`.

The local overlay remains outside Git and the canonical repository registry wins key collisions. Disconnected executors remain fail-closed and L2/L3 execution remains approval-gated.
