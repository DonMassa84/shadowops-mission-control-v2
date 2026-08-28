# ShadowOps Foundation Freeze Baseline

Status: **FROZEN**

> Fundament frozen. Produkt offen.

## Frozen foundation

The following foundation contracts are frozen:

- GitHub delivery pipeline baseline
- fail-closed governance
- Approval / Audit / Privacy / Evidence gates
- workflow lifecycle semantics
- L0-L3 risk model
- L2/L3 approval requirement
- single-use approval
- production port 4013 protection
- importer dedupe/provenance/canonical-ID/dry-run contract
- isolated worker branch/worktree model
- Mission Control / Verified UI base structure

## Product remains open

The following areas remain deliberately open:

- real workflow implementations
- workflow registry contents
- real data sources
- connectors
- execution adapters
- runs and results
- audit presentation
- product bug fixes
- performance improvements
- useful UX improvements

## Freeze exceptions

A frozen foundation area may change only for:

- `REPRODUCIBLE_PRODUCT_BUG`
- `SECURITY_DEFECT`
- `RELEASE_BLOCKER`

Otherwise:

- `FOUNDATION_CHANGE=BLOCKED`
- `NEW_META_GOVERNANCE=BLOCKED`
- `PRODUCT_WORK=ALLOWED`

## Runtime environments

- 4014 = development / preview
- 4015 = ephemeral acceptance
- 4013 = stable production

4013 promotion requires separate explicit approval.

No automatic promotion is permitted.

## Product success criterion

A feature counts as working only when its real chain is proven:

`Workflow → Start → Execution → Result → Run → Audit`

Unknown state must never be represented as READY or VERIFIED.
