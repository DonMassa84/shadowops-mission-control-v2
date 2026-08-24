# ShadowOps Mission Control acceptance evidence

Status date: 2026-08-23

FINAL_STATUS=MISSION_CONTROL_READY
ORIGINAL_MISSION_CONTROL_TESTS=PASS_42
FINAL_1_0_1_REGRESSION=PASS_69

The original UI acceptance below remains historical evidence. PRs #16, #18 and #19 extended the verified release without replacing the Phoenix architecture; the superseding final gate is `docs/evidence/shadowops_1_0_1_release.md`.

## VERIFIED

- Phoenix-native reusable Mission Control shell, sidebar and source/status components.
- Real workflow registry list, filters and detail route.
- Durable approval create/approve/reject/expire/invalid-transition persistence with audit linkage.
- Durable run queue/start/success/failure/block/invalid-transition persistence with audit linkage.
- Real systemd and Docker service inventory and Ollama model inventory.
- Security control view and fail-closed unauthenticated write behavior.
- Audit chain list and verification.
- Privacy-safe knowledge and evidence metadata.
- Explicit `NOT_CONNECTED` pages for nodes, agents, logs, Messenger, WhatsApp and Telegram.
- Existing i7 display implementation retained; its YAML content now contains autonomy-preserving personal strategy reminders and no operational progress claims.
- Bandit 1.12.5; `mix hex.audit`: no retired or advisory packages found.

## PROTOTYPE

None among required Mission Control screens.

## MODELLED

None required for acceptance.

## PLANNED

- Optional connector contracts only if a genuine current source is later approved.

## OPEN

- Nodes: canonical node registry and health contract absent.
- Agents: explicit agent registry absent.
- Logs: approved bounded/redacted log registry absent.
- Messenger, WhatsApp, Telegram: current privacy-reviewed connectors absent.

## Evidence references

- Dependency audit: `docs/evidence/security_dependency_audit.json`
- UI inventory: `docs/ui/UI_ROUTE_INVENTORY.md`
- Backend contract: `docs/ui/UI_BACKEND_CONTRACT.md`
- Full-function report: `docs/evidence/full_function_acceptance.md`
- Browser screenshots: `docs/evidence/full-function-screenshots/` contains desktop captures for dashboard, workflows, workflow detail, runs, services, AI, security, approvals, audit, evidence, knowledge, Facebook and i7, plus a responsive dashboard and physical i7 strategy rotation pair.

## Browser verification

- Fresh Phoenix process on loopback port 4013 with Bandit 1.12.5.
- All requested browser and API routes returned HTTP 200; unauthorized workflow execution returned HTTP 503 `writes_disabled`.
- Headless Chrome rendered every acceptance screen at 1440×1000; the i7 route at 1920×1080 and the dashboard at 390×844.
- DOM inspection found the application shell, Mission Control title and source availability content; no critical Chrome renderer error or missing application asset was observed.
- Visual inspection confirmed readable tables, explicit empty/unavailable states, current-route navigation, no blank screen and a compact horizontally scrollable mobile navigation.
