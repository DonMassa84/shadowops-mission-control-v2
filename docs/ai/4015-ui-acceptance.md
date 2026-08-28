# 4015 UI Acceptance — ShadowOps Mission Control

**Date:** 2026-08-28  
**Branch:** `local/all-developments`  
**Code candidate:** `a466e774e7cb8a08bae947d21dc439bc57d2a211`  
**Runtime:** `http://127.0.0.1:4015` (ephemeral acceptance preview; never production)

---

## Evidence Provenance

The route, performance and quality-gate evidence below was collected from the 4015 acceptance workspace based on `b4eed982b8e5bf519722f560227da68cdf06fbc8` with the knowledge-probe optimization subsequently committed as `a466e774e7cb8a08bae947d21dc439bc57d2a211`.

The previous version of this document incorrectly presented `b4eed98` as the final branch HEAD after the optimization had already been committed. This revision separates the code candidate from the evidence provenance.

**Final exact-HEAD revalidation is required after this documentation commit.** The authoritative final result must be posted to Issue #27 without another branch mutation, so that `TESTED_HEAD == REMOTE_HEAD` can remain true. This document intentionally does not self-claim a future commit SHA.

---

## Executive Summary

The 4015 acceptance run verified the canonical Mission Control surfaces and showed the root timeout reduced from 13.7s to 3.0s after removing the expensive SQLite `PRAGMA quick_check` from the knowledge vector-store probe. The recorded local gates were green, but final acceptance remains **PENDING EXACT-HEAD REVALIDATION** until the current remote branch HEAD is re-tested after this documentation update.

---

## Route Verification Matrix

| Route | HTTP | Time | Classification | Notes |
|-------|------|------|----------------|-------|
| `/` (Dashboard) | 200 | 3.0s | CONNECTED | RuntimeOverview snapshot (16 parallel probes, max 2s) |
| `/workflows` | 200 | 0.2s | CONNECTED | Canonical + external + local evidence |
| `/workflows/:id` | 200 | 0.2s | CONNECTED | Detail with L2 approval UI |
| `/runs` | 200 | 0.004s | CONNECTED | Empty state handled |
| `/jobs` | 200 | 0.003s | CONNECTED | Oban not configured → NOT_CONFIGURED |
| `/approvals` | 200 | 0.004s | CONNECTED | One-click approve/reject buttons |
| `/services` | 200 | 1.1s | CONNECTED | 111 discovered via systemd/docker |
| `/nodes` | 200 | 0.03s | CONNECTED | 2 physical nodes (local + i7) |
| `/agents` | 200 | 0.66s | DEGRADED | systemd discovery, some DEGRADED |
| `/ai` | 200 | 0.003s | CONNECTED | Policy: REMOTE_ONLY, no local LLM |
| `/security` | 200 | 0.02s | CONNECTED | All 10 checks PASS |
| `/audit` | 200 | 0.004s | CONNECTED | 3 events, hash chain VALID |
| `/knowledge` | 200 | 0.46s | CONNECTED | 1985 docs, ChromaDB query_probe PASS |
| `/evidence` | 200 | 0.006s | CONNECTED | 44 artifacts, metadata only |
| `/social/messenger` | 200 | 0.66s | OPTIONAL_UNAVAILABLE | No source configured |
| `/social/whatsapp` | 200 | 0.73s | READY | Local export, 15 msgs, aggregate only |
| `/social/telegram` | 200 | 0.69s | READY | systemd discovery, 4 services |
| `/focus` | 200 | 0.01s | CONNECTED | LEARNING_FOCUS source AVAILABLE |
| `/compute` | 200 | 0.02s | CONNECTED | 2/2 nodes reachable |

---

## API Endpoint Performance

| Endpoint | Time | Status |
|----------|------|--------|
| `/api/health` | 0.13s | PASS |
| `/api/ready` | 0.01s | PASS |
| `/api/workflows` | 0.05s | PASS |
| `/api/runs` | 0.004s | PASS |
| `/api/approvals` | 0.005s | PASS |
| `/api/audit` | 0.006s | PASS |
| `/api/security/status` | 0.015s | PASS |
| `/api/knowledge` | 2.0s | PASS (under 3.5s probe timeout) |
| `/api/services` | 1.4s | PASS (under 3.5s probe timeout) |
| `/api/nodes` | 0.03s | PASS |
| `/api/agents` | 0.69s | PASS |
| `/api/ai/status` | 0.005s | PASS |
| `/api/evidence` | 0.009s | PASS |

**Optimization applied:** removed `PRAGMA quick_check` (11.7s) from the knowledge vector-store probe. The probe now uses document count, collection record count and a query probe.

---

## UI Contract Compliance

### Source-State Contract
- All surfaces report `AVAILABLE`/`CONNECTED`, `UNAVAILABLE`, or `OPTIONAL_UNAVAILABLE`.
- Empty stores are valid connected states (runs and approvals show no records).
- No synthetic `READY` claims are accepted as production evidence.

### Write Invariants
- Write token required (`SHADOWOPS_WRITE_TOKEN`).
- Fails closed without token (503 on unauthenticated run attempt).
- Workflow execution requires an APPROVED durable record.
- Lifecycle transitions validated: `QUEUED → RUNNING → SUCCESS|FAILED|BLOCKED`.
- Approval terminal states are immutable.
- Audit chain exposes previous/current hash linkage.
- Execution uses argv-style invocation rather than shell interpolation.

### Privacy & Availability
- Evidence/Knowledge: metadata only, no content or absolute paths exposed.
- Nodes/Agents/Logs: `NOT_CONNECTED`/`OPTIONAL_UNAVAILABLE` until a canonical source exists.
- Messenger/WhatsApp/Telegram: privacy-guarded aggregates only.
- Security: no secrets rendered; redaction self-check recorded PASS.

---

## RUNNABLE vs REFERENCE_ONLY UI

**Workflows page (`/workflows`):**
- Canonical executable workflows → “Approve & run” control (disabled if no write token).
- Canonical non-runnable workflows → review/detail control.
- Local evidence (`REFERENCE_ONLY`) → evidence/integration path, not direct execution.
- External runtime sets → source navigation.
- Local discoveries receive deterministic `localwf_*` IDs but remain `REFERENCE_ONLY` until runtime and governance mapping are proven.

**Workflow Detail (`/workflows/:id`):**
- Shows approval-required badge for high-risk workflows.
- Provides approval/run control only through the governed path.
- Documents authorization chain: Policy → ApprovalStore → PrivacyGate → ExecutionService → Audit.

---

## Approval-Required UI

**Approvals page (`/approvals`):**
- PENDING approvals expose approve/reject controls.
- Non-PENDING states are shown as final/immutable.
- Audit reference is visible.
- Controls are disabled when the write token is not configured.

**Workflow Detail:**
- Approval requirement remains visible.
- Governed execution creates/uses approval and records the result in audit evidence.
- Approval review remains accessible separately.

---

## Navigation Verification

Sidebar groups recorded during the acceptance run:
- **Dashboard**: Overview
- **Operations**: Compute, Workflows, Runs, Jobs, Services, Backups
- **Sources**: Integrations, Evidence, Knowledge
- **Governance**: Approvals, Security, Audit, Logs
- **Focus & AI**: Focus, AI, Agents

All recorded links resolved successfully during the acceptance run.

---

## Recorded Quality Gates

| Gate | Recorded result |
|------|-----------------|
| `mix format --check-formatted` | PASS |
| `mix compile --warnings-as-errors` | PASS |
| `MIX_ENV=test mix test --seed 12345` | 106 passed |
| `mix credo --strict` | PASS (0 errors; refactoring warnings noted) |
| `mix dialyzer` | DEGRADED (34 reported as pre-existing) |
| `mix sobelow --exit` (shadowops_web) | DEGRADED (4 reported as pre-existing) |
| `mix shadowops.registry validate` | PASS |
| `mix shadowops.workflow_ids.validate` | PASS |
| `mix hex.audit` | PASS |
| `git diff --check` | PASS |

These are **recorded local acceptance results**, not GitHub Actions status checks for the final remote HEAD.

---

## Local Acceptance Gates

| Gate | Recorded result |
|------|-----------------|
| FORMAT | PASS |
| COMPILE | PASS |
| TESTS | PASS (106) |
| MISSION_ROUTES | PASS (recorded route matrix) |
| PRIVACY_GATE | PASS |
| WRITE_BYPASS | BLOCKED without write token |
| SECRET_LEAK_SCAN | PASS |
| VISUAL_ACCEPTANCE | PASS during recorded 4015 run |

---

## Known Issues / Follow-up

1. Dashboard recorded at 3.0s during the acceptance preview.
2. Knowledge API recorded at 2.0s after probe optimization.
3. Services API recorded at 1.4s.
4. Static-analysis findings reported as pre-existing must remain visible rather than being silently reclassified.
5. Final exact-HEAD revalidation is mandatory after this document commit.

---

## Completion State

```text
BRANCH=local/all-developments
CODE_CANDIDATE_HEAD=a466e774e7cb8a08bae947d21dc439bc57d2a211
RECORDED_ACCEPTANCE_BASE=b4eed982b8e5bf519722f560227da68cdf06fbc8
KNOWLEDGE_PROBE_OPTIMIZATION_COMMITTED=YES
REMOTE_DOC_FIX_COMMIT=THIS_COMMIT
EXACT_HEAD_REVALIDATION=PENDING
GITHUB_ACTIONS_FOR_FINAL_HEAD=NOT_YET_PROVEN
4015_ROLE=ACCEPTANCE_PREVIEW_ONLY
4013_PRODUCTION_MUTATION=NO
FINAL_ACCEPTANCE=PENDING
```

### Finalization rule

After this documentation commit is pushed, test the **exact resulting remote HEAD** with formatting, compile, full tests and 4015 acceptance. Publish the final result to GitHub Issue #27 **without another commit to `local/all-developments`**. The final record must include:

```text
TESTED_HEAD=
REMOTE_HEAD=
REMOTE_HEAD_MATCH=YES|NO
FORMAT_RC=
COMPILE_RC=
FULL_TEST_RC=
4015_ACCEPTANCE=PASS|FAIL
CRITICAL_BLOCKERS=
FINAL_ACCEPTANCE=PASS|FAIL
4013_MUTATION=NO
```
