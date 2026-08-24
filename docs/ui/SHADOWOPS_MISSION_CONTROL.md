# ShadowOps Mission Control

## Implementation

The Mission Control is a Phoenix LiveView/HEEx interface around the existing control-plane contexts. `ShadowOpsWeb.MissionControlComponents` supplies the application shell, grouped sidebar, top bar, badges, metrics, panels, source metadata and unavailable states. `/assets/mission-control.css` defines the dark operations palette, responsive layout, semantic focus treatment and reduced-motion behavior. No second frontend framework was added.

The canonical navigation is:

- Dashboard
- Operations: Workflows, Runs, Services, Nodes
- Intelligence: Agents, AI, Knowledge
- Social: Facebook, Messenger, WhatsApp, Telegram
- Governance: Approvals, Security, Audit, Evidence, Logs
- System: i7 Display, Health, Readiness

## Operational behavior

Workflows come from the schema-v2 registry and link to configuration, runtime, policy, real run and audit views. The execution UI describes the authenticated API boundary and does not put tokens into HTML. Durable Runs and Approvals use append-only local JSONL event stores and survive application restarts. Services and Ollama views execute only their established read contracts. Optional areas without a source render a reasoned `NOT_CONNECTED` state.

The dashboard refreshes high-changing summary state every 15 seconds after LiveView connection. Registry data is loaded once per workflow view; knowledge and evidence metadata are loaded once per page request. The implementation avoids per-component runtime commands.

## Accessibility and privacy

The shell includes a skip link, semantic navigation, current-page state, semantic tables, visible keyboard focus, text labels in every status badge, responsive breakpoints and reduced-motion handling. Evidence, knowledge and Facebook freshness displays avoid private absolute source paths.

## Security verification

The Security page derives its state from the registry, audit verifier, learning-source allowlist, write-token configuration, approval policy, redaction self-check and recorded dependency audit. Bandit was updated from 1.12.4 to 1.12.5; `mix hex.audit` then returned no retired or advisory packages. High-risk actions remain backend-authorized and audited.
