# ShadowOps 1.0.1 release evidence

- Completed: 2026-08-23, Europe/Berlin
- Starting main: `663edcefaac14f1deed3beaed5e7cb2338cc45ca`
- Deployed application main: `0666df7b437d3df590f77c54ab9a00f22d0e9a5a`
- Final status: `SHADOWOPS_1_0_1_COMPLETE`

## Release sequence

| Concern | PR | Feature head | Squash merge | Tests | Required CI |
|---|---:|---|---|---:|---|
| Adaptive i7 strategy slide engine | #16 | `2a74cf6a0f1e52f91db134022a360403c28fd34a` | `8b00be628b5d3fb01fe28b5e11fa11ac7d0b1474` | 53 | portable-quality-gate PASS; registry-and-tests PASS |
| Privacy-safe Facebook Social Review | #18 | `9738db987996020d141ddb4defb4dbc3f3bb6403` | `be2ef06bc2958effa733e1793c3111e87e69f9aa` | 64 | portable-quality-gate PASS; registry-and-tests PASS |
| Runtime portability and security boundaries | #19 | `8e4d1c1afaf186169fbf84d90b9e88ece209534b` | `0666df7b437d3df590f77c54ab9a00f22d0e9a5a` | 69 | portable-quality-gate PASS; registry-and-tests PASS |

All three feature branches were pushed normally and squash-merged only after both required workflows passed. No force push was used.

## Final immutable gate

Executed on deployed application main `0666df7b437d3df590f77c54ab9a00f22d0e9a5a`:

```text
FORMAT=PASS
COMPILE_WARNINGS_AS_ERRORS=PASS
TESTS=PASS_69
DIFF_CHECK=PASS
HEX_AUDIT=PASS_NO_RETIRED_OR_SECURITY_ADVISORY_PACKAGES
```

The final managed runtime was restarted through `shadowops-phoenix.service` and remained bound only to `127.0.0.1:4013`.

## Five-route production smoke

```text
/health=200
/ready=200
/display/i7=200
/social/facebook=200
/social/review=200
```

Health and readiness remained green after the final controlled restart.

## i7 acceptance

- Canonical strategy dataset: 72 slides.
- Existing system pool: 6 slides.
- Total available display content: 78 screens.
- Weighted selection, configured-context weighting, night weighting, cooldown, no-consecutive-repeat, ticker, transitions, live refresh and six-slide fallback are covered by tests.
- The existing reverse tunnel and kiosk architecture were not changed.
- The physical kiosk remained active on `http://127.0.0.1:4013/display/i7`.
- Fresh frames captured 15 seconds apart after the final deployment had different hashes, confirming continued physical rotation.

## Facebook privacy and data quality

- `/social/facebook` and `/social/review` render privacy-safe aggregate metadata only.
- Missing, empty, truncated, malformed, array-root, directory and unreadable sources return safe unavailable contracts without fake metrics or HTTP 500.
- Recursive privacy tests block raw messages, identity fields, names, email addresses, phone numbers, profiles, cookies, sessions, tokens, passwords and credentials.
- Source-backed status remains `PARTIAL`; privacy remains `PROTECTED`.
- Follow-up remains `PARTIAL` from current evidence. Reciprocity, initiation, response, latency, consistency, balance and trend remain `UNAVAILABLE`.
- No unsupported metric was converted to zero, an estimate or a synthetic percentage.

## Independent hardening result

```text
P0_CONFIRMED=NONE
P1_CONFIRMED=NONE
P2_CONFIRMED=DETERMINISTIC_RUNTIME_SECRET,SYSTEMCTL_ABSENT_CRASH,I7_SCHEMA_FAIL_OPEN_OR_500,LEARNING_CONFIG_SYMLINK_ESCAPE
P3_CONFIRMED=PRIVACY_GATE_OVERBLOCKING,REGISTRY_RUNTIME_TRUST_BOUNDARY
```

- The managed service now obtains `SHADOWOPS_SECRET_KEY_BASE` from a protected local EnvironmentFile with mode `0600`. The value is not present in Git or this report.
- Missing `systemctl`, Docker and Ollama commands now produce or retain explicit `UNAVAILABLE` contracts; no synthetic rows or model counts are created.
- Workflow arguments containing shell metacharacters remain literal argv under `System.cmd/3`; shell injection and request-body runtime selection were not reproduced.
- The runtime executable remains a trusted, local, read-only workflow-registry boundary. Workflow writes remain actor-, authorization- and approval-gated.
- Benign password-reset/JWT documentation and public SSH keys are allowed, while value-bearing credentials and private-key material are blocked.
- Malformed learning configuration returns explicit `UNAVAILABLE` or the verified system fallback without a LiveView 500.
- Lexical traversal, absolute external paths, prefix collisions and symlink escapes are confined.

Full reproduction details are recorded in `docs/evidence/shadowops_1.0.1_independent_validation.md`.

## Remaining optional gaps

Nodes, agents, logs, Messenger, WhatsApp and Telegram remain explicitly `NOT_CONNECTED` because no current canonical real source was established. They are optional integrations and were not replaced with demo adapters or synthetic operational data.

## Data handling

This evidence contains no secret values, credentials, private Facebook content, raw messages, runtime databases, browser profiles, caches or temporary screenshots. Physical frames used for verification remained temporary and were not staged.
