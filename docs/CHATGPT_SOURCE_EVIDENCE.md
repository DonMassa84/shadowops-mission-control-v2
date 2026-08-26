# ChatGPT Source Evidence

## Goal

Prove ChatGPT project availability from a real local export without committing raw conversation content, credentials, or private local paths.

## Trust boundary

- The canonical source remains local.
- GitHub stores only code, tests, schemas, and non-sensitive evidence rules.
- `READY` is allowed only when the local source is reachable, real, non-synthetic, and the normalized record satisfies the existing truthfulness checks.
- Missing or malformed local evidence must remain `NOT_CONFIGURED` / `UNAVAILABLE`.
- Raw ChatGPT messages and attachments are never committed by this workflow.

## Expected local inputs

ShadowOps may ingest a local ChatGPT export directory supplied through `SHADOWOPS_CHATGPT_EXPORT_DIR`. The importer must derive bounded metadata only:

- project id
- project name
- source type `chatgpt_library_project`
- `real_data`
- `synthetic`
- `reachable`
- `content_ingested`
- `integration_mode`

## Acceptance

1. Missing export directory fails closed.
2. Invalid export data fails closed.
3. Valid project metadata normalizes to the federated project catalog.
4. Raw message content is excluded from persisted catalog output.
5. Logical ChatGPT nodes are read-only/status-only.
6. Existing format, compile, tests, and CI remain green.
