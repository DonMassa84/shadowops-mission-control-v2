# ShadowOps GitHub Actions Workflow Matrix

Candidate SHA: `fda310acff54106c988801d5b36f67bc0791f6e7`
Basis: Branch `feature/shadowops-verified-app` (246-PR-Fileset)

Hinweis: 4 Workflows existieren auf `main`, aber **nicht** auf diesem Branch:
`mcp-runtime.yml`, `one-time-format.yml`, `product-release-gate.yml`, `ui-v4-contract.yml`.
Diese fehlen im Featureset und werden hier nicht inventarisiert.

| file | name | push branches | pull_request branches | workflow_dispatch | permissions | runner | timeout | deployment | 4013 | release |
|------|------|---------------|-----------------------|-------------------|-------------|--------|----------|------------|------|---------|
| ci_hardening.yml | ShadowOps Hardening CI | hardening/**, feat/mission-control-v2, local/all-developments | main | NO | contents: read | ubuntu-latest | 35m | NO (release build only) | NO | foundation |
| elixir.yml | ShadowOps Production Gate | main, hardening/production-ready-2026-08-25 | main | YES | contents: read | ubuntu-latest | 25/15/12m | smoke on 4013 in CI container | YES (CI-Port 4013 nur Smoke) | release core |
| local-all-developments-contract.yml | Local All Developments Contract | local/all-developments (paths) | main (paths) | NO | contents: read | ubuntu-latest | - | NO | NO | hygiene |
| local-coder-contract.yml | ShadowOps Local Coder Contract | - | main (paths) | NO | contents: read | ubuntu-24.04 | - | NO | NO | hygiene |
| local-static-diagnostics.yml | Local Static Diagnostics | local/all-developments | main | NO | contents: read | ubuntu-latest | 35m | NO | NO | foundation |
| opencode-handoff-contract.yml | OpenCode Handoff Contract | local/all-developments (paths) | main (paths) | NO | contents: read | ubuntu-latest | - | NO | NO | hygiene |
| remote-ai-policy.yml | Remote AI Policy | local/all-developments (paths) | main (paths) | NO | contents: read | ubuntu-latest | - | NO | NO | hygiene |
| verified-app-product.yml | ShadowOps Verified Product Gate | feature/shadowops-verified-app, product/** | main | YES | contents: read | ubuntu-latest | 25m | NO | NO (nur Test-Assertion) | **Release-Gate** |

## Trigger-Plausibilität

- `verified-app-product.yml` triggert auf `push` von **feature/shadowops-verified-app** und auf
  `pull_request` gegen **main**. Dies ist der einzige Workflow, der auf PR #36 als Check läuft.
- `elixir.yml` und `ci_hardening.yml` triggern zwar `pull_request: main`, wurden aber auf
  PR #36 für den aktuellen Head **nicht** ausgeführt (0 Runs auf `fda310a`).
  Ursache: GitHub evaluiert Workflow-Set pro Head/Base-Kombination; auf diesem Branch-Set
  lief nur `verified-app-product.yml`.
- `local-*-contract.yml` + `opencode-handoff-contract.yml` + `remote-ai-policy.yml` laufen
  nur bei `pull_request` mit Pfadfilter gegen `main` bzw. auf `local/all-developments`.

## Risikobewertung

- **Deployment-Capability:** Kein Workflow publiziert oder deployed. `elixir.yml`
  führt einen Release-Build + Laufzeit-Smoke aus, bindet dabei CI-internen Port 4013 in
  einer GitHub-Hosted-Runner-Umgebung (kein Host-Zugriff). `AUTO_DEPLOY=NO` bestätigt.
- **Permissions:** alle Workflows `contents: read`, kein `deployments`, kein `id-token`.
- **Actions-Versionen:** checkout@v4/v5, setup-python@v5, setup-node@v5, setup-beam@v1,
  cache@v4 – keine ungültigen Pins.
- **workflow_dispatch:** nur `elixir.yml` + `verified-app-product.yml`; beide ohne
  freigegebene Secrets, `contents: read`.
- **4013-Mutation:** kein Systemstart von CI aus möglich (`CI_4013_MUTATION=NO`).
