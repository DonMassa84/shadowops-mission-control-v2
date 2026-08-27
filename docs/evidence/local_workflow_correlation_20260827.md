# Local Workflow Correlation Evidence — 2026-08-27

## Scope

Read-only local source correlation run against the operator home directory. The scan did not execute discovered workflows, did not mutate source files, and did not expose secret values.

Source run:

```text
DISCOVERY_SOURCE=/home/schattenmacher/reports/shadowops/workflow_discovery_20260827_035710
CORRELATION_OUTPUT=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244
```

## Correlation result

| Source | Entrypoints | Configs | Runtime refs | Test refs | Governance refs | Git repos | Score | Classification |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Projects | 706 | 77 | 334 | 293 | 315 | 5 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| DokumentenSystem | 1026 | 64 | 1000 | 1000 | 861 | 5 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| ProofFlow-Obsidian-Vault | 29 | 1 | 142 | 0 | 13 | 0 | 75 | STRONG_CANDIDATE |
| actions-runner-host | 79 | 21 | 208 | 17 | 29 | 1 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| auto_bewerbungen | 185 | 12 | 78 | 7 | 3 | 23 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| whatsapp-agent | 1000 | 1 | 126 | 15 | 46 | 0 | 90 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| matrix_shadowops | 1034 | 15 | 55 | 1000 | 7 | 23 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| shadowops-local-hold | 116 | 20 | 50 | 26 | 68 | 0 | 90 | HIGH_VALUE_INTEGRATION_CANDIDATE |
| openclaw-workspace | 1000 | 4 | 492 | 1000 | 210 | 2 | 100 | HIGH_VALUE_INTEGRATION_CANDIDATE |

Aggregate result:

```text
HIGH_VALUE_CANDIDATES=8
STRONG_CANDIDATES=1
WORKFLOW_CANDIDATES=0
FINAL_STATUS=HIGH_VALUE_WORKFLOW_CORRELATION_PASS
```

## Existing runtime evidence

The local host exposed the following relevant listeners during the read-only scan:

```text
127.0.0.1:4013  ShadowOps Phoenix production runtime
127.0.0.1:4014  ShadowOps preview/development runtime
127.0.0.1:4096  OpenCode server
127.0.0.1:5678  local service
127.0.0.1:8765  Python service
127.0.0.1:8766  Python service
127.0.0.1:8787  Python service
127.0.0.1:8790  Python service
127.0.0.1:11434 Ollama
127.0.0.1:11436 socat bridge
10.20.0.1:11444 socat bridge
```

The scan also found a large set of existing user-level systemd services and timers related to ShadowOps, OpenCode, i7, DokumentenSystem, OpenClaw, WhatsApp, career automation, backup, audit, security, workflow registry, and related operator tooling.

Examples include:

```text
shadowops-phoenix.service
shadowops-preview.service
shadowops-i7-tunnel.service
shadowmaker-opencode-server.service
i7-control-app.service
whatsapp-agent.service
shadowmaker-workflow-registry.service
shadowmaker-workflow-auto-register.service
shadowmaker-career-it-all-drives-analyze.service
openclaw-obsidian-workflow-bridge.service
openclaw-rag-rebuild.service
```

Presence of a unit or listener is evidence of discovery only. It does not by itself prove source truth, real data, governance mapping, or permission to execute it.

## Safety evidence

```text
SECRET_VALUES_READ=0
SECRET_VALUES_EXPOSED=0
SOURCE_MUTATIONS=0
EXECUTION_ATTEMPTS=0
```

No discovered executable or systemd unit was promoted automatically.

## ShadowOps mapping rule

The next integration stage must preserve the canonical fail-closed chain:

```text
DISCOVERED
-> ENTRYPOINT_FOUND
-> CONFIG_FOUND
-> RUNTIME_REFERENCE_FOUND
-> SOURCE_VERIFIED
-> GOVERNANCE_MAPPED
-> CapabilityRegistry
-> Policy / Risk
-> Approval where required
-> PrivacyGate
-> ExecutionService
-> Adapter
-> Audit / Events
```

A local path, file, service, timer, repository, or listening port must never be upgraded directly to `READY` or executable solely because it exists.

## Recommended first mappings

1. OpenCode — governed remote-only coding runtime; no local coding fallback.
2. ProofFlow-Obsidian-Vault — measured local knowledge source; vector/RAG readiness remains separate.
3. i7 — compute/node source; mutations only through a proven node adapter.
4. WhatsApp — connector candidate; real-data and reachability evidence required.
5. Career / auto_bewerbungen — source/evidence integration before mutation workflows.
6. DokumentenSystem — import only individually proven workflow IDs, never arbitrary scripts.
7. Existing systemd units — read-only inventory first; start/stop/restart only after explicit allowlist and governance mapping.

## Local raw evidence paths

```text
MATRIX=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/source_matrix.tsv
ENTRYPOINTS=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/entrypoints.tsv
CONFIGS=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/configs.tsv
RUNTIME_REFS=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/runtime_refs.tsv
TEST_REFS=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/test_refs.tsv
GOVERNANCE_REFS=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/governance_refs.tsv
SUMMARY=/home/schattenmacher/reports/shadowops/workflow_correlation_20260827_043244/SUMMARY.env
```

These are local evidence paths and are not assumed to be portable or available in CI.
