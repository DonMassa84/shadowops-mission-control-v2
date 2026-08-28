# Independent Workflow Census — Second Instance

- **Second instance:** YES
- **Isolated branch:** `audit/workflow-census-second-instance` (worktree `../shadowops-workflow-census-second`)
- **Base SHA:** `fda310acff54106c988801d5b36f67bc0791f6e7` (= `origin/feature/shadowops-verified-app` HEAD, = PR #36 head oid)
- **Role:** independent auditor / census worker / evidence builder. No shared-branch edits, no merge, no deploy, no 4013/4014 mutation, no secrets.

## Phase 2 — Remote truth
- PR #36: state=OPEN, isDraft=false, mergeable=**CONFLICTING**, baseRef=main, headRef=feature/shadowops-verified-app, headRefOid=fda310a.
- Latest run on branch: `ShadowOps Verified Product Gate` run 33193759820 → **FAILURE** (2026-08-28). All recent runs on this branch are failing/cancelled.
- Product gate failure means the verified-app branch is NOT currently green upstream.

## Phase 3 — Census by source set
| Set | Count | In repo? | Status |
|-----|-------|----------|--------|
| central_registry (workflow_registry_v2.yaml `workflows:`) | 9 | YAML entries present; 0 backing impl files | REGISTERED/NOT_CONFIGURED |
| shadowmaker_tasks (external TCC) | 48 | external (evidenced by name) | UNKNOWN in repo |
| whatsapp_agent_pack | 16 | subset of 48; per verified_app/data/workflows.json | 12 ACCEPTED / 2 BLOCKED(runtime) / 2 BLOCKED(approval) |
| opencode_standard | 7 | external, NOT_IMPORTED | UNKNOWN |
| telegram_workflow_controller | 6 | external, NOT_IMPORTED | UNKNOWN |
| federation (workflow_ids.yaml) | 4 | external ref to DonMassa84/shadowops | UNKNOWN |
| github_actions (`.github/workflows/`) | 8 | present as `.yml` | 7 safe, 1 starts 4013 |

**Unique workflow slots = 82** = 9 + 48 + 7 + 6 + 4 (federation) + 8 (GA). WhatsApp 16 is correctly counted *inside* the 48 (not double-counted). `config/workflow_registry.yaml` (legacy) does **not** exist.

## Phase 4 — Classification highlights
All 9 central-registry workflows: `definition_status=REGISTERED` but **0 have a backing implementation file in this repo** (docs/finanzen/*, config/agents/finanzen/*, app/ihk_ai.py, config/career_email_only_workflow.yaml, .github/workflows/quality.yml, .github/workflows/finanzabgleich-gate.yml are all MISSING). Two CI-referenced definitions (`repository_quality`, `finance_quality_gate`) point at absent `.github` files → effectively `BLOCKED`/`NOT_CONFIGURED`. `career_funnel_ihk` is `DISABLED_BY_CONFIGURATION`.

WhatsApp (16): 12 ACCEPTED+VERIFIED (L0/L1), 2 BLOCKED runtime (whatsapp-doctor, whatsapp-meta-status), 2 BLOCKED approval (whatsapp-purge-expired, whatsapp-meta-subscribe, L2).

## Phase 5 — Real, testable candidates
15 safe-test candidates enumerated (see candidates.json): verified_app python unittest suite (16/16 PASS, port-free), `mix shadowops.registry validate`, `mix shadowops.workflow_ids.validate`, ops/mcp read-only tests + py_compile, the 4 local-contract / diagnostics / policy GitHub Actions (read-only), and verified-app-product gate (tests only). All are L0/CI, no secret, no external side effect, no 4013/4014.

## Phase 7 — GitHub Actions
8 workflows analyzed (see github_actions_matrix.md). Only `elixir.yml` would start PORT 4013 (release_runtime_gate). It was NOT triggered. No workflow was manually triggered.

## Phase 9 — Executed safe tests
- `python3 -m unittest discover -s verified_app/tests` → **16/16 PASS**
- YAML static validation (`workflow_registry_v2.yaml`, `workflow_ids.yaml`) → OK
- JSON validation (`verified_app/data/workflows.json`) → OK
- `ops/mcp/shadowops_runtime_mcp.py` py_compile → OK
- Local contract scripts (`test_local_all_developments_contract.sh`, `test-shadowops-coder.sh`) → read-only; they FAIL on this isolated audit branch (KeyError 'model' / 'protected branch gate failed') — expected branch-context behavior, no mutation.

## Key findings
1. PR #36 is CONFLICTING + its Verified Product Gate is FAILING → release currently blocked upstream.
2. `elixir.yml` starts PORT 4013 — never triggered.
3. Legacy `config/workflow_registry.yaml` absent though referenced by compatibility block.
4. `repository_quality` & `finance_quality_gate` reference missing `.github` definition files.
5. 0 of 9 central-registry workflows have verifiable in-repo implementation files.
6. Strongest in-repo runtime candidate = verified_app python unittest suite (port-free, secret-free).

## Integrity attestation
- PRODUCT_FILES_MUTATED=NO
- 4013_MUTATION=NO, 4014_MUTATION=NO
- MERGE=NO, DEPLOY=NO
- No secrets accessed or written.
