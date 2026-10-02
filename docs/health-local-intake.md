# ShadowOps Health Local Intake

Purpose: connect health, dental and insurer documents to ShadowOps without committing raw medical data or personal identifiers to GitHub.

## Trust boundary

- Raw PDFs/images remain local only.
- Do not commit patient names, addresses, insurance numbers, document text or attachments.
- Import only a sanitized manifest with operational metadata.
- Canonical events use `privacy=local_only` and `source=health_local`.
- Local generated state is ignored by Git via `priv/health/`, `health*.json`, `medical*.json` and `dental*.json`.

## Supported event types

- `health.document_ingested`
- `health.coverage_decision_recorded`
- `health.claim_requirements_updated`

## Supported manifest metadata

The importer whitelists only:

- `document_kind`
- `document_date`
- `provider_category`
- `payer_category`
- `status`
- `currency`
- `estimated_total`
- `approved_amount`
- `statutory_amount`
- `supplementary_amount`
- `expected_self_pay`
- `claim_documents_required`
- `treatment_area`
- `treatment_year`

All other fields are dropped before persistence.

## Import

From the repository root:

```bash
mix shadowops.health.import /absolute/path/to/shadowops_health_import.json
```

Default local store:

```text
priv/health/events.jsonl
```

Override the store path with:

```bash
export SHADOWOPS_HEALTH_STORE="$HOME/.local/state/shadowops/health/events.jsonl"
```

The command must end with:

```text
HEALTH_IMPORT=OK
PRIVACY=LOCAL_ONLY
```

## Security requirement

Never place the source PDFs or an identifying manifest under a tracked repository path. The Git repository contains connector logic only; medical evidence stays on the local encrypted host/storage boundary.
