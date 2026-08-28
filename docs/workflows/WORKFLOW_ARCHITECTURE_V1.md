# ShadowOps Workflow Architecture v1

Status: migration foundation
Scope: existing ShadowOps workflows, pipelines, communication flows, historical ChatGPT-developed flows, and future library examples.

## Workflow types

- `STATIC` — fixed, deterministic, reproducible workflow.
- `PARAMETERIZED` — fixed structure with runtime inputs such as source, file, repository, node, message, or thread.
- `TEMPLATE` — reusable library pattern that can be adapted to a concrete task.
- `AI_COMPOSED` — AI proposes a workflow by composing registered capabilities only; AI never executes directly.
- `EVENT_DRIVEN` — workflow instance created from a trusted event or schedule.

## Core execution contract

Every workflow type uses the same controlled chain:

`Workflow -> Input Validation -> Capability Validation -> Risk Classification -> Approval Gate -> Executor Binding -> Run -> Result -> Audit/Evidence`

## Object model

- Workflow: user or system task.
- Pipeline: ordered steps used by a workflow.
- Capability: registered atomic operation.
- Connector: bounded source/sink integration such as Gmail, WhatsApp, Telegram, Slack, GitHub, Calendar, Contacts, Files, Nodes.
- Executor: server-side registered implementation of a capability.
- Source: trusted reference identified by `source_id`; arbitrary user paths are not executable inputs.
- Run: immutable execution instance with inputs, policy result, result and audit references.

## Library lifecycle

`FOUND -> NORMALIZED -> DEDUPLICATED -> CLASSIFIED -> VALIDATED -> LIBRARY`

A library item does not become executable merely by being imported.

Promotion path:

`LIBRARY -> TEMPLATE -> AI_PROPOSED/USER_SELECTED -> POLICY_VALIDATED -> APPROVAL_REQUIRED? -> RUNNABLE`

## Safety invariants

- `CHAT_FOUND != RUNNABLE`
- `GITHUB_FOUND != RUNNABLE`
- `EXAMPLE != EXECUTABLE`
- unknown capability => BLOCKED
- unknown executor => BLOCKED
- unknown runtime => BLOCKED
- malformed input => BLOCKED
- AI direct execution => BLOCKED
- arbitrary shell generation/execution => BLOCKED
- browser-selected executor/runtime => BLOCKED
- risk downgrade => BLOCKED
- L2/L3 approval bypass => BLOCKED
- no force push
- no merge without explicit approval
- no deploy without explicit approval
- production port 4013 remains unchanged during development/acceptance
- development acceptance target is 4015 unless a later explicit contract changes it

## Communication capability model

Shared communication capabilities are channel-neutral where possible:

- `communication.search`
- `communication.read`
- `communication.thread.load`
- `communication.attachment.extract`
- `communication.classify`
- `communication.summarize`
- `communication.entities.extract`
- `communication.reply.draft`
- `communication.forward.draft`
- `communication.send`
- `communication.post`

Connector bindings may include Gmail, WhatsApp, Telegram, Slack and GitHub. Read/analyze/draft operations remain separated from external writes. Send/post/reply operations require the applicable external-write policy and approval.

## Generic dynamic-input model

Workflow definitions expose an `input_contract`. The app renders the corresponding selector:

- document workflow -> file/source picker
- repository workflow -> repository picker
- communication workflow -> message/thread picker
- infrastructure workflow -> node picker

The UI submits references such as `source_id`, `repository_ref`, `thread_ref` or `node_ref`. It must not submit an arbitrary command or arbitrary executor path.

## Existing workflows and pipelines

Existing ShadowOps workflows and pipelines are migrated, not replaced. Historical variants are retained through provenance and deduplicated into canonical workflow/template families.

The initial migration inventory is stored in `workflow_library/catalog/chat_history_inventory.yaml`.

## 1000+ example library

Large external/example sets are accepted as reference material only. Import pipeline:

`1000+ examples -> parse -> provenance -> normalize -> deduplicate -> template families -> capability mapping -> policy validation`

No imported example receives execution rights automatically.

## Acceptance target

- existing workflows preserved
- existing pipelines preserved
- all migrated entries typed
- provenance retained
- duplicate families identified
- communication connectors modeled separately from semantic workflow intent
- AI planner emits structured proposals only
- execution remains controlled by registered capabilities, policy, approval and audit
