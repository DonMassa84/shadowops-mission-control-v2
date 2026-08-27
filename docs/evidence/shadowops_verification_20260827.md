# ShadowOps Verification Snapshot — 2026-08-27

## Purpose

Version-controlled evidence snapshot for the ShadowOps functional-core hardening and workflow-discovery state. This document distinguishes local operator evidence from independently visible GitHub evidence and does not claim production readiness beyond what is proven.

## Repository scope

- Repository: `DonMassa84/shadowops-mission-control-v2`
- Evidence branch: `fix/functional-core-20260826`
- Verified source commit: `463bc79b5534637bcfeba426dd5cb62a3653c5ee`
- Pull request: `#21` — `Make ShadowOps useful: WebMCP, remote-only AI and feature recovery`
- PR state at verification: open, draft, not merged
- Merge performed by this verification: `NO`
- Deploy performed by this verification: `NO`

## Local acceptance evidence

The operator supplied the following exact-head test output for commit `463bc79b5534637bcfeba426dd5cb62a3653c5ee`:

```text
Finished in 84.1 seconds (0.4s async, 83.7s sync)
Result: 106 passed

=== FINAL ===
EXPECTED_HEAD=463bc79b5534637bcfeba426dd5cb62a3653c5ee
MERGE=NO
DEPLOY=NO
```

A negative API path was also observed:

```text
GET /api/audit/audit_unknown
ShadowOpsWeb.AuditController.show/2
Sent 404
```

Interpretation:

- local test baseline: `106/106 PASS`
- unknown audit IDs fail explicitly with HTTP `404`
- no merge or deployment was part of the acceptance run
- this is local operator evidence, not GitHub Actions CI evidence

## High-risk workflow hardening

Commit `463bc79b5534637bcfeba426dd5cb62a3653c5ee` changes `apps/shadowops_core/lib/shadow_ops_core/local_workflow_evidence_store.ex` to persist `approval_ref` and enforce execution approval for L2/L3 workflow evidence.

Effective rule:

```text
executable = true
AND risk_level in {L2, L3}
AND approval_ref is missing or empty
=> {:error, :approval_required_for_execution}
```

Additional behavior:

- `approval_required` is true for L2/L3 records
- `approval_ref` is persisted in the evidence record
- unknown `localwf_*` IDs fail with `{:error, :unknown_workflow_id}`
- invalid workflow identifiers continue to fail closed

This is evidence of a fail-closed activation contract for high-risk local workflow evidence. It does not by itself prove that every workflow is production-ready.

## GitHub exact-head verification

GitHub inspection confirmed:

- commit `463bc79b5534637bcfeba426dd5cb62a3653c5ee` exists
- it is the head of branch `fix/functional-core-20260826`
- PR `#21` points to this head and remains a draft
- repository `main` was not at this commit at verification time
- exact-head GitHub commit status had no reported status contexts
- exact-head GitHub check-runs count was `0`
- exact-head GitHub Actions workflow-runs count was `0`

Therefore:

```text
LOCAL_TEST_GATE=PASS
GITHUB_CI_EXACT_HEAD=NOT_PROVEN
```

The local `106 passed` result must not be represented as an independent GitHub CI run.

## Local workflow correlation evidence

Versioned evidence in `docs/evidence/local_workflow_correlation_20260827.md` records a read-only correlation scan with:

```text
HIGH_VALUE_CANDIDATES=8
STRONG_CANDIDATES=1
WORKFLOW_CANDIDATES=0
FINAL_STATUS=HIGH_VALUE_WORKFLOW_CORRELATION_PASS
```

Correlated sources include:

- Projects
- DokumentenSystem
- ProofFlow-Obsidian-Vault
- actions-runner-host
- auto_bewerbungen
- whatsapp-agent
- matrix_shadowops
- shadowops-local-hold
- openclaw-workspace

The scan explicitly recorded:

```text
SECRET_VALUES_READ=0
SECRET_VALUES_EXPOSED=0
SOURCE_MUTATIONS=0
EXECUTION_ATTEMPTS=0
```

Presence of a local path, file, service, timer, repository, listener, entrypoint, test reference, or governance reference is discovery evidence only. It is not execution permission or production-readiness evidence.

## Local capability mapping

Versioned evidence in `docs/evidence/local_capability_mapping_20260827.md` records:

```text
HIGH_VALUE_CANDIDATES=8
STRONG_CANDIDATES=1
WORKFLOW_CANDIDATES=0
CAPABILITY_CANDIDATES_MAPPED=9
```

All nine mapped candidates were non-executable at the recorded snapshot.

Promotion contract:

```text
DISCOVERED != CONFIGURED
CONFIGURED != REACHABLE
REACHABLE != REAL_DATA
```

`READY` requires verified configuration, reachability, real data, and governance mapping where execution is possible.

Workflow/script candidates remain `REFERENCE_ONLY` until all required controls are proven:

1. adapter exists
2. RiskPolicy mapping exists
3. CapabilityRegistry mapping exists
4. ExecutionService routing exists
5. PrivacyGate is applied
6. Audit evidence is produced
7. runtime verification passes

## Curated workflow lifecycle

PR `#21` documents the evidence-first lifecycle:

```text
DISCOVERED
-> NORMALIZED
-> CONNECTED
-> TESTED
-> PRODUCTION_READY
```

Fail-closed promotion rules:

- file presence may reach `NORMALIZED` only
- `CONNECTED` requires runtime verification, real data, and reachability
- `TESTED` additionally requires explicit execution-test evidence
- `PRODUCTION_READY` additionally requires governance mapping and executable status
- duplicate candidates are grouped for review, never silently merged or deleted

## Current evidence status

| Gate | Status | Evidence basis |
|---|---|---|
| Exact source commit exists | PASS | GitHub commit object |
| Local automated tests | PASS | operator output: `106 passed` |
| Unknown audit ID negative path | PASS | operator runtime/test output: HTTP `404` |
| L2/L3 approval evidence contract | PASS | commit diff in `LocalWorkflowEvidenceStore` |
| Unknown local workflow ID fail-closed | PASS | commit diff |
| Workflow discovery/correlation | PASS | versioned local correlation evidence |
| Capability candidate mapping | PASS | versioned capability mapping |
| Secret exposure during discovery | PASS | `SECRET_VALUES_EXPOSED=0` |
| Automatic source mutation during discovery | PASS | `SOURCE_MUTATIONS=0` |
| Automatic execution during discovery | PASS | `EXECUTION_ATTEMPTS=0` |
| GitHub CI on exact head | OPEN | no status/check/workflow runs found |
| Real workflow execution E2E | OPEN | not proven by discovery evidence |
| Production-ready workflow count | OPEN | must be proven individually |
| Merge | NO | PR remains draft/unmerged |
| Deploy | NO | no deployment included in evidence run |

## Required next gate

Do not add feature breadth before completing the real-workflow evidence gate.

Required chain for each workflow promoted beyond discovery:

```text
REAL SOURCE
-> INGEST / ADAPTER
-> CapabilityRegistry
-> Policy / Risk
-> Approval where required
-> PrivacyGate
-> ExecutionService
-> EXECUTION
-> RESULT
-> Audit / Events
```

Required machine-readable final metrics:

```text
WORKFLOWS_DISCOVERED=
WORKFLOWS_UNIQUE=
WORKFLOWS_DUPLICATES=
WORKFLOWS_CONNECTED=
WORKFLOWS_TESTED=
WORKFLOWS_E2E_VERIFIED=
WORKFLOWS_PRODUCTION_READY=
WORKFLOWS_MOCK_ONLY=
WORKFLOWS_BLOCKED=
```

## Verification conclusion

```text
SHADOWOPS_LOCAL_TEST_GATE=PASS
SHADOWOPS_HIGH_RISK_APPROVAL_GATE=PASS
SHADOWOPS_DISCOVERY_GATE=PASS
SHADOWOPS_GITHUB_CI_EXACT_HEAD=OPEN
SHADOWOPS_REAL_WORKFLOW_E2E_GATE=OPEN
MERGE=NO
DEPLOY=NO
```

The verified ShadowOps state is strong at code/test/governance-discovery level. Production readiness must remain capability-specific and evidence-driven; no discovered workflow is considered production-ready solely because it exists or has references in code, configuration, tests, services, or documentation.
