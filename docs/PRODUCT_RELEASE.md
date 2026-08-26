# ShadowOps Mission Control V2 — Product Release Contract

ShadowOps Mission Control V2 is a Phoenix/LiveView local control plane for operational visibility, governed workflows, evidence, approvals, audit, project federation, infrastructure and AI governance.

## Product identity

- Canonical web stack: Phoenix + LiveView
- Stable runtime port: `4013` (promotion only after certification)
- Product preview port: `4014`
- Certification smoke port: `4015`
- AI execution policy: `REMOTE_ONLY`
- Local AI inference: forbidden for ShadowOps coding and automation
- Write actions: governance-gated and audited
- Truth model: unavailable or unverified sources must not be presented as READY

## Finished product UX

The Mission Control UI provides:

- persistent operational sidebar
- command-center dashboard
- status-first cards and evidence-backed tables
- keyboard-accessible command palette (`Ctrl/Cmd+K` or `/`)
- responsive mobile layout
- reduced-motion support
- dedicated AI Governance surface
- explicit `REMOTE_ONLY`, `FORBIDDEN` local-model execution and no-fallback presentation
- approvals, audit, evidence, security, workflows, runs, nodes, services, projects, social, career and knowledge surfaces

The UI remains a thin view over the canonical Phoenix control plane. It does not become an authority for actor identity, risk, approvals, runtime state or execution policy.

## Local product preview

Use an isolated worktree so ongoing development on `local/all-developments` is not disturbed:

```bash
cd /home/schattenmacher/Projects/shadowops-mission-control-v2
git fetch origin --prune

PREVIEW=/home/schattenmacher/Projects/shadowops-product-preview
rm -rf "$PREVIEW"
git worktree add "$PREVIEW" origin/release/product-finish-2026-08-26
cd "$PREVIEW"
git switch -c release/product-finish-2026-08-26 --track origin/release/product-finish-2026-08-26 2>/dev/null || true

bash scripts/product_preview.sh
```

Expected final output:

```text
HEALTH_HTTP=200
READY_HTTP=200
UI_HTTP=200
URL=http://127.0.0.1:4014/
COMMAND_PALETTE=CTRL_K_OR_SLASH
FINAL_STATUS=PRODUCT_PREVIEW_PASS
```

Port `4013` is not modified by the product preview launcher.

## Product acceptance

Run:

```bash
bash scripts/product_acceptance.sh
```

For the full Dialyzer gate:

```bash
SHADOWOPS_PRODUCT_DIALYZER=1 bash scripts/product_acceptance.sh
```

The acceptance contract checks:

- clean release-candidate worktree
- Mission Control client syntax
- remote-only AI contract
- read-only MCP contract
- format
- compile with warnings as errors
- full deterministic ExUnit suite
- Credo strict for every Elixir source changed since the immutable pre-finish baseline
- full-repository Credo legacy-debt report (visible, non-blocking)
- Sobelow
- workflow registry
- workflow IDs
- Hex audit
- diff check
- atomic single-use approval implementation markers
- source integrity

The release-delta baseline is commit
`b521fafa1e8e5ad5a55edf8b5107edfe75ddfaa4`. This keeps all product-finish
Elixir changes under a strict blocking gate without misrepresenting the existing
repository-wide Credo backlog as a regression. Override it only with an audited
commit via `SHADOWOPS_CREDO_BASE_REF`.

A passing acceptance report ends with:

```text
SHADOWOPS_PRODUCT_ACCEPTANCE
AI_EXECUTION_POLICY=REMOTE_ONLY
PORT_4013_CHANGED=NO
DEPLOY_TRIGGERED=NO
FAIL_REASON=NONE
FINAL_STATUS=PRODUCT_ACCEPTANCE_PASS
```

## Promotion contract

Do not promote to stable `4013` unless all of the following are evidenced:

1. atomic single-use approval consumption is implemented and its negative/concurrency tests pass
2. product release gate is green
3. `scripts/certify_all_developments.sh` completes successfully on the final consolidated HEAD
4. release smoke on `4015` passes
5. intentional rollback drill has been proven
6. final HEAD is the exact HEAD being promoted
7. stable promotion is explicitly requested

Stable promotion remains an explicit action. Preview or CI success must never silently mutate `4013`.

## Source truthfulness

A connector, adapter or UI page existing in the repository does not prove a live source connection. Gmail, Calendar, Contacts, Drive, GitHub, messaging, finance and other integrations must report their actual evidence-backed state. `NOT_CONFIGURED`, `NOT_CONNECTED`, `DEGRADED` and `UNAVAILABLE` are valid product states and must remain visible rather than being replaced with synthetic READY data.

## Release status terminology

- `DEVELOPMENT`: implementation still changing
- `RELEASE_CANDIDATE`: product surfaces are assembled but one or more required release gates are still pending
- `CERTIFIED`: all deterministic certification gates passed for an exact HEAD
- `STABLE`: that certified exact HEAD was deliberately promoted to port `4013` and post-promotion health/readiness succeeded

Do not use `PRODUCTION_READY` or `STABLE` without the corresponding evidence.
