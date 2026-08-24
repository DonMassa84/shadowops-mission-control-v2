# Mission Control backend contract

## Source-state contract

Every operational surface reports `AVAILABLE`/`CONNECTED`, `UNAVAILABLE`, or `NOT_CONNECTED`. Empty durable stores are valid connected stores and are described as having no records; an empty list is never used to claim an optional integration is healthy.

| Area | Read contract | Write contract | Refresh guidance |
|---|---|---|---|
| Workflows | `/api/workflows`, registry v2 | `POST /api/workflows/:id/run` | 30–60 seconds |
| Runs | `/api/runs`, `/api/runs/:id` | workflow execution path only | 5–15 seconds |
| Services | `/api/services` | none exposed in UI | 10–15 seconds |
| AI | `/api/ai/status` | none | 15 seconds |
| Approvals | `/api/approvals`, `/api/approvals/:id` | create/approve/reject through write pipeline | 5–15 seconds |
| Audit | `/api/audit`, `/api/audit/verify` | application governance events only | 10–30 seconds |
| Security | `/api/security/status` | none | 30–60 seconds |
| Knowledge | `/api/knowledge` | none | 60–300 seconds |
| Evidence | `/api/evidence` | none | 60–300 seconds |

## Write invariants

- The backend requires a configured bearer write token and `x-shadowops-actor`.
- Writes fail closed when the write token is absent.
- Workflow execution requires an APPROVED durable record matching action `workflow.execute` and the workflow ID.
- Runs persist only API requests made against an ID in the canonical registry.
- Lifecycle transitions are validated: `QUEUED → RUNNING → SUCCESS|FAILED|BLOCKED`, or `QUEUED → BLOCKED`.
- Approval terminal states cannot transition again; expired records are presented as `EXPIRED`.
- Approval decisions and run transitions append audit events; the audit chain exposes `previous_hash` and `current_hash` verification.
- The workflow executor uses argv-based `System.cmd` and accepts only absolute regular runtime files from the trusted registry. It does not evaluate shell strings.

## Privacy and availability

Evidence and knowledge screens expose source basenames, counts, timestamps, artifact names, and verification state. They do not expose note bodies or absolute paths. Nodes, agents, logs, Messenger, WhatsApp, and Telegram stay `NOT_CONNECTED` until a current canonical source is introduced.
