# ChatGPT Project integration

ShadowOps treats ChatGPT Project state as private local evidence. The repository does not claim direct access to ChatGPT conversations or project data and does not store credentials or raw conversation bodies.

## Project-domain manifest

Default path:

`~/.local/share/shadowops/domains/chatgpt.json`

Override with:

`SHADOWOPS_CHATGPT_MANIFEST=/absolute/path/chatgpt.json`

Supported normalized fields:

```json
{
  "status": "READY",
  "health": "HEALTHY",
  "summary": "Normalized project state",
  "open_items": 3,
  "next_deadline": null,
  "updated_at": "2026-08-25T00:00:00Z",
  "classification": "PRIVATE_LOCAL"
}
```

A missing manifest is reported as `NOT_CONFIGURED`. ShadowOps never promotes a missing project source to READY.

## Import evidence

Default path:

`~/.local/share/shadowops/imports/chatgpt_project.json`

This file is optional evidence produced by an external, user-controlled export or synchronization process. ShadowOps reads it but does not perform direct provider writes.

Example normalized envelope:

```json
{
  "status": "READY",
  "health": "HEALTHY",
  "adapter": "local_chatgpt_project_export",
  "last_sync": "2026-08-25T00:00:00Z",
  "record_count": 12,
  "real_data": true,
  "synthetic": false,
  "reachable": true
}
```

Do not place access tokens, cookies, authorization headers, raw conversation bodies, or other secrets in either manifest.

## UI

The project is visible at:

`/projects/chatgpt`

It also appears in the project overview and source inventory. Until real local evidence exists it remains fail-visible as `NOT_CONFIGURED` / `UNAVAILABLE`.
