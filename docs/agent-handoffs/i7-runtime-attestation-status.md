# i7 Runtime Attestation / Compute Status

STATUS=IMPLEMENTED_PENDING_VALIDATION
BRANCH=ai/i7-runtime-attestation-worker
BASE_SHA=2872cfcb5fac8fa0f470fd80ea79e5eff1055fbe

Implemented:
- evidence-backed i7 node adapter
- verified `qa`, `repository_change`, `supplementary_compute` activation
- fixed-target bounded SSH executor
- exact-head remote wrapper
- CPU probe / format / compile / target test / full test / QA bundle / diff-check job allowlist
- compute dispatcher through `NodeCapabilityRouter`
- `mix shadowops.i7.compute` operator path
- deterministic safety/evidence tests

Pending:
- repository CI on exact implementation head
- real installation of wrapper on authorized i7
- real CPU probe and remote test execution
- runtime evidence publication

Hard boundaries:
`NO_MERGE`, `NO_DEPLOY`, `NO_FORCE_PUSH`, `NO_MAIN_WRITE`, `NO_4013_MUTATION`, `NO_4014_MUTATION`.
