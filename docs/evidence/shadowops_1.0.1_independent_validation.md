# ShadowOps 1.0.1 independent hardening validation

- Date: 2026-08-23
- Branch: `shadowops-hardening-1.0.1`
- Base: `be2ef06bc2958effa733e1793c3111e87e69f9aa`
- Isolation: application changes stayed in a separate Git worktree; only the confirmed local secret configuration was applied to the managed service, without changing port 4013, tunnel, or physical kiosk architecture
- Baseline: format PASS, compile PASS, 64 tests PASS, diff check PASS
- Rule applied: no reproduction means no P0/P1

## Severity summary

```text
P0_CONFIRMED=NONE
P1_CONFIRMED=NONE
P2_CONFIRMED=DETERMINISTIC_RUNTIME_SECRET,SYSTEMCTL_ABSENT_CRASH,I7_SCHEMA_FAIL_OPEN_OR_500,LEARNING_CONFIG_SYMLINK_ESCAPE
P3_CONFIRMED=PRIVACY_GATE_OVERBLOCKING,REGISTRY_RUNTIME_TRUST_BOUNDARY
FALSE_POSITIVES=SHELL_INJECTION,UNTRUSTED_API_RUNTIME_SELECTION,LEXICAL_PATH_TRAVERSAL,ABSOLUTE_OUTSIDE_PATH,PREFIX_COLLISION,FACEBOOK_NEGATIVE_PATH_500,OLLAMA_ABSENCE_CRASH,DOCKER_ABSENCE_CRASH
```

No P0/P1 impact was demonstrated. The executable-selection finding requires trusted local registry mutation; the HTTP request body cannot override the runtime, and workflow writes remain actor-, token-, and approval-gated.

## Confirmed issue: managed runtime used the deterministic secret fallback

```text
REPRO_COMMAND=inspect the managed service environment and process environment for SHADOWOPS_SECRET_KEY_BASE without printing its value
OBSERVED=the variable was absent and config/config.exs therefore selected String.duplicate("0", 64)
EXPECTED=the deployed service receives an unpredictable secret through protected runtime configuration
ROOT_CAUSE=the managed systemd user unit had no EnvironmentFile for SHADOWOPS_SECRET_KEY_BASE
MINIMAL_FIX=generate a local 128-hex-character secret in ~/.config/shadowops/shadowops-phoenix.env (mode 0600) and load it through a systemd drop-in
REGRESSION_TEST=systemd unit verification, process-environment presence check, mode check, health/readiness HTTP checks; the value is never printed or committed
SEVERITY=P2 because the endpoint is loopback-only and reached by the existing secure tunnel, but a deterministic signing secret is still not acceptable production configuration
```

## Confirmed issue: systemctl absence crashed service discovery

```text
REPRO_COMMAND=MIX_ENV=test mix run -e 'System.put_env("PATH", "/tmp/shadowops-systemctl-absent"); IO.inspect(ShadowOpsCore.RuntimeSources.services())'
OBSERVED=ErlangError :enoent from System.cmd("systemctl", ...); RuntimeSources.services/0 did not return a contract
EXPECTED=clean availability UNAVAILABLE with no invented service rows
ROOT_CAUSE=service_scope/1 did not rescue command-resolution errors, unlike the Docker and Ollama adapters
MINIMAL_FIX=return an empty scope result on command failure so aggregate availability remains source-backed and fail-closed
REGRESSION_TEST=apps/shadowops_core/test/runtime_sources_test.exs -- reports unavailable instead of crashing when runtime commands cannot be resolved
SEVERITY=P2
```

## Confirmed issue: privacy gate overblocked benign text

Synthetic corpus before the fix:

| Case | Result |
|---|---|
| `api_key=synthetic-placeholder` | CORRECT_BLOCK |
| `access_token=synthetic-placeholder` | CORRECT_BLOCK |
| `password=synthetic-placeholder` | CORRECT_BLOCK |
| synthetic PEM private-key material | CORRECT_BLOCK |
| `the password was reset` | FALSE_POSITIVE |
| `authentication token accepted` | CORRECT_ALLOW |
| documentation about JWT | FALSE_POSITIVE |
| synthetic public SSH key | FALSE_POSITIVE |
| `secret management policy` | CORRECT_ALLOW |

```text
REPRO_COMMAND=MIX_ENV=test mix run -e 'Enum.each(corpus, &IO.inspect(ShadowOpsCore.PrivacyGate.check(&1)))'
OBSERVED=3 false positives; no false negatives in the required corpus
EXPECTED=block value-bearing credentials/private-key material while allowing documentation and public-key material
ROOT_CAUSE=keyword-only regexes treated any mention of password/JWT/SSH public-key algorithms as secret material
MINIMAL_FIX=match credential assignments, bearer values, authorization headers, and PEM private-key boundaries; normalize structured secret keys case-insensitively
REGRESSION_TEST=apps/shadowops_core/test/privacy_gate_test.exs
SEVERITY=P3
```

## Confirmed issue: malformed i7 plan schema failed open or raised

Before the fix:

| Input | Core contract | `/display/i7` |
|---|---|---|
| `goal: "string"` | AVAILABLE | 500 (`Access.get/3`) |
| `current: null` | AVAILABLE | 200 with invalid available plan |
| `next: {}` | AVAILABLE | 200 with invalid available plan |
| `writing_framework: "text"` | AVAILABLE | 200 with invalid available plan |
| `kpis: null` | AVAILABLE | 200 with invalid available plan |
| `execution: []` | AVAILABLE | 500 (`Access` list error) |

```text
REPRO_COMMAND=configure each malformed YAML under config, call LearningFocus.load/1, then GET /display/i7 through ShadowOpsWeb.Endpoint
OBSERVED=2 LiveView 500s and 4 malformed plans incorrectly labelled AVAILABLE
EXPECTED=HTTP 200 with explicit UNAVAILABLE for every malformed shape
ROOT_CAUSE=LearningFocus validated only the YAML top-level map, not the nested display contract
MINIMAL_FIX=validate required maps, lists, scalar fields, KPI entries, and focus values before assigning AVAILABLE
REGRESSION_TEST=apps/shadowops_web/test/i7_display_test.exs -- malformed learning plan shapes render explicit unavailable state without a 500
SEVERITY=P2; fixed and released with the i7 slide engine before this hardening branch was rebased
```

## Confirmed issue: symlink escaped learning-plan allowlist

```text
REPRO_COMMAND=create config/.hardening-link.yaml -> /tmp/outside.yaml and call LearningFocus.load(link)
OBSERVED=the outside YAML was read and returned with availability AVAILABLE
EXPECTED=UNAVAILABLE with path outside allowlist
ROOT_CAUSE=Path.expand plus string-prefix comparison provided lexical confinement but did not resolve symlinks
MINIMAL_FIX=retain the prefix boundary and add OTP filelib.safe_relative_path/2 symlink-aware confinement
REGRESSION_TEST=apps/shadowops_web/test/i7_display_test.exs -- learning plan confinement blocks traversal, prefix collisions and symlink escapes
SEVERITY=P2; fixed and released with the i7 slide engine before this hardening branch was rebased
```

Lexical `../` traversal, absolute outside paths, and prefix collisions were already rejected before the fix.

## Confirmed behavior: registry runtime trust risk

```text
REPRO_COMMAND=replace repository_quality runtime with /usr/bin/printf in an in-memory registry, call Registry.validate/1, then call WorkflowExecutor.execute/2
OBSERVED=Registry.validate/1 returned :ok and the direct executor ran the absolute regular file
EXPECTED=under the current architecture runtime selection is trusted registry configuration, never request-body input
ROOT_CAUSE=registry schema validates runtime type but intentionally has no executable allowlist; WorkflowExecutor confines only to an absolute regular file
MINIMAL_FIX=no runtime allowlist change proposed without a defined executable policy; retain local registry as a trusted configuration boundary
REGRESSION_TEST=apps/shadowops_core/test/workflow_executor_test.exs verifies request runtime fields are ignored and shell metacharacters remain literal argv
```

Classification:

```text
SHELL_INJECTION=NOT_REPRODUCED
ARBITRARY_EXECUTABLE_SELECTION=REPRODUCED_ONLY_FROM_TRUSTED_WORKFLOW_MAP
REGISTRY_TRUST_RISK=CONFIRMED_LOCAL_CONFIGURATION_BOUNDARY
UNTRUSTED_API_RUNTIME_CONTROL=NOT_REPRODUCED
SEVERITY=P3_ACCEPTED_TRUST_BOUNDARY
```

Arguments containing `;`, `&&`, `||`, `$()`, backticks, pipes, redirections, spaces, and quotes were returned literally by `/usr/bin/printf`; the `$()` marker file was not created.

## Facebook negative paths

| Source | Core result | UI result |
|---|---|---|
| empty file | `invalid_json` | HTTP 200, unavailable/error |
| invalid JSON | `invalid_json` | HTTP 200, unavailable/error |
| UTF-8 BOM JSON | `invalid_json` | HTTP 200, unavailable/error |
| JSON array | `invalid_schema` | HTTP 200, unavailable/error |
| missing evidence | `invalid_schema` | HTTP 200, unavailable/error |
| directory source | `source_unreadable: eisdir` | HTTP 200, unavailable/error |
| unreadable source | `source_unreadable: eacces` | HTTP 200, unavailable/error |

Every UI response remained privacy-protected and contained no fake zero metrics. There is no Facebook API route. The more complete regression corpus was released separately in Facebook PR #18 and retained during this branch's rebase.

## External tool absence

With `PATH` set to an intentionally missing directory, the services adapter returned `UNAVAILABLE` with zero records and the Ollama adapter returned `UNAVAILABLE` with zero models. Docker absence was handled by its existing rescue path. No crash was reproduced for Ollama or Docker, so no production rewrite was made.

## Validation gate

```text
FORMAT=PASS
COMPILE_WARNINGS_AS_ERRORS=PASS
TESTS=PASS_69
DIFF_CHECK=PASS
PRODUCTION_APPLICATION_MAIN_MODIFIED=NO
PRODUCTION_RUNTIME_SECRET_CONFIGURED=YES
PUSHED=NO
```
