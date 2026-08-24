# ShadowOps IHK evidence matrix — 1.0.0rc1 through 1.0.1

## Status vocabulary

`VERIFIED` means a command, test, HTTP response, or physical-system observation was recorded locally on 2026-08-22 or 2026-08-23. `PROTOTYPE` means a Phoenix-native contract exists but is not backed by a persistent production source. `MODELLED` is a documented design. `PLANNED` is intentionally not implemented. `OPEN` requires a real source or external integration.

| Area | Status | Evidence / boundary |
| --- | --- | --- |
| Phoenix compile, format, tests | VERIFIED | The final 1.0.1 gate passed format, compile with warnings as errors, diff-check, Hex audit and 69 tests; the earlier 42-test acceptance remains historical evidence in `full_function_acceptance.md`. |
| Workflow registry | VERIFIED | Validated schema-v2 YAML is served by the existing `WorkflowEngine.Registry`. |
| Facebook | VERIFIED | The privacy-safe aggregate-only adapter is rendered at `/social/facebook` and `/social/review`; unsupported behavioral dimensions remain `UNAVAILABLE`, follow-up remains `PARTIAL`, and no identities, messages or credentials cross the UI boundary. |
| Readiness and health | VERIFIED | Loopback `/health` and `/ready` returned HTTP 200 after required registry, learning configuration and audit-chain checks succeeded. Optional sources do not gate readiness. |
| Write controls | VERIFIED | Mutating API routes require configured write token and `X-ShadowOps-Actor`; with no token they returned `503 {"error":"writes_disabled"}`. |
| Security headers | VERIFIED | Loopback `/health` response exposed CSP, `nosniff`, frame denial, referrer, permissions and cross-origin headers. |
| i7 learning display | VERIFIED | `/display/i7` returned 200 from the real local `config/learning_focus.yaml`; its personal strategy reminders preserve autonomy and reciprocity and reject pressure/deception/manipulation. Missing/unreadable configuration renders `UNAVAILABLE`. |
| i7 kiosk unit | VERIFIED | The existing system kiosk and loopback SSH forwarding path were verified on `shadowserver-i7`; Firefox used the current port-4013 URL. |
| i7 physical deployment | VERIFIED | Two real X11 screenshots taken 15 seconds apart showed different active strategy slides and ticker positions from the Ryzen Phoenix instance. |
| Audit integrity | VERIFIED | `var/audit.jsonl` is append-only from application APIs and every row includes timestamp, actor, action, resource, result, evidence reference, previous hash and current hash. `/api/audit/verify` returned `valid:true`; a pre-canonical development journal was retained as an `.invalid` forensic copy. |
| Runtime metadata | VERIFIED | Services are read from `systemctl --user`, system `systemctl` and `docker ps --all`; Ollama is read from `ollama list`; knowledge and evidence expose metadata only. Unreachable sources return `UNAVAILABLE`, never synthetic operational records. |
| Runs | VERIFIED | Append-only persisted lifecycle records validate registry IDs and legal transitions; requests, transitions, audit references and optional evidence references survive reload. |
| Approvals | VERIFIED | Append-only persisted requests and decisions enforce actor identity, legal transitions, expiry and audit linkage. |
| Mission Control UI | VERIFIED | Phoenix-native dashboard, workflow/detail, runs, services, AI, security, approvals, audit, evidence and knowledge screens render real sources or explicit unavailable states. |
| Knowledge and evidence stores | VERIFIED | Allowlisted source and artifact metadata is exposed without private note bodies or absolute filesystem paths. |
| Messenger, WhatsApp, Telegram | OPEN | No independent real local source contract was found; these must remain `NOT_CONNECTED`. |
| Economic model / acceptance evidence | OPEN | No hours, rates, approval or acceptance values were inferred or invented. |

## Architecture and risk decision

The canonical Phoenix umbrella remains the only deployed architecture. PR #14 was inspected solely as a reference. Its Python sandbox, SQLite schema, FastAPI runtime and public-facing service definitions were not merged or deployed. The Phoenix endpoint binds to loopback by default; i7 access is designed for existing private SSH/WireGuard/local-network paths and no public control-plane listener is introduced.

The release architecture is frozen at the accepted Phoenix contexts, router contracts and existing private i7 connection. Future features or connector work require a separate reviewed change set; the strategy content update did not change those boundaries.

The two Bandit findings `EEF-CVE-2026-75484` and `EEF-CVE-2026-74836` were fixed by updating Bandit from 1.12.4 to 1.12.5; `mix hex.audit` then reported no advisory or retired package. Nodes, agents, logs, Messenger, WhatsApp and Telegram remain explicitly `NOT_CONNECTED` because no genuine current source exists; they are optional and do not imply healthy state.

## IHK final focus update for ShadowOps 1.0.1

This update adds verified technical learning from PRs [#15](https://github.com/DonMassa84/ihk-document-ai/pull/15), [#16](https://github.com/DonMassa84/ihk-document-ai/pull/16), [#18](https://github.com/DonMassa84/ihk-document-ai/pull/18) and [#19](https://github.com/DonMassa84/ihk-document-ai/pull/19). It does not change the existing project boundary, schedule, hours or external acceptance status.

### 1. Project goal and business benefit

The technical project goal is a reproducible Zero-Trust and governance workflow in the canonical Phoenix application. Fail-closed controls, durable approvals/runs/audit records and evidence-driven release gates reduce avoidable manual rechecks and accidental release errors. The verified benefit is qualitative: the same baseline, CI, deployment and acceptance checks can be repeated and traced. Monetary savings, staffing effects and signed business acceptance remain `OPEN` because no supporting source exists.

### 2. AS-IS / TO-BE analysis

| Perspective | Evidence-based state |
| --- | --- |
| AS-IS | External-tool availability was assumed in one service path; unavailable states and privacy boundaries were not equally defensive; the managed signing-secret injection was incomplete; physical and HTTP verification required manual reconstruction. |
| TO-BE | Missing real sources return explicit `UNAVAILABLE`/`NOT_CONNECTED`; external-tool guards fail closed; the managed secret is injected from a protected local mode-0600 EnvironmentFile; CI, controlled deployment, five HTTP smokes and physical i7 verification form one acceptance chain. |

### 3. Technical decision and alternatives

Controlled incremental hardening was selected instead of replacing the Phoenix architecture. It retained the already verified contexts, routes, durable stores, security boundaries and private i7 tunnel while correcting only reproduced defects. Architecture replacement would have duplicated production responsibilities and invalidated existing acceptance evidence without a demonstrated need.

The decision rules were:

- `REPRODUCE BEFORE FIX`: severity follows observed behavior, not an unverified label.
- `NO FAKE DATA`: a missing source remains `UNAVAILABLE` or `NOT_CONNECTED`.
- `FAIL CLOSED`: uncertainty never becomes implicit authorization or synthetic success.
- `FINISH BEFORE EXPAND`: a green release state is frozen before new scope starts.

In IHK alternatives/evaluation terms, the chosen option had the lowest migration risk and highest reuse of verified evidence while satisfying the security and operational criteria.

### 4. Risk, security and privacy

- Final independent hardening confirmed `P0=0` and `P1=0`.
- PR #19 added the `systemctl`-absence fallback, narrower value-bearing PrivacyGate matching and no-shell/external-tool regression coverage.
- The managed `SHADOWOPS_SECRET_KEY_BASE` is supplied through a protected local EnvironmentFile with mode `0600`; its value is neither printed nor stored in Git.
- Workflow arguments containing shell metacharacters remained literal argv; request-body runtime selection was not reproduced.
- Facebook Social Review is aggregate-only. Raw private data exposure is blocked, unsupported metrics remain `UNAVAILABLE`, and follow-up remains `PARTIAL`.
- Optional sources without a canonical real adapter remain `NOT_CONNECTED` and do not become fabricated healthy states.

### 5. Testing and quality assurance

| Release gate | Verified result |
| --- | --- |
| PR #15 Mission Control | 43 tests; No Fake Data, Security Gate, HTTP Sweep, Browser Verify, physical i7 and IHK evidence PASS. |
| PR #16 adaptive i7 | 53 tests; canonical 72-slide dataset plus six preserved system slides; physical rotation PASS. |
| PR #18 Facebook Social Review | 64 tests; privacy/no-fake negative paths and five-route isolated HTTP verification PASS. |
| PR #19 hardening | 69 tests; format PASS; compile warnings-as-errors PASS; diff-check PASS; `mix hex.audit` PASS. |
| GitHub CI | `quality`/`portable-quality-gate` and `ShadowOps Elixir`/`registry-and-tests` passed before every merge. |

The five canonical production smokes returned HTTP 200 for `/health`, `/ready`, `/social/facebook`, `/social/review` and `/display/i7`.

### 6. Deployment, acceptance and operation

The application runs as the managed user service `shadowops-phoenix.service` on loopback `127.0.0.1:4013`. The controlled sequence was merge, fast-forward main sync, managed restart, HTTP smoke and physical i7 regression verification. The existing kiosk/tunnel design was preserved. The display provides 72 strategy slides plus six independent system slides, for 78 configured screens in total.

### 7. Economic and organizational value

Verified qualitative value consists of reduced rework, reproducible verification, lower release risk and traceable technical acceptance. No hourly rate, monetary saving, ROI, staffing number, approval signature or external acceptance result is supported by repository evidence. Those values remain `OPEN/TBD` and must be supplied by the responsible business/IHK stakeholders if required.

### 8. Lessons learned and project management

- Independent reproduction filtered false positives before implementation work began.
- Separate Codex implementation and OpenCode read-only review reduced conflicting simultaneous changes, as recorded in the Issue #17 coordination log.
- Green states were frozen before the next bounded change.
- The reusable evidence chain is: baseline → reproduction → decision → implementation → tests → CI → deployment → acceptance → physical verification.
- Documentation distinguishes verified technical acceptance from missing external or commercial evidence.

### 9. Evidence and appendix references

- PR #15: Mission Control release and Facebook portability correction.
- PR #16: adaptive i7 strategy-slide engine and physical verification.
- PR #18: privacy-safe aggregate Facebook Social Review.
- PR #19: independently reproduced runtime portability and privacy hardening.
- [Issue #17](https://github.com/DonMassa84/ihk-document-ai/issues/17): shared Mission-Control coordination and final gate status.
- `shadowops/docs/evidence/full_function_acceptance.md`: historical 42-test Mission Control acceptance.
- `shadowops/docs/evidence/i7_strategy_72_acceptance.md`: strategy dataset and physical display acceptance.
- `shadowops/docs/evidence/shadowops_1.0.1_independent_validation.md`: finding reproduction and classification.
- `shadowops/docs/evidence/shadowops_1_0_1_release.md`: final 69-test, CI, deployment, privacy and physical acceptance evidence.

No secret value, raw Facebook content, private message, credential, sensitive source content or runtime journal is included in this update.

## IHK change matrix

| IHK_SECTION | WHAT_CHANGED | EVIDENCE | STATUS |
| --- | --- | --- | --- |
| Project goal / benefit | Added reproducible governance, fail-closed and rework-reduction outcome. | PRs #15/#19; `shadowops_1_0_1_release.md` | VERIFIED technical; financial value OPEN |
| AS-IS / TO-BE | Added measured portability/privacy/manual-verification risks and final guarded state. | PRs #18/#19; independent validation | VERIFIED |
| Technical decision | Recorded incremental hardening and four decision rules instead of architecture replacement. | PRs #15/#16/#18/#19 | VERIFIED |
| Risk / security / privacy | Added P0=0/P1=0, protected secret injection, aggregate-only Facebook and explicit unavailable contracts. | PRs #18/#19; release evidence | VERIFIED |
| Testing / QA | Added 43/53/64/69-test progression, required CI and five HTTP smokes. | PRs #15/#16/#18/#19; GitHub CI | VERIFIED |
| Deployment / acceptance | Added managed service, loopback listener, controlled deployment and physical i7 chain. | PRs #16/#19; release evidence | VERIFIED |
| Economic / organization | Added defensible qualitative value only. | Release evidence | VERIFIED qualitative; quantitative values OPEN/TBD |
| Lessons learned | Added reproduction-first review, separated roles and frozen green states. | Independent validation; PR sequence | VERIFIED |
| Evidence / appendix | Linked PRs and canonical 1.0.1 evidence without private data. | Repository evidence paths above | VERIFIED |
