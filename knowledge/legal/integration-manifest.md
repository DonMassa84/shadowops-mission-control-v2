# Legal Integration Manifest

Status: INTEGRATED_ON_BRANCH

## Connected surfaces

- [x] Redacted registry
- [x] Mission Control UI `/legal`
- [x] Read API `/api/legal`
- [x] System overview projection
- [x] Existing read-security pipeline
- [x] Evidence boundary documented
- [x] Audit/approval requirements documented for future writes
- [x] GitHub redacted metadata boundary
- [x] Local private evidence boundary
- [x] Obsidian redacted mirror contract
- [x] Route/privacy test

## Explicitly not enabled

- No legal write API
- No automatic bank/payment mutation
- No raw lawyer email ingestion into public Git
- No raw USB/case evidence publishing
- No absolute filesystem path exposure

## Gate

Merge only after local `mix test` / CI is green and privacy scans remain PASS.
