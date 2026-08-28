# Kali Versioned Coordination State

This file is the durable Git version of the current Kali-related ShadowOps coordination state.

## Canonical repository

REPOSITORY=DonMassa84/shadowops-mission-control-v2
INTEGRATION_BRANCH=local/all-developments
INTEGRATION_SHA_AT_ASSIGNMENT=f4a61dc35a6afd2120e7630d5c7389f1bbdbfbb1
GLOBAL_COORDINATION_ISSUE=27

## Kali node contract

NODE_ID=kali
HOSTNAME=kali-2026
TYPE=security_node
SPECIALIZATION=security_forensics
NAT_IP=192.168.122.238
SHADOWLAB_IP=10.20.0.173
SSH_USER=schattenmacher
SSH_IDENTITY_HOST_PATH=~/.ssh/id_ed25519_shadow_kali
SCHEDULER_PRIORITY=preferred_for_matching_capability
EXECUTION_POLICY=bounded_workflows_only
TARGET_POLICY=owned_or_explicitly_authorized_scope_only
CAPABILITY_ACTIVATION=requires_current_runtime_tool_evidence

## Infrastructure routing policy

Security / forensics / network analysis -> Kali
AI / GPU / local models -> Ryzen
QA / auxiliary compute -> i7

Routing must fail closed when the requested capability is unknown or when current node/tool evidence is missing. A node must not report READY from declared metadata alone.

## Kali finalizer workstream

BRANCH=ai/kali-finalizer
ASSIGNMENT_ISSUE_COMMENT=5448263549
STATUS_FILE=docs/agent-handoffs/kali-finalizer-status.md
ACCEPTANCE_RUNBOOK=docs/runbooks/4015-kali-acceptance.md

Scope:
- finish remaining bounded production-readiness work,
- complete capability routing,
- prove Kali capabilities,
- close blocking CI gates,
- close V2.5 convergence,
- freeze one final candidate SHA,
- perform exact-head 4015 acceptance,
- perform independent Kali security acceptance,
- publish final report to Issue #27,
- stop before production promotion.

## MiMo Kali GitHub bridge workstream

BRANCH=ai/kali-bridge-mimo
DRAFT_PR=31
TASK_COMMIT=2923dbfd320b85fd0fdb37270b9d8f933f15989f
TASK_FILE=docs/agent-handoffs/kali-bridge-mimo-task.md
GLOBAL_ASSIGNMENT_COMMENT=5448337411

Target transport:

```text
GitHub Issue/PR
-> bounded Kali inbox
-> task validation and deduplication
-> bounded OpenCode handoff
-> Kali outbox
-> durable GitHub status/evidence
```

Required bridge gates:

```text
KALI_GITHUB_READ=PASS
KALI_GITHUB_INBOX=PASS
KALI_TASK_RECEIVE=PASS
KALI_TASK_DEDUP=PASS
KALI_OPENCODE_HANDOFF=PASS
KALI_OUTBOX=PASS
KALI_GITHUB_STATUS_PUBLISH=PASS
KALI_RECOVERY=PASS
ARBITRARY_EXECUTION=BLOCKED
ARBITRARY_SYSTEMD=BLOCKED
4013_MUTATION=NO
```

## Existing worker state

MiMo governance:
- branch `ai/mimo-governance`
- verified worker head `1c6322c9eabe40e99d31e40fd997853f2051fd60`
- governance review complete and tests green.

Hy3 acceptance:
- branch `ai/hy3-acceptance`
- verified worker head `3e6abc3c283901994efdb1e470acc9b3e056260e`
- independent governance acceptance complete.

V2.5:
- branch `ai/v25-workflows`
- last known head `e62476853cadd3ef6b8e887827716262f7ff005b`
- truthful terminal workflow accounting remains CONNECTED=10, TESTED=0, BLOCKED_FROM_TESTED=10, PRODUCTION_READY=0 until real canonical execution attestations exist.
- formal current-base convergence report remains required.

## Production boundary

PR #16 remains the integration-to-main lifecycle PR and is not authorized for merge by this state file.

Hard constraints:

```text
NO_MERGE
NO_DEPLOY
NO_FORCE_PUSH
NO_PRODUCTION_MUTATION
NO_4013_MUTATION
```

Production promotion is a separate future operator decision after exact-head CI, 4015 and Kali acceptance all pass.

## Persistence rule

Important coordination, task, gate, blocker and acceptance information must be persisted in GitHub through one or more of:

1. versioned worker-branch files,
2. worker PR comments,
3. global Issue #27 comments.

Nothing important should exist only in an OpenCode chat or terminal output. Before the final exact-head acceptance phase, version changes normally. Once the final candidate SHA is frozen, do not add documentation commits to that candidate; persist final acceptance evidence to Issue #27 instead so the tested SHA remains unchanged.
