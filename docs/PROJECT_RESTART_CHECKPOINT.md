# ShadowOps Project Restart Checkpoint

**Snapshot:** 2026-08-28  
**Purpose:** canonical restart entrypoint after reboot, context loss, stopped OpenCode process, or long pause.

> This file is a checkpoint, not a replacement for newer GitHub state. If a PR/Issue/handoff is newer than this snapshot, the newer durable GitHub state wins.

---

## 1. Restart procedure

After any restart or long pause:

1. `git fetch` and verify repository/worktrees.
2. Read this file first.
3. Read PR #24 (MiMo), PR #25 (V2.5), PR #26 (Hy3).
4. Read Issue #27 (global orchestration).
5. Read Issue #28 (Agent Supervisor).
6. Read Issue #29 (Communications Backbone).
7. Compare each local worker HEAD with its remote worker branch.
8. Preserve any uncommitted work before branch changes.
9. Resume only from the newest durable `NEXT_ACTION`.

Canonical recovery rule:

```text
GitHub remote HEAD + PR/Issue comments + handoff
        ↓
reconstruct worker state
        ↓
verify local worktree/branch
        ↓
resume NEXT_ACTION
```

Never reconstruct state from memory alone.

---

## 2. Global safety invariants

```text
NO_FORCE_PUSH
NO_UNREVIEWED_RESET/CLEAN/RESTORE/STASH-DROP
NO_WORKER_PUSH_TO_MAIN_OR_BASE
NO_AUTOMATIC_MERGE
NO_AUTOMATIC_DEPLOY
NO_4013_PROMOTION_WITHOUT_EXPLICIT_APPROVAL
NO_ARBITRARY_SHELL_PATH
NO_ARBITRARY_EXECUTABLE_PATH
NO_ARBITRARY_SYSTEMD_UNIT
NO_APPROVAL_BYPASS
NO_RISK_DOWNGRADE_BY_EVIDENCE
UNKNOWN_CAPABILITY_FAILS_CLOSED
UNKNOWN_RUNTIME_FAILS_CLOSED
UNKNOWN_RISK_FAILS_CLOSED
UNKNOWN_MESSAGE/SENDER/CHANNEL_FAILS_CLOSED
```

Canonical actionable path:

```text
Request
→ actor/context
→ CapabilityRegistry
→ Policy/Risk
→ Approval
→ PrivacyGate
→ ExecutionService
→ bounded Adapter
→ Result
→ Audit + Evidence
```

No controller, LiveView, Telegram bot, Discord bot, bridge, supervisor, or worker may bypass this chain.

---

## 3. Definitions of completion

Use these exact stages:

```text
LOCAL_ONLY
COMMITTED_LOCAL
PUSHED
REMOTE_HEAD_VERIFIED
GITHUB_GREEN
INTEGRATED_CANDIDATE
4015_ACCEPTED
4013_PROMOTED
```

Workflow lifecycle:

```text
DISCOVERED
→ NORMALIZED
→ CONNECTED
→ TESTED
→ PRODUCTION_READY
```

`PRODUCTION_READY` requires at minimum:

```text
real_data=true
synthetic=false
reachable=true
runtime_verified=true
execution_tested=true
governance_mapped=true
```

---

## 4. Current worker state

### MiMo — PR #24

```text
BRANCH=ai/mimo-governance
REMOTE_HEAD=2f391df12ad627266160b682fc24759de653ae01
PR=OPEN_DRAFT
MERGED=NO
```

Established governance result:

```text
MIMO_GITHUB_GREEN=YES
FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0
FULL_TEST_RC=0
RISK_DOWNGRADE_BLOCKED=PASS
APPROVAL_BYPASS_BLOCKED=PASS
```

Important: `docs/agent-handoffs/mimo-status.md` currently contains an older `HEAD=f192d82`; the remote PR head above is newer and authoritative until MiMo refreshes the handoff.

Open MiMo work:

- Issue #28 Agent Supervisor fail-closed governance review.
- Issue #29 Communications Backbone security/governance review.
- i7 bounded-capability governance regression review as needed.

MiMo reviews/hardens governance; it does not own core supervisor/comms implementation.

---

### V2.5 — PR #25

```text
BRANCH=ai/v25-workflows
REMOTE_HEAD=9e1decb9a6e1b98b0870cfb5d10910b30fd693e3
PR=OPEN_DRAFT
MERGED=NO
V25_RECOVERY_SHA=da361d225e2b2f54f3c71b12800b8411a95f41e2
```

Current inventory checkpoint:

```text
RAW_TOTAL=5175
LOCALWF_REGISTERED=500
UNIQUE=500
NORMALIZED=489
REJECTED=4675
DUPLICATES=0
CONNECTED=10
TESTED=0
PRODUCTION_READY=0
BLOCKED=1

RISK_L0=35
RISK_L1=331
RISK_L2=108
RISK_L3=26
RISK_TOTAL=500

SYNTHETIC_READY=0
MOCK_READY=0
UNKNOWN_RUNTIME_READY=0
UNKNOWN_CAPABILITY_READY=0
UNKNOWN_RISK_READY=0
ARBITRARY_COMMANDS=0
ARBITRARY_EXECUTABLE_PATHS=0
ARBITRARY_SYSTEMD_UNITS=0
```

Connected workflows:

| Workflow | Risk | Capability | Adapter |
|---|---:|---|---|
| `localwf_projects_2bfcaef0d5b8` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_2bfde0029ca0` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_34cdb22dfe1d` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_53bb185be57b` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_5b74eb4b262e` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_6b34f484140f` | L0 | `node.status` | `ScriptAdapter` |
| `localwf_projects_bd7888260092` | L2 | `service.status` | `SystemdAdapter` |
| `localwf_projects_fcac239a2dbc` | L2 | `node.status` | `ScriptAdapter` |
| `localwf_proofflow-obsidian-vault_598ffb03958e` | L1 | `knowledge.read` | `ScriptAdapter` |
| `localwf_proofflow-obsidian-vault_6fc36a3a1df6` | L1 | `knowledge.read` | `ScriptAdapter` |

### V2.5 next P0

Do not expand broad inventory first. Convert the 10 `CONNECTED` workflows into truthful `TESTED` workflows one-by-one:

```text
RunState
+ real bounded execution
+ Audit
+ PrivacyGate
+ ExecutionAttestation
= TESTED
```

If a workflow fails the gate, keep/demote it to `REFERENCE_ONLY` with an explicit blocker.

Suggested ExecutionAttestation fields:

```text
workflow_id
capability
risk
actor
approval_id
adapter
runtime_target
tested_sha
started_at
finished_at
result
exit_code
input_sha256
output_sha256
evidence_sha256
audit_id
trace_id
```

Other V2.5 ownership:

- Agent Supervisor implementation — Issue #28.
- Communications Backbone core/router/adapters — Issue #29.
- i7 node-agent/backend/QA integration once legitimate auth exists.

---

### Hy3 — PR #26

```text
BRANCH=ai/hy3-acceptance
REMOTE_HEAD=7a91289d22597e62ffb3b8e59b427a95539ef1f9
PR=OPEN_DRAFT
MERGED=NO
```

Remote handoff still says `STATUS=READY_FOR_WORK`; therefore PR #26 is not yet GitHub-green.

Latest locally reported audit result:

```text
ROOT_CAUSE=CanonicalEvent missing approval.consumed
LOCAL_FIX=add approval.consumed to canonical event types
LOCAL_FULL_TEST=106 passed, 0 failures
DOUBLE_CONSUME=BLOCKED
APPROVAL_PATH_CONSISTENT=PASS
SINGLE_USE_SEMANTICS=PASS
```

The worker reported `da361d2` and the `canonical_event.ex` fix were not yet present on PR #26.

Orchestrator decision: **commit + push to `ai/hy3-acceptance`** while keeping the PR draft.

Hy3 restart steps:

```text
1. Read latest PR #26 instructions.
2. Preserve local work.
3. Bring da361d2 onto ai/hy3-acceptance losslessly.
4. Add canonical_event.ex fix as a separate commit.
5. Run full gates.
6. Push ai/hy3-acceptance.
7. Verify LOCAL_HEAD == REMOTE_HEAD.
8. Refresh docs/agent-handoffs/hy3-status.md and outbox.
```

Target:

```text
HY3_GITHUB_GREEN=YES
FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0
WORKFLOW_ENGINE_RC=0
FULL_TEST_RC=0
APPROVAL_SINGLE_USE=PASS
AUDIT_CHAIN=PASS
REMOTE_HEAD_MATCH=YES
READY_FOR_INTEGRATION=YES
```

---

### Nemo — 4015 UI

Target branch:

```text
ai/4015-ui-acceptance
```

At this snapshot there is no remote branch matching `4015-ui`; Nemo has no durable worker-branch checkpoint yet.

Nemo scope:

```text
/
/workflows
/runs
/jobs
/approvals
navigation
RUNNABLE vs REFERENCE_ONLY UI
safe Run/Approval controls
4015 browser/LiveView acceptance
i7 Nodes UI from backend contract
communications health UI after backend exists
```

Nemo must not change:

```text
CapabilityRegistry semantics
RiskPolicy semantics
ApprovalStore semantics
workflow promotion rules
core supervisor logic
core communications routing/governance
```

Nemo restart priority:

```text
1. Read Issue #27 and Issue #29.
2. Create ai/4015-ui-acceptance from the current approved base.
3. Diagnose/fix the 4015 root/UI timeout.
4. Expose actions only for proven RUNNABLE records.
5. Test, commit, push, verify remote head.
6. Publish durable heartbeat.
```

---

## 5. Runtime roles

```text
4015 = integration/acceptance preview
4013 = stable/productive runtime
4014 = untouched
```

Last explicit 4015 HTTP evidence:

```text
/              HTTP=000
/health        HTTP=200
/ready         HTTP=200
/workflows     HTTP=200
/api/workflows HTTP=200
```

Therefore `4015_ACCEPTANCE` remains FAIL/UNPROVEN until root/UI/browser usability passes.

Final 4015 gate:

```text
INTEGRATION_HEAD=
SOURCE_HEADS=
FORMAT_RC=0
COMPILE_RC=0
FULL_TEST_RC=0
HEALTH_HTTP=200
READY_HTTP=200
API_ACCEPTANCE=PASS
GOVERNANCE_ACCEPTANCE=PASS
APPROVAL_ACCEPTANCE=PASS
AUDIT_VERIFY=PASS
SECURITY_ACCEPTANCE=PASS
4015_UI_ACCEPTANCE=PASS
4015_ACCEPTANCE=PASS
```

4013 promotion only after exact 4015 candidate passes and Hy3 audits that exact candidate, followed by explicit approval.

---

## 6. Ryzen + i7 topology

Target machine roles:

```text
Ryzen host
  = primary ShadowOps dev/integration host
  = GitHub bridge
  = Communications Router authority
  = worker orchestration / 4015 preview

Secondary i7 node
  = ShadowOps node agent
  = independent QA/compute worker
  = heartbeat/status source
  = bounded remote operations target
  = optional standby communications relay only after separate acceptance
```

### Current i7 truth

```text
I7_NETWORK_REACHABLE=YES
I7_SSHD_REACHABLE=YES
I7_EXISTING_TESTED_KEYS=ALL_REJECTED
I7_AUTH=BLOCKED
I7_REMOTE_BOOTSTRAP_PATH=NONE_CONFIRMED
I7_RUNTIME=NOT_CONNECTED
I7_COMMS_AGENT=NOT_DEPLOYED
I7_COMPUTE=NOT_ACTIVE
I7_CPU_LOAD=UNKNOWN
```

Do not retry random identities, brute-force, or weaken SSH.

### i7 target node-agent

Prefer a dedicated user-level service on the i7:

```text
shadowops-node-agent.service
NODE_ID=i7
```

The node agent must communicate outbound to the primary ShadowOps communications/runtime plane and must not require duplicated Telegram/Discord bot secrets by default.

Allowed model:

```text
Telegram / Discord / GitHub
          |
          v
Ryzen: ShadowOps Comms Router
          |
          +--> MiMo/V2.5/Hy3/Nemo
          |
          +--> i7 Node Agent
                    |
                    +--> heartbeat/status
                    +--> QA/compute
                    +--> logs/evidence
                    +--> ExecutionAttestation
```

Bounded i7 capabilities after legitimate auth:

```text
L0: status, CPU/load, RAM, GPU, temperature, disk, network, service status/logs, git head
L1: exact-SHA QA checkout, format, compile, target tests, full test
L2: allowlisted service start/stop/restart + approval
L3: reboot/shutdown + approval
```

No free-form shell/command interface through ShadowOps.

First post-auth action must be read-only discovery: hostname/OS, CPU/load, RAM, GPU, temperature, disk, network, git, Elixir/Erlang.

Required i7 acceptance:

```text
I7_NODE_AGENT_INSTALLED=PASS
I7_NODE_AGENT_ACTIVE=PASS
I7_HEARTBEAT=PASS
I7_MESSAGE_ACK=PASS
I7_STATUS_READ=PASS
I7_QA_EXACT_SHA=PASS
I7_EXECUTION_ATTESTATION=PASS
I7_SECRET_LEAKAGE=0
I7_ARBITRARY_COMMAND_PATH=0
I7_APPROVAL_BYPASS=0
```

---

## 7. Agent Supervisor — Issue #28

Purpose: restart stopped workers after login/reboot and resume from durable GitHub/handoff/inbox state.

Verified user-systemd baseline:

```text
Linger=yes
shadowops-agent-bridge.service enabled
shadowops-agent-bridge.service active
USER_SYSTEMD_BOOT_BASE=PASS
BRIDGE_BOOT_PERSISTENCE=PASS
```

This does not yet prove a literal post-reboot worker auto-resume.

Still missing:

```text
SUPERVISOR_ENABLED
SUPERVISOR_ACTIVE
BOOT_RECOVERY
AUTO_RESUME
GREEN_WORKER_NOT_RESTARTED
HEARTBEAT_AFTER_BOOT
CRASH_LOOP_PROTECTION
```

Target flow:

```text
Linux login/reboot
→ systemd --user
→ bridge
→ Agent Supervisor
→ read durable worker state
→ GREEN? leave idle
→ STOPPED/RECOVERING? start worker
→ read inbox + handoff
→ resume NEXT_ACTION
→ publish heartbeat
```

Protections:

- bounded restart backoff,
- no crash-loop storms,
- preserve uncommitted work,
- no wrong-branch restart,
- no arbitrary launcher/unit control,
- no production mutation.

---

## 8. Communications Backbone — Issue #29

Goal: replace ad-hoc Markdown-only communication with a real, auditable, restart-safe multi-channel plane.

Target architecture:

```text
Worker / Operator / Orchestrator
          |
          v
ShadowOpsCore.Comms.MessageEnvelope
          |
          v
ShadowOpsCore.Comms.Router
          |
          +--> DeliveryLedger / Idempotency / ACK / Retry
          +--> GitHubAdapter      # durable truth/recovery
          +--> TelegramAdapter    # realtime
          +--> DiscordAdapter     # realtime
          +--> LocalBridgeAdapter # migration compatibility
          +--> i7 NodeAgent       # secondary node
```

GitHub remains authoritative for durable task/decision/blocker/green checkpoints.

Telegram target:

- manager/control bot,
- dedicated or logical worker identities,
- long polling initially,
- operator/chat allowlists,
- deduplication + max hops + loop protection,
- no direct shell/workflow authority.

Discord target:

- one ShadowOps bot/application,
- logical worker channels/threads,
- suggested channels: `shadowops-control`, `mimo`, `v25`, `hy3`, `nemo`, `approvals`, `alerts`, `audit`, `i7`,
- Gateway for bidirectional bot communication,
- outbound webhooks optional for mirrors only,
- guild/channel/role allowlists.

MessageEnvelope v1:

```text
schema_version
message_id
correlation_id
causation_id
trace_id
sender
recipient
message_type
priority
risk
requires_ack
created_at
expires_at
hop_count
max_hops
body
refs
metadata
```

Delivery states:

```text
CREATED
→ QUEUED
→ SENT
→ DELIVERED
→ ACKED
→ CONSUMED
```

Failure states:

```text
RETRYING
EXPIRED
FAILED
```

Required controls:

```text
DEDUPLICATION
REPLAY_PROTECTION
MAX_HOPS
LOOP_DETECTION
RATE_LIMIT
ACK_TRACKING
BOUNDED_RETRY
TTL_EXPIRY
IDENTITY_ALLOWLISTS
SECRET_REDACTION
TRANSPORT_OUTAGE_RECOVERY
```

Transport secrets must never be committed. Target local file:

```text
~/.config/shadowops/secrets/communications.env
mode 0600
```

Example variable names only:

```text
TELEGRAM_*_TOKEN
DISCORD_BOT_TOKEN
DISCORD_GUILD_ID
```

Never write real values to GitHub/handoffs/logs/screenshots.

Target user-service topology:

```text
shadowops-agent-bridge.service
shadowops-comms.service
shadowops-agent-supervisor.service
```

On the i7, later:

```text
shadowops-node-agent.service
```

Current state: Issue #29 is architecture/assignment only; Telegram/Discord/i7 comms runtime is not yet proven connected.

---

## 9. Worker ownership

### V2.5

- core MessageEnvelope/Router/DeliveryLedger,
- Telegram + Discord adapters,
- user-service runtime integration,
- Agent Supervisor implementation,
- 10 connected workflows → real execution/attestation,
- i7 node-agent/backend integration after auth.

### MiMo

- fail-closed governance,
- sender/channel identity model,
- spoof/replay protection review,
- L2/L3 approval invariants,
- supervisor state-machine review,
- communications/i7 security review.

### Hy3

- adversarial acceptance,
- duplicate/replay/loop-storm tests,
- forged sender/channel tests,
- transport outage/recovery,
- secret leakage tests,
- exact integrated candidate audit.

### Nemo

- UI consumer only,
- 4015 root/workflow/run/approval UI,
- communications health/status,
- worker + i7 heartbeat visualization,
- alerts + per-channel delivery state,
- no routing/governance core ownership.

---

## 10. Architecture patterns already selected

Use patterns, not wholesale platform replacement.

- **Temporal:** heartbeat timeout, retry/backoff, attempt and total timeouts, cancellation semantics.
- **Kestra:** explicit run state machine + append-only state history.
- **Argo:** conceptual `SUSPEND → APPROVE → RESUME` for L2/L3.
- **Backstage:** backend permission projection: `ALLOW`, `CONDITIONAL`, `DENY`; UI never decides security.
- **in-toto/Witness:** ExecutionAttestation/provenance for `TESTED` promotion.
- **OpenTelemetry:** one `trace_id` across Request → Policy → Approval → Execution → Audit → Evidence.

Suggested modules:

```text
ShadowOpsCore.RunStateMachine
ShadowOpsCore.ExecutionAttestation
ShadowOpsCore.ExecutionTrace
ShadowOpsCore.ExecutionCircuitBreaker
ShadowOpsAgentSupervisor.StateMachine
ShadowOpsCore.Comms.MessageEnvelope
ShadowOpsCore.Comms.Router
ShadowOpsCore.Comms.DeliveryLedger
ShadowOpsNodeAgent
```

---

## 11. Restart-safe checkpoint format

Every meaningful worker checkpoint must publish:

```text
AGENT=
HEAD=
PHASE=
STATE=WORKING|BLOCKED|DEPENDENCY_WAIT|GREEN
LAST_COMPLETED_GATE=
NEXT_ACTION=
BLOCKER=
DEPENDENCY=
PUSHED_SHA=
REMOTE_HEAD_MATCH=YES|NO
```

Completed code flow:

```text
WORK
→ TEST
→ COMMIT
→ PUSH WORKER BRANCH
→ VERIFY REMOTE HEAD
→ UPDATE HANDOFF + OUTBOX/GITHUB
```

A worker that is intentionally `GREEN` is idle-by-design and must not be crash-loop restarted.

---

## 12. Current P0/P1 order

```text
P0-1  Hy3 persist/push tested approval.consumed fix and recovery candidate
P0-2  V2.5 turn the 10 CONNECTED workflows into truthful TESTED/REFERENCE_ONLY outcomes
P0-3  Nemo create ai/4015-ui-acceptance and publish first real UI checkpoint
P1-1  Implement Agent Supervisor and prove auto-resume/crash-loop protection
P1-2  Implement Communications Backbone core + Telegram + Discord adapters
P1-3  Restore legitimate i7 auth and deploy bounded i7 Node Agent
P1-4  Integrate exact GitHub-green worker SHAs into a 4015 candidate
P1-5  Full 4015 runtime/UI/security/audit acceptance
P1-6  Only then consider 4013 promotion with explicit approval
```

---

## 13. Final production-readiness target

```text
SHADOWOPS_PRODUCTION_READINESS=PASS
FORMAT_RC=0
COMPILE_RC=0
FULL_TEST_RC=0
ALL_WORKFLOWS_CLASSIFIED=PASS
ALL_EXECUTABLES_GOVERNED=PASS
ALL_EXECUTABLES_AUDITED=PASS
SYNTHETIC_READY=0
MOCK_READY=0
UNKNOWN_RUNTIME_READY=0
UNKNOWN_CAPABILITY_READY=0
UNAPPROVED_L2_L3=0
ARBITRARY_COMMAND_PATH=0
APPROVAL_SINGLE_USE=PASS
AUDIT_CHAIN=PASS
EVIDENCE_GATE=PASS
PRIVACY_GATE=PASS
4015_ACCEPTANCE=PASS
4013_PROMOTION_READY=YES
```

Until all required gates are proven, blocked/reference-only states are valid and preferred over false readiness.
