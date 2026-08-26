#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "LOCAL_ALL_CONTRACT=FAIL reason=$1" >&2
  exit 1
}

for file in \
  scripts/local_all_developments.sh \
  scripts/certify_all_developments.sh \
  scripts/promote_stable_4013.sh \
  scripts/shadowops-local.sh \
  scripts/shadowops-coder.sh \
  scripts/run-shadowops-mcp.sh
  do
  bash -n "$file" || fail "bash_syntax_${file}"
done

# Development and certification must never claim the stable port.
grep -Fq 'PREVIEW_PORT="${SHADOWOPS_ALL_PREVIEW_PORT:-4014}"' scripts/local_all_developments.sh || fail preview_port_contract
grep -Fq 'SMOKE_PORT="${SHADOWOPS_CERT_SMOKE_PORT:-4015}"' scripts/certify_all_developments.sh || fail smoke_port_contract
grep -Fq '[[ "$PREVIEW_PORT" != "4013" ]]' scripts/local_all_developments.sh || fail preview_4013_guard
grep -Fq 'CERTIFICATION_MUST_NOT_BIND_4013' scripts/certify_all_developments.sh || fail certification_4013_guard

# Stable mutation requires explicit opt-in and a certified artifact.
grep -Fq 'SHADOWOPS_PROMOTE_STABLE:-NO' scripts/promote_stable_4013.sh || fail promotion_opt_in_missing
grep -Fq 'CERTIFICATE_MISSING_RUN_CERTIFY_ALL_DEVELOPMENTS_FIRST' scripts/promote_stable_4013.sh || fail certificate_requirement_missing
grep -Fq 'CERTIFIED_ARTIFACT_SHA256_MISMATCH' scripts/promote_stable_4013.sh || fail artifact_integrity_missing

for gate in CREDO DIALYZER SOBELOW PRODUCTION_HANDOFF MCP_CONTRACT LOCAL_CODER_CONTRACT; do
  grep -Fq "$gate" scripts/certify_all_developments.sh || fail "certification_gate_${gate}_missing"
  grep -Fq "$gate" scripts/promote_stable_4013.sh || fail "promotion_gate_${gate}_missing"
done

# Automatic rollback and prior service snapshot are mandatory.
grep -Fq 'rollback()' scripts/promote_stable_4013.sh || fail rollback_function_missing
grep -Fq 'AUTOMATIC ROLLBACK' scripts/promote_stable_4013.sh || fail rollback_marker_missing
grep -Fq 'service.before.txt' scripts/promote_stable_4013.sh || fail stable_snapshot_missing

# OpenCode must inspect the preview candidate, not the stable production runtime.
grep -Fq '"SHADOWOPS_BASE_URL": "http://127.0.0.1:4014"' opencode.jsonc || fail opencode_not_bound_to_preview

# The local coder itself must remain protected from main/master.
grep -Fq 'BLOCKED_PROTECTED_BRANCH' scripts/shadowops-coder.sh || fail coder_protected_branch_guard_missing

# Do not introduce destructive git history operations into the local promotion path.
if grep -En 'git[[:space:]]+(reset|clean|rebase|merge)[[:space:]]' \
  scripts/local_all_developments.sh scripts/certify_all_developments.sh scripts/promote_stable_4013.sh; then
  fail destructive_git_operation_present
fi

python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path('opencode.jsonc').read_text())
assert cfg['default_agent'] == 'shadowops-coder'
assert 'model' not in cfg
assert 'small_model' not in cfg
assert cfg['mcp']['shadowops-runtime']['type'] == 'local'
assert cfg['mcp']['shadowops-runtime']['environment']['SHADOWOPS_BASE_URL'] == 'http://127.0.0.1:4014'
PY

echo "LOCAL_ALL_CONTRACT=PASS"
