# PDF Governance — Real Local Source Evidence

**Source:** `pdf_governance`
**Adapter:** `ShadowOpsCore.OperationalSources.pdf_governance/0` (+ `pdf_governance_at/2`)
**Branch:** `integration/real-local-governance-sources-2026-08-27`
**Date:** 2026-08-27
**Scope:** read / status / evidence source. No raw PDF content is ever exposed.

## Source location

- Canonical base: `/home/schattenmacher/openclaw_training` (symlink → `/mnt/nvme-data/openclaw_training`)
- PDF source root: `/mnt/nvme-data/openclaw_training/workflows`
- Reachable check: base root exists and is a directory; source root exists. `reachable=true`

## Status JSON

- Path: `data/workflow_status/pdf_governance_status.json`
- Parses: yes (source of the counts below)

## Artifacts (5/5 present) + SHA256

```text
PDF_GOVERNANCE_REPORT.md            44c0179011d813d5a5a5e7846e9c372eb1a26ef761a4979fd94ca1a21527292b
PDF_DISTRIBUTION_BOARD.md           a6da568d67ec09fcfb3787811b2afc9634887bda72bd552c926375cfc7bee50b
pdf_inventory.jsonl                 afc53b94ede898a0540312c2c97194749bfc0fe15eefd825051c4886b5abd718
pdf_inventory.csv                   15517a24b74346724429a3483711b181b6602f84a249fad3b91a0ae780ac0687
pdf_discord_distribution_plan.json  a6de4ff013a781c97e6df90a8cdb7ba95f01020c58fde65223bfdfef1b3e7ede
```

## Counts

```text
PDF_TOTAL=2756
TEXT_EXTRACTED=2174
RECORD_COUNT=2756   (JSONL records)
artifact_count=5 / artifact_required=5
```

Priority: `P2=1493, P3=1263`
Categories: `career=266, docs-archive=383, finance=555, housing=255, ihk=928, memory=10, openclaw=325, security=34`

## Readiness evidence

```text
status=READY
real_data=true
synthetic=false
reachable=true
record_count=2756 (>0)
missing_artifacts=[]
```

## Privacy / non-exposure

- The connector reports path basenames, counts, hashes and status fields only.
- It never reads or prints raw PDF binary content (`%PDF` bytes), and never
  includes the PDF document body, metadata or secret values in its output.
- A regression test asserts the connector output carries no raw PDF content.

## Verified commands

```bash
# Elixir probe (production-independent, read-only):
MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix run -e \
  'r = ShadowOpsCore.OperationalSources.pdf_governance(); IO.puts("status=#{r.status} record_count=#{r.record_count} reachable=#{r.reachable}")'
# output: status=READY record_count=2756 reachable=true

# determinist tests (temp sources):
MIX_ENV=test SHADOWOPS_START_PERSISTENCE=false mix test apps/shadowops_core/test/governance_sources_test.exs
# READY / DEGRADED / synthetic-never-READY / no-raw-content all pass
```
