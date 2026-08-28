# External Workflow Import Proposal

This document is generated from the canonical registry source.

**Mode:** dry-run proposal
**Registry mutation:** NO
**Runtime execution:** NO
**Proposal SHA256:** `2470ca6f4915f658cb3768b31d094d51dac1eb989aa266a65968e3ecdf3dfd28`

## Accounting

| Metric | Count |
|---|---:|
| Raw declared occurrences | 77 |
| Subset occurrences | 16 |
| Proven duplicate occurrences | 16 |
| Unique declared slots | 61 |
| Concrete definitions | 16 |
| Not imported ID slots | 45 |
| Canonical collisions | 0 |
| Validation errors | 0 |

## Concrete candidates

| Canonical ID | Source | Risk | Capability | Runtime | Approval |
|---|---|---|---|---|---|
| `so:wf:v1:whatsapp-agent-pack-whatsapp-backup` | whatsapp_agent_pack | L1 | WHATSAPP_MAINTENANCE | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-contacts` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-doctor` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-maintenance-15min` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-maintenance-daily` | whatsapp_agent_pack | L1 | WHATSAPP_MAINTENANCE | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-maintenance-hourly` | whatsapp_agent_pack | L1 | WHATSAPP_MAINTENANCE | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-meta-status` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-meta-subscribe` | whatsapp_agent_pack | L2 | WHATSAPP_ACTION | TCC | true |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-purge-expired` | whatsapp_agent_pack | L2 | WHATSAPP_ACTION | TCC | true |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-queue` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-report` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-retry-all` | whatsapp_agent_pack | L1 | WHATSAPP_MAINTENANCE | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-status` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-sync-status` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-worker-drain` | whatsapp_agent_pack | L1 | WHATSAPP_MAINTENANCE | TCC | false |
| `so:wf:v1:whatsapp-agent-pack-whatsapp-worker-status` | whatsapp_agent_pack | L0 | WHATSAPP_MONITORING | TCC | false |


## Blockers

- `{"count":45,"type":"UNRESOLVED_DECLARED_SLOTS"}`
- `{"declared_count":6,"source_set":"telegram_workflow_controller","type":"WORKFLOW_IDS_NOT_IMPORTED"}`
- `{"declared_count":7,"source_set":"opencode_standard","type":"WORKFLOW_IDS_NOT_IMPORTED"}`
- `{"declared_count":48,"source_set":"shadowmaker_tasks","type":"WORKFLOW_IDS_NOT_IMPORTED"}`


## Safety

- Registry mutation: NO
- Runtime execution: NO
- 4013 promotion: NO
- 4014 mutation: NO
- Deploy: NO
- Force push: NO
