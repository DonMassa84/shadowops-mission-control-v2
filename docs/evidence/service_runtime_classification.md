# Service Runtime Classification Evidence

## Git Info

- **HEAD**: `auto/opencode-work`
- **Branch**: `auto/opencode-work`
- **Base**: `origin/fix/functional-core-20260826`

## Test Results

- **Total Tests**: 268 passed
- **Format**: PASS
- **Compile**: PASS
- **Registry**: PASS
- **Diff Check**: PASS

## Runtime Source

- **Adapter**: `SystemctlServiceRuntime`
- **Protocol**: systemctl CLI
- **Scopes**: user, system

## Correlation Policy

Evidence order:
1. candidate source_ref
2. exact service name
3. scope:name identity
4. LoadState
5. FragmentPath/SourcePath
6. SHA-256 definitions comparison
7. runtime_verified

## Fail-Closed Rules

- **Runtime Conflict**: `runtime_conflict=true` → `runtime_verified=false`, `connected=false`, `real_data=false`, READY forbidden
- **User/System Ambiguity**: `runtime_ambiguous=true` → fail closed
- **Synthetic Data**: Never promotes to READY
- **Fuzzy Name Match**: Never runtime verified
- **Non-Service Script**: systemd must not promote it

## Health State Model

| State | Meaning |
|-------|---------|
| DISCOVERED | Definition/file found |
| RUNTIME_VERIFIED | Exact runtime identity proven |
| LIVE | Process running |
| CONNECTED | Expected service/transport path responding |
| REAL_DATA | Real non-synthetic data received |
| READY | runtime_verified AND live AND connected AND real_data AND governance_mapped AND synthetic==false |

## Key Semantic Rules

- `systemd ActiveState=active` DOES NOT automatically yield `REAL_DATA` or `READY`
- `DISCOVERED` proves a real local file exists; execution remains disabled until runtime and governance mapping are proven
- No green READY badges without complete evidence

## Files Created

1. `apps/shadowops_core/lib/shadow_ops_core/adapters/service_runtime_adapter.ex` - Behaviour
2. `apps/shadowops_core/lib/shadow_ops_core/adapters/systemctl_service_runtime.ex` - Adapter
3. `apps/shadowops_core/lib/shadow_ops_core/integration_probe.ex` - Probe behaviour
4. `apps/shadowops_core/lib/shadow_ops_core/service_runtime_correlation.ex` - Correlation
5. `apps/shadowops_core/test/service_runtime_adapter_test.exs` - Tests
6. `docs/evidence/service_runtime_classification.md` - This file

## Runtime Mutations

- **0** systemd mutations
- **0** service start/stop/restart
- **0** model downloads
- **0** pushes
