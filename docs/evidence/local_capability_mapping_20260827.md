# Local Capability Mapping — 2026-08-27

## Correlation result

```text
HIGH_VALUE_CANDIDATES=8
STRONG_CANDIDATES=1
WORKFLOW_CANDIDATES=0
CAPABILITY_CANDIDATES_MAPPED=9
```

## Mapping

| Source | Classification | Surface | Capability | Mode | Executable | Target status |
|---|---|---|---|---|---|---|
| Projects | HIGH_VALUE_INTEGRATION_CANDIDATE | Project Catalog | `NONE` | PROJECT_DISCOVERY | NO | DISCOVERED |
| DokumentenSystem | HIGH_VALUE_INTEGRATION_CANDIDATE | Workflows / Evidence | `workflow.execute` | REFERENCE_ONLY | NO | GOVERNANCE_MAPPING_REQUIRED |
| ProofFlow-Obsidian-Vault | STRONG_CANDIDATE | Knowledge | `NONE` | LOCAL_KNOWLEDGE_VAULT | NO | AVAILABLE_IF_MEASURED |
| actions-runner-host | HIGH_VALUE_INTEGRATION_CANDIDATE | GitHub / CI | `github.export|github.sync` | EXTERNAL_CI_REFERENCE | NO | REFERENCE_ONLY |
| auto_bewerbungen | HIGH_VALUE_INTEGRATION_CANDIDATE | Career | `NONE` | CAREER_SOURCE | NO | SOURCE_VERIFICATION_REQUIRED |
| whatsapp-agent | HIGH_VALUE_INTEGRATION_CANDIDATE | Connectors / WhatsApp | `NONE` | CONNECTOR_CANDIDATE | NO | CONNECTOR_VERIFICATION_REQUIRED |
| matrix_shadowops | HIGH_VALUE_INTEGRATION_CANDIDATE | Projects / Integrations | `NONE` | REFERENCE_ONLY | NO | SOURCE_CLASSIFICATION_REQUIRED |
| shadowops-local-hold | HIGH_VALUE_INTEGRATION_CANDIDATE | Evidence / Archive | `NONE` | REFERENCE_ONLY | NO | DISCOVERED |
| openclaw-workspace | HIGH_VALUE_INTEGRATION_CANDIDATE | Agents / Workflows | `workflow.execute` | REFERENCE_ONLY | NO | GOVERNANCE_MAPPING_REQUIRED |

## Promotion contract

```text
DISCOVERED != CONFIGURED
CONFIGURED != REACHABLE
REACHABLE != REAL_DATA

READY requires verified:
  configuration
  + reachability
  + real data
  + governance mapping where execution is possible
```

No discovered executable is automatically promoted.

Workflow/script candidates remain REFERENCE_ONLY until:

1. adapter exists
2. RiskPolicy mapping exists
3. CapabilityRegistry mapping exists
4. ExecutionService routing exists
5. PrivacyGate is applied
6. Audit evidence is produced
7. runtime verification passes

## Safety

```text
SECRET_VALUES_READ=0
SECRET_VALUES_EXPOSED=0
SOURCE_MUTATIONS=0
EXECUTION_ATTEMPTS=0
AUTO_PROMOTIONS=0
```
