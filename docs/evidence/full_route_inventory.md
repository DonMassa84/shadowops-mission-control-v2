# ShadowOps full route inventory

Generated from the canonical Phoenix router with `mix phx.routes` on 2026-08-23. The umbrella alias resolves to `ShadowOpsWeb.Router`. Total routes: 57.

| Method | Route | Handler | Class | Acceptance expectation |
|---|---|---|---|---|
| GET | `/` | `DashboardLive :index` | UI | 200, real source summary |
| GET | `/infrastructure` | `InfrastructureLive :index` | LEGACY | 200 compatibility page |
| GET | `/compute` | `ComputeLive :index` | LEGACY | 200 compatibility page |
| GET | `/workflows` | `WorkflowsLive :index` | UI | 200, canonical registry |
| GET | `/workflows/:id` | `WorkflowDetailLive :show` | UI | 200 for known ID |
| GET | `/runs` | `RunsLive :index` | UI | 200, durable records or explicit empty state |
| GET | `/runs/:id` | `RunsLive :show` | UI | 200 for persisted ID |
| GET | `/jobs` | `JobsLive :index` | LEGACY | 200 compatibility page |
| GET | `/nodes` | `NodesLive :index` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/services` | `ServicesLive :index` | UI | 200, systemd and Docker records |
| GET | `/agents` | `AgentsLive :index` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/ai` | `AILive :index` | UI | 200, Ollama runtime state |
| GET | `/security` | `SecurityLive :index` | UI | 200, runtime checks |
| GET | `/approvals` | `ApprovalsLive :index` | UI | 200, durable records or explicit empty state |
| GET | `/approvals/:id` | `ApprovalDetailLive :show` | UI | 200 for persisted ID |
| GET | `/audit` | `AuditLive :index` | UI | 200, durable chain |
| GET | `/logs` | `LogsLive :index` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/knowledge` | `KnowledgeLive :index` | UI | 200, metadata only |
| GET | `/evidence` | `EvidenceLive :index` | UI | 200, privacy-safe metadata |
| GET | `/settings` | `SettingsLive :index` | LEGACY | 200 compatibility page |
| GET | `/social/facebook` | `FacebookLive :index` | UI | 200, privacy-safe aggregate source |
| GET | `/social/messenger` | `SocialUnavailableLive :messenger` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/social/whatsapp` | `SocialUnavailableLive :whatsapp` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/social/telegram` | `SocialUnavailableLive :telegram` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| HEAD | `/display/i7` | `I7ProbeController :head` | HEALTH | 200 when learning plan is available |
| GET | `/display/i7` | `I7DisplayLive :index` | UI | 200, six source-backed slides |
| GET | `/api/health` | `HealthController :show` | HEALTH | 200 JSON |
| GET | `/api/ready` | `ReadinessController :show` | HEALTH | 200 only when required checks pass |
| GET | `/api/system/overview` | `SystemOverviewController :show` | API_READ | 200 JSON |
| GET | `/api/workflows` | `WorkflowsController :index` | API_READ | 200 JSON |
| GET | `/api/workflows/:id` | `WorkflowsController :show` | API_READ | 200 known, 404 unknown |
| GET | `/api/runs` | `RunsController :index` | API_READ | 200 JSON |
| GET | `/api/runs/:id` | `RunsController :show` | API_READ | 200 known, 404 unknown |
| GET | `/api/nodes` | `NodesController :index` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/api/nodes/:id` | `NodesController :show` | OPTIONAL_NOT_CONNECTED | 404 with explicit reason |
| GET | `/api/services` | `ServicesController :index` | API_READ | 200 JSON |
| GET | `/api/agents` | `AgentsController :index` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/api/ai/status` | `AIStatusController :status` | API_READ | 200 JSON |
| GET | `/api/ai/models` | `AIStatusController :models` | API_READ | 200 JSON |
| GET | `/api/security/status` | `SecurityController :status` | API_READ | 200 JSON |
| GET | `/api/audit` | `AuditController :index` | API_READ | 200 JSON |
| GET | `/api/audit/verify` | `AuditController :verify` | API_READ | 200 with valid chain |
| GET | `/api/logs/recent` | `LogsController :recent` | OPTIONAL_NOT_CONNECTED | 200 with explicit reason |
| GET | `/api/knowledge` | `KnowledgeController :index` | API_READ | 200, metadata only |
| GET | `/api/evidence` | `EvidenceController :index` | API_READ | 200, metadata only |
| GET | `/api/learning/plan` | `LearningController :plan` | API_READ | 200 for real YAML, 503 unavailable |
| GET | `/api/approvals` | `ApprovalsController :index` | API_READ | 200 JSON |
| GET | `/api/approvals/:id` | `ApprovalsController :show` | API_READ | 200 known, 404 unknown |
| POST | `/api/workflows/:id/run` | `WorkflowsController :run` | API_WRITE | authenticated actor and approval required |
| POST | `/api/approvals` | `ApprovalsController :create` | API_WRITE | authenticated actor required |
| POST | `/api/nodes/:id/actions/healthcheck` | `NodesController :healthcheck` | OPTIONAL_NOT_CONNECTED | authenticated request fails closed with 503 |
| POST | `/api/nodes/:id/actions/start` | `NodesController :start` | OPTIONAL_NOT_CONNECTED | authenticated request fails closed with 503 |
| POST | `/api/nodes/:id/actions/stop` | `NodesController :stop` | OPTIONAL_NOT_CONNECTED | authenticated request fails closed with 503 |
| POST | `/api/approvals/:id/approve` | `ApprovalsController :approve` | API_WRITE | authenticated legal transition only |
| POST | `/api/approvals/:id/reject` | `ApprovalsController :reject` | API_WRITE | authenticated legal transition only |
| GET | `/health` | `HealthController :show` | HEALTH | 200 JSON |
| GET | `/ready` | `ReadinessController :show` | HEALTH | 200 only when required checks pass |

`Nodes`, `Agents`, `Logs`, `Messenger`, `WhatsApp`, and `Telegram` have no canonical privacy-reviewed adapter in this Phoenix application. Their routes intentionally remain `OPTIONAL_NOT_CONNECTED`; this inventory does not infer connectivity from unrelated processes or historical registries.
