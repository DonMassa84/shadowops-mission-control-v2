# Hermetic test environment decision — 2026-08-27

## Problem

The same ShadowOps source revision produced different test results depending on the orchestration path:

- direct hermetic execution: 117/117 passed
- local preview/production-acceptance orchestration: 93/117 passed

The difference was not evidence of 24 independent product defects. The test process was inheriting runtime/preview configuration from the parent shell.

## Root cause

The local preview setup loads runtime configuration before quality gates run. A blacklist-based cleanup (`env -u ...`) cannot guarantee isolation because new or previously unknown variables can remain inherited.

A second leak path remained in `scripts/production_acceptance.sh`, which invoked `mix test --seed 12345` directly and therefore inherited the caller environment.

## Decision

All certification test executions must cross a hermetic boundary. Use a positive allowlist with `env -i` and pass only the minimal variables required by Mix/ExUnit.

Canonical model:

```text
runtime/preview environment
        |
        X  no inheritance into tests
        |
hermetic test environment
        |
        +-- HOME
        +-- USER / LOGNAME
        +-- PATH
        +-- LANG
        +-- MIX_ENV=test
        +-- SHADOWOPS_START_PERSISTENCE=false
```

This is a durable certification invariant, not a one-off workaround.

## Evidence

On commit `8685bad59a35606d4c0106286498f4c0130952f8`, the direct hermetic test run reported:

```text
Result: 117 passed
DIRECT_HERMETIC_TEST=PASS
4013_MUTATED=NO
```

The subsequent local-all run failed specifically at `QUALITY_GATE_PRODUCTION_ACCEPTANCE`, where `production_acceptance.sh` still executed its own non-hermetic test command and reproduced 93/117.

## Resolution

The nested test invocation in `scripts/production_acceptance.sh` was moved behind the same hermetic `env -i` boundary.

The fix was committed as:

```text
097d73225cd96399f2e8de8c04987a50c605b210
fix: isolate production acceptance test environment
```

Closure evidence from the local run:

```text
Result: 117 passed
PASS tests
PASS registry
PASS prod_compile
PASS dependency_audit
PASS phoenix_security_scan
PASS no_fake_state
PASS secret_scan
PASS runtime_health
PASS layer_truthfulness
PASS project_catalog_truthfulness
PASS connector_truthfulness
PASS audit_chain
PASS_COUNT=43
FAIL_COUNT=0
FINAL_STATUS=PRODUCTION_ACCEPTANCE_PASS
PRODUCTION_ACCEPTANCE_HERMETIC=PASS
4013_MUTATED=NO
SOURCE_PARITY=PASS
```

This confirms that the repeated 93/117 result was caused by orchestration environment contamination, not by 24 independent application regressions.

## Additional harness lessons

Quality-gate commands must report a named failure reason instead of relying on an unlabelled `set -e` exit. Expected negative probes, such as finding no listener on an unused port, must be normalized as data rather than treated as fatal shell failures.

## Regression rules

1. Never weaken application tests to compensate for orchestration contamination.
2. Compare exact Git HEAD and worktree state before diagnosing divergent results.
3. Every nested script that starts ExUnit must use the same hermetic boundary.
4. Runtime configuration and test configuration are separate trust domains.
5. A passing test suite does not authorize promotion of the stable runtime.
6. Stable port 4013 remains unchanged until an explicit promotion decision.
7. A certification harness must treat absence of an optional/stale runtime process as a normal state, not as a shell failure.
8. Nested acceptance scripts must not silently re-enter a less isolated execution environment than their caller.
