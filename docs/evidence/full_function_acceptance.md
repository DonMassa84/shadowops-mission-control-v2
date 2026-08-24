# ShadowOps full-function release acceptance

Acceptance timestamp: `2026-08-23T01:31:57+02:00`

Git reference: `c5797bc93f0a4918bc52d7594de3e8db7e266d54` on branch `shadowops-mission-control-1.0.0rc1`, plus the inspected release worktree documented here. No push or merge was performed.

This is the historical 42-test Mission Control acceptance. The superseding 1.0.1 release passed 69 tests and the final CI/deployment/physical gates documented in `shadowops_1_0_1_release.md`; the original observations below are retained rather than rewritten.

## Release result

`FINAL_STATUS=RELEASE_READY`

The canonical Phoenix umbrella remains the only product architecture. This release pass added no optional connector and no synthetic operational state. The accepted architecture is frozen after the gates below; subsequent product changes require a new change set and acceptance run.

## Executed gates

| Gate | Result | Evidence |
| --- | --- | --- |
| Format | PASS | `mix format --check-formatted` |
| Compile | PASS | `mix compile --warnings-as-errors` |
| Tests | PASS_42 | 9 `shadowops_core`, 9 `workflow_engine`, 15 `shadowops_web`, 9 `agent_runtime` |
| Diff whitespace | PASS | `git diff --check` |
| Dependency advisories | PASS | `mix hex.audit`: no retired or security advisory packages |
| Route discovery | PASS | All 57 routes from `mix phx.routes` are classified in `full_route_inventory.md` |
| HTTP sweep | PASS | Every concrete UI/read route returned its expected status and body; known dynamic detail routes returned 200, unknown IDs returned JSON 404 |
| Browser verification | PASS | Required desktop pages, responsive dashboard and i7 were rendered with installed headless Chrome; LiveView WebSocket connection was observed |
| Audit integrity | VALID | `/api/audit/verify` returned `valid:true` after authenticated approval and workflow-run acceptance writes |
| Readiness | PASS | `/health` and `/ready` returned HTTP 200; required registry, audit and learning-plan checks were healthy |
| Security | PASS | Writes fail closed, authenticated actors are required, transitions are enforced, response headers and privacy scans passed |
| No fake data | PASS | Runtime scan found no synthetic operational adapter; optional sources stay explicit `NOT_CONNECTED` |

## Functions and source comparisons

- Dashboard, workflow registry, workflow detail, runs, approvals, audit, evidence, knowledge, Facebook, services, AI and security rendered from their real configured sources.
- The canonical registry contained five workflows. Search, category, domain, status and runtime filters, sorting and filter reset passed through LiveView without a full reload.
- Durable approvals covered create, approve, reject, expire, actor enforcement, illegal transition rejection, audit linkage and process-restart persistence.
- Durable runs covered `QUEUED`, `RUNNING`, `SUCCESS`, `FAILED` and `BLOCKED` transitions in isolated persistence tests. Live acceptance produced genuine `BLOCKED` and `FAILED` records: the safe `repository_quality` workflow is declared as `github_actions`, so local execution failed closed instead of fabricating success.
- The audit API remained append-only through the public router. Every record contained actor, action, resource, result, evidence reference and hash links; modification and deletion routes do not exist.
- Services returned 440 real records at acceptance: 434 systemd records plus six records matching `docker ps --all`. The aggregate source label accurately listed `systemctl --user / systemctl / docker ps`.
- The AI API returned 60 installed models, exactly matching `ollama list` with its header excluded.
- Knowledge metadata matched the allowlisted real stores. Evidence API artifact count matched the files under `docs/evidence`; private note bodies and sensitive absolute paths were not returned.
- Facebook rendered only the approved aggregate/formula source. No identities, raw messages, credentials or token values were exposed.
- Nodes, Agents, Logs, Messenger, WhatsApp and Telegram remain `NOT_CONNECTED`: this Phoenix application has no canonical privacy-reviewed adapter for those optional sources.

## Security acceptance

- Missing write configuration returned HTTP 503 `writes_disabled`; configured authentication tests returned HTTP 401 for a bad token and HTTP 400 for a missing actor.
- Approval-gated workflow execution rejected requests without an approved durable decision.
- Approval timestamps are validated and normalized; illegal decisions return bounded JSON errors rather than exceptions.
- Persistence decoding accepts only known struct fields and does not create atoms from stored input.
- CSP, frame denial, `nosniff`, referrer, permissions and cross-origin headers were present. API responses used `no-store` where designed.
- API responses were scanned for bearer tokens, API keys, access tokens, private knowledge roots and private social message content; no matches were found.
- The configured safe-path boundary and secret-redaction tests passed. No unsafe shell interpolation or public unauthenticated high-risk mutation route was introduced.
- The staging index was empty during the release check. Runtime journals under `var/`, crash/temp files, historical backups, private source data and temporary browser files were not staged.

## i7 strategy display acceptance

`config/learning_focus.yaml` remains the sole content source. It now carries personal reflection reminders centered on selection, observed behavior, autonomy, respect, reciprocity, consistency and substance. The text explicitly rejects pressure, deception and manipulation; it is not an operational progress feed.

- Six existing slides, 12-second automatic rotation, 800 ms fade, continuous ticker, 60-second YAML refresh, keyboard controls and burn-in movement were retained.
- The physical i7 system kiosk remained active. Firefox used `http://127.0.0.1:4013/display/i7?v=1787440870` through the existing loopback SSH forwarding listener owned by `sshd`; no kiosk or tunnel architecture was changed.
- The physical browser received the changed YAML through its live 60-second API refresh. The existing kiosk service was then restarted once to load the updated static slide label and reset rotation; its URL and unit definition were unchanged.
- Physical screenshots taken 15 seconds apart show different active slides and ticker positions:
  - `full-function-screenshots/i7-strategy-physical-1.png` — personal strategy rules.
  - `full-function-screenshots/i7-strategy-physical-2.png` — autonomy and reciprocity criteria.
- The YAML contains configured principles, not fabricated completion, percentage or progress data. Missing/invalid YAML still produces `UNAVAILABLE`.

## Browser evidence

The approved directory `docs/evidence/full-function-screenshots/` contains desktop captures for dashboard, workflows, workflow detail, runs, services, AI, security, approvals, audit, evidence, knowledge, Facebook and the local i7 route; it also contains a responsive dashboard and physical i7 rotation pairs. Visual review found readable tables, working navigation, explicit unavailable states, no blank panels, no missing stylesheet/script/icon, and no critical browser renderer error.

## Repairs made during full-function acceptance

1. Added the umbrella `mix phx.routes` alias so the complete canonical router can be inventoried from the project root.
2. Corrected runtime write-token loading, actor/status boundaries, approval timestamp validation and JSON-safe invalid-transition errors.
3. Restricted durable approval/run decoding to known fields, fixing restart persistence without dynamic atom creation.
4. Added real Docker discovery to the existing service source and corrected the UI source label; no container state is inferred.
5. Added the missing local favicon asset after Chrome exposed repeated asset 404s.
6. Updated only the i7 YAML strategy content and its two descriptive slide labels; the display and physical connection architecture are unchanged.

## Remaining optional gaps

`NODES`, `AGENTS`, `LOGS`, `MESSENGER`, `WHATSAPP`, and `TELEGRAM` remain `NOT_CONNECTED` until genuine canonical, privacy-reviewed sources exist. They are optional and do not block this release.
