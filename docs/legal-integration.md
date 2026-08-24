# ShadowOps Legal Integration

## Purpose

Integrate legal case status into ShadowOps without exposing private legal evidence, banking data, full correspondence, payment proofs or original case files through Git or the general control plane.

## Integration map

- Mission Control: `/legal`
- Read API: `/api/legal`
- System overview: `/api/system/overview` includes `legal`
- Evidence: case IDs may be referenced by evidence artifacts; raw legal originals remain outside Git
- Audit: future write operations must record case ID + action only, never raw secret payloads
- Approvals: any future legal write/export workflow must require explicit approval
- Security: read endpoint uses the existing ShadowOps read security pipeline
- Knowledge/GitHub: only redacted operational metadata is committed
- Local private store: canonical original evidence remains under the local private ShadowOps evidence boundary
- Obsidian: redacted status may be mirrored; original evidence must not be placed in a publicly synced vault

## Data classes

### REDACTED_METADATA

Allowed in Git / Mission Control:

- case ID
- case type
- operational status
- dates/deadlines
- redacted amount/status fields when explicitly approved for the registry
- verification state
- evidence references that do not reveal local paths

### LEGAL_PRIVATE

Never exposed through the public repository or general read API:

- IBAN/BIC/account details
- full payment proofs or bank statements
- full lawyer correspondence
- private addresses/telephone numbers
- identity documents
- criminal case originals
- USB evidence content
- unredacted PDFs
- absolute local filesystem paths

## Fail-closed rules

1. Invalid/missing registry => `UNAVAILABLE` / `FAIL_CLOSED`.
2. `private_source` is stripped from API output and replaced with `LOCAL_PRIVATE_STORE`.
3. No legal write endpoint exists in this integration.
4. Future mutation/export workflows must require ShadowOps approvals and Audit events.
5. Git remains a redacted metadata plane, never the canonical legal evidence store.

## Current registry

Source: `priv/legal/cases.json`

The registry is intentionally read-only from Mission Control. Operational updates should first be reconciled against source evidence, then written through a controlled local workflow and only the redacted projection should be committed.
