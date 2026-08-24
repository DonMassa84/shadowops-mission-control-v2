# ShadowOps UI route inventory

Verified against `mix phx.routes ShadowOpsWeb.Router` and the Phoenix sources on 2026-08-23.

| Screen | Browser route | Backend/source | Classification | Notes |
|---|---|---|---|---|
| Mission Control | `/` | readiness, workflow registry, run/approval/audit stores, systemctl, Ollama, knowledge/evidence metadata | CONNECTED | Real values or explicit source state only. |
| Workflows | `/workflows` | canonical workflow registry v2 | CONNECTED | Search, type/domain/status/runtime filters and sort. |
| Workflow detail | `/workflows/:id` | registry, durable runs, audit | CONNECTED | Missing registry fields are labelled unavailable. |
| Runs | `/runs`, `/runs/:id` | append-only run event store | CONNECTED | No generated historical runs. |
| Services | `/services` | `systemctl --user` and system `systemctl` | CONNECTED | Read-only; scope/state/source filters. |
| Nodes | `/nodes` | none | NOT_CONNECTED | No canonical node registry plus health contract exists. |
| Agents | `/agents` | none | NOT_CONNECTED | Arbitrary processes are not treated as agents. |
| AI | `/ai` | `ollama list` | CONNECTED | Runtime can become UNAVAILABLE; header row excluded. |
| Knowledge | `/knowledge` | configured knowledge directories | CONNECTED | Metadata only; no note content or absolute path. |
| Facebook | `/social/facebook` | privacy-guarded aggregate analytics | CONNECTED | Existing analytics implementation retained. |
| Messenger | `/social/messenger` | none | NOT_CONNECTED | Requires a current privacy-reviewed connector. |
| WhatsApp | `/social/whatsapp` | none | NOT_CONNECTED | Historical workflow metadata is not an operational connector. |
| Telegram | `/social/telegram` | none | NOT_CONNECTED | No current local connector. |
| Approvals | `/approvals`, `/approvals/:id` | append-only approval event store | CONNECTED | Decisions remain authenticated API writes. |
| Security | `/security` | runtime checks and dependency-audit evidence | CONNECTED | No secrets rendered. |
| Audit | `/audit` | durable hash-chained audit journal | CONNECTED | Read action recomputes the chain. |
| Evidence | `/evidence` | `docs/evidence` | CONNECTED | Privacy-safe artifact metadata only. |
| Logs | `/logs` | none approved | NOT_CONNECTED | No safe bounded/redacted log contract. |
| i7 learning display | `/display/i7` | `learning_focus.yaml` | CONNECTED | Previously verified implementation unchanged. |
| Health/readiness | `/health`, `/ready` | endpoint and required dependencies | CONNECTED | JSON operational contracts. |
| Infrastructure legacy | `/infrastructure` | legacy page | PARTIAL | Retained for compatibility; not in canonical sidebar. |
| Compute legacy | `/compute` | legacy page | PARTIAL | Retained for compatibility; not in canonical sidebar. |
| Jobs legacy | `/jobs` | legacy page | PARTIAL | Superseded by Runs; retained for compatibility. |
| Settings legacy | `/settings` | legacy page | PARTIAL | Retained; no unauthenticated mutation controls. |

`MISSING`: none among the requested Mission Control routes.
