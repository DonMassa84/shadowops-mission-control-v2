# Mission Control V2 — automatic imports and secret contract

## Purpose

Mission Control V2 projects external applications into one privacy-safe dashboard without committing private records or secret values to GitHub.

## Import boundary

Connector processes write bounded JSON evidence files to:

`$SHADOWOPS_IMPORT_DIR/<source>.json`

Default:

`~/.local/share/shadowops/imports/<source>.json`

Supported source IDs initially:

- gmail
- calendar
- drive
- github
- whatsapp
- telegram
- obsidian
- finance
- i7

The dashboard reads only normalized evidence fields such as status, health, adapter, last_sync, record_count, real_data, reachable, error_code and error_message. Raw messages, documents, transactions, contacts, tokens and credentials must not be written into these evidence files.

## Secret boundary

SourceRegistry stores only the *names* of required environment bindings. It never returns the values.

Examples:

- GMAIL_CLIENT_ID
- GMAIL_CLIENT_SECRET
- GMAIL_REFRESH_TOKEN
- GOOGLE_CLIENT_ID
- GOOGLE_CLIENT_SECRET
- GOOGLE_REFRESH_TOKEN
- GITHUB_TOKEN
- TELEGRAM_BOT_TOKEN

Dashboard states are limited to `CONFIGURED`, `MISSING` or `NOT_REQUIRED`.

Secret values belong in the local service environment / secret store or GitHub Actions Secrets when a CI workflow requires them. They must never be committed, rendered, logged or copied into domain manifests.

## Example import evidence

```json
{
  "status": "READY",
  "health": "HEALTHY",
  "adapter": "github_connector_v1",
  "last_sync": "2026-08-24T21:00:00Z",
  "record_count": 42,
  "real_data": true,
  "synthetic": false,
  "reachable": true
}
```

## Project-domain boundary

Normalized project summaries remain under:

`~/.local/share/shadowops/domains/*.json`

Mission Control V2 supports ShadowOps, Infrastructure, Career, Finance, Investigations, Legal, IHK / Zero Trust, Community, Social, Knowledge, Housing, Administration, Health, Learning and Personal Framework.

## Fail-visible rules

- missing import evidence => `NOT_CONFIGURED`
- invalid JSON => `NOT_CONFIGURED / INVALID_JSON`
- unreadable evidence => `NOT_CONFIGURED / IMPORT_UNREADABLE`
- missing secret binding => `MISSING`
- no source-backed evidence may be promoted to READY
- synthetic data may never be presented as real data

## Production acceptance

Before release:

1. `mix format --check-formatted`
2. `MIX_ENV=test mix compile --warnings-as-errors`
3. `MIX_ENV=test mix test`
4. `/health` returns OK
5. `/ready` returns READY
6. `/` renders Project overview and Automatic imports
7. `/projects` renders all configured domains
8. `/api/integrations` includes import-scope records
9. a configured secret name is visible only as a binding status; its value is absent from HTML, API responses and logs
10. missing sources remain fail-visible
