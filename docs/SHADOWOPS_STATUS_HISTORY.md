# ShadowOps — Chronological Project Status History

This document is the canonical human-readable timeline of ShadowOps Mission Control V2.

It complements Git history, pull requests, issues and CI by recording the **meaning of each project state**.

Evidence semantics are defined in `docs/history/README.md`.

---

## 2026-08-19 — Gate A hardened baseline

**Evidence:** `LOCAL_REPORTED`

Known project state from the earlier ShadowOps hardening line:

- format/compile/tests/registry/diff/fail-closed checks reported PASS
- fail-closed adapter behavior established
- Gate A classified as ready for Gate B
- Gate B remained blocked because required route/controller/runtime evidence was incomplete

**Status:** `PARTIAL`

**Meaning:** core governance and fail-closed mechanics were materially advanced, but production readiness was not yet evidenced end-to-end.

---

## 2026-08-23 — Runtime/control-plane evidence expansion

**Evidence:** `LOCAL_REPORTED`

Reported local milestones included:

- Phoenix runtime responding on the local ShadowOps port
- `/health` and `/ready` responding successfully in the evidenced runtime
- governed workflow/control-plane surfaces expanded
- WhatsApp end-to-end evidence reported PASS for the then-current integration path
- workflow registry and runtime evidence significantly expanded

**Status:** `PARTIAL`

**Non-claim:** these observations do not prove that every later branch or runtime instance inherited the same state.

---

## 2026-08-24 — Data Fabric V5 validated, real sources still absent

**Evidence:** `LOCAL_REPORTED`

Reported Phase 5 state:

- format PASS
- compile PASS
- full tests PASS
- Electron PASS
- entity resolution PASS
- relationships PASS
- timeline PASS
- signals PASS
- direct ingest bypass BLOCKED
- PrivacyGate PASS
- audit chain PASS
- Gmail/Calendar/Contacts/Documents/GitHub sources reported `NOT_CONFIGURED`
- `REAL_DATA_INGESTED=NO`

**Status:** `DATA_FABRIC_VALIDATED_WITHOUT_REAL_SOURCE_INGEST`

**Meaning:** architecture and governance paths were validated, but production claims requiring real source evidence remained blocked.

---

## 2026-08-25 — Privacy-safe health intake branch

**Evidence:** `REPO_VERIFIED` via PR `#1`

Branch: `feature/health-local-intake`

PR state at historical snapshot: open draft.

Implemented/intended scope recorded by the PR:

- local-only health canonical event types
- strict metadata whitelist
- sanitized local event persistence
- raw PDFs, identifying fields and attachments excluded from GitHub

**Status:** `OPEN / VALIDATION_REQUIRED`

---

## 2026-08-25 — Production hardening baseline

**Evidence:** `REPO_VERIFIED` via PR `#2`

Branch: `hardening/production-ready-2026-08-25`

Historical head recorded by PR metadata: `2ccf940c6633285d65235b330da81f258a2853ca`.

Major capabilities described by the PR include:

- production CI/release hardening
- fail-closed production runtime configuration
- Layer Health UI/API and truthfulness gates
- federated GitHub + ChatGPT project catalog path
- read-only `/api/projects`
- governed workflow/service execution
- approval/privacy/audit boundaries
- deterministic run evaluation
- optional PostgreSQL + Oban persistence path
- production acceptance and local handoff tooling

Critical contract:

- CI proves repository/release state, not external/local source connectivity
- external integrations remain non-positive until evidenced
- local production handoff requires separate runtime proof

**Status:** `OPEN DRAFT / PRODUCTION-HANDOFF CANDIDATE`

---

## 2026-08-25 — ChatGPT ↔ OpenCode GitHub MCP merged

**Evidence:** `REPO_VERIFIED` via merged PR `#3`

Merged into `main` on 2026-08-25.

Purpose:

- GitHub becomes the auditable handoff/source-of-truth layer between ChatGPT and OpenCode
- OpenCode GitHub MCP is read-only
- publishing remains explicit through normal Git/GitHub operations
- secrets/private raw runtime data remain local

**Status:** `MERGED`

---

## 2026-08-25 — Read-only ShadowOps runtime MCP gateway

**Evidence:** `REPO_VERIFIED` via PR `#4`

Branch: `integration/shadowops-runtime-mcp`

Recorded design:

- read-only MCP tools for existing Phoenix GET endpoints
- write/action paths rejected at the gateway boundary
- response redaction and bounded payloads
- loopback-by-default exposure
- no production runtime restart performed by the PR

**Status:** `OPEN`

---

## 2026-08-26 — Fail-closed ChatGPT source evidence pipeline

**Evidence:** `REPO_VERIFIED` + partial `CI_VERIFIED` via PR `#7`, Issues `#5` and `#6`

Branch: `feat/chatgpt-source-evidence`

Recorded head during the snapshot process: `9d409a1a5cbe836b3e92265e6937825fbcd9efe9`.

Implemented scope:

- fail-closed local ChatGPT export reader
- bounded project metadata projection only
- no raw messages, attachments, credentials or local paths in normalized records
- provider-aware federated catalog merge
- truthful `READY` semantics
- ChatGPT domain/import evidence emitted only after verified source evidence
- tests for missing/invalid source, privacy projection and merge semantics

CI evidence observed for the current PR line:

- format PASS
- compile with warnings-as-errors PASS
- full tests PASS
- Credo strict PASS
- later hardening gates were still running at the time of the snapshot

**Status:** `IMPLEMENTED / MERGE BLOCKED BY REMAINING GATES`

---

## 2026-08-26 — Local ChatGPT source discovery correctly fails closed

**Evidence:** `LOCAL_REPORTED`

Local evidence reported:

- no unpacked supported ChatGPT export found in the searched user directories
- no matching ZIP export found
- `CHATGPT_SOURCE_GATE=BLOCKED`
- reason: `NO_LOCAL_CHATGPT_EXPORT_FOUND`
- ChatGPT domain remained `NOT_CONFIGURED / UNAVAILABLE`
- ChatGPT import evidence file remained absent
- project catalog retained ChatGPT as `NOT_CONFIGURED`, `real_data=false`, `reachable=false`

**Status:** `EXPECTED_FAIL_CLOSED`

**Meaning:** absence of a real source is not an implementation failure; it is a valid non-READY state.

---

## 2026-08-26 — Local runtime/source drift detected

**Evidence:** `LOCAL_REPORTED`

Observed local state at the reported runtime snapshot:

- local `feat/chatgpt-source-evidence` checkout was behind remote because an uncommitted test-file change blocked fast-forward
- local HEAD reported as `2ccf940c6633285d65235b330da81f258a2853ca`
- remote feature head was `9d409a1a5cbe836b3e92265e6937825fbcd9efe9`
- port `4014` had no listener
- port `4013` had an active Phoenix/BEAM listener
- `4013 /health = 200`
- `4013 /ready = 200`
- `4013 /projects = 500`
- `4013 /projects/chatgpt = 404`
- runtime log referenced `ShadowOpsWeb.ProjectsLive.render/1`, indicating source/build/runtime drift relative to the newer project-domain implementation line

**Status:** `BLOCKED_RUNTIME_ALIGNMENT`

**Required next action:** preserve local changes, synchronize the feature branch, determine the exact running checkout/build, repair only the proven root cause, rerun quality gates, then align the canonical runtime.

---

## 2026-08-26 — Persistent OpenCode ↔ ChatGPT GitHub handoff

**Evidence:** `REPO_VERIFIED` via Issue `#8`

Issue `#8` establishes a persistent bounded evidence channel:

- `[CHATGPT_TASK]` for work instructions
- `[OPENCODE_RESULT]` for sanitized results
- no secrets/raw private data in GitHub
- branch/SHA/test/CI/runtime status and blocker codes are allowed evidence

**Status:** `ACTIVE`

---

# Current interpretation

As of this chronology snapshot, the project has strong governance, test and production-hardening foundations, but **production readiness remains conditional on evidence**.

The highest-priority open chain is:

`branch synchronization → runtime drift/root-cause closure → full hardening gates → real-source evidence where required → controlled runtime alignment → merge decision`

Operating rule:

`FINISH BEFORE EXPAND`
