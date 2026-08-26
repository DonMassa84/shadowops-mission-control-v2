#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${SHADOWOPS_BASE_URL:-http://127.0.0.1:4013}"
READ_TOKEN="${SHADOWOPS_READ_TOKEN:?SHADOWOPS_READ_TOKEN is required}"

http_code() {
  local path="$1"
  curl -sS --max-time 8 \
    -H "Authorization: Bearer $READ_TOKEN" \
    -o /dev/null -w '%{http_code}' "$BASE_URL$path" 2>/dev/null || printf '000'
}

require_http() {
  local path="$1"
  local expected="$2"
  local code
  code="$(http_code "$path")"

  if [[ "$code" != "$expected" ]]; then
    printf 'FAIL %-30s HTTP=%s expected=%s\n' "$path" "$code" "$expected" >&2
    return 1
  fi

  printf 'PASS %-30s HTTP=%s\n' "$path" "$code"
}

runtime_location() {
  curl -sS --max-time 8 \
    -H "Authorization: Bearer $READ_TOKEN" \
    -D - -o /dev/null "$BASE_URL/runtime" \
    | awk 'BEGIN { IGNORECASE=1 } /^location:/ { gsub("\r", "", $2); print $2; exit }'
}

printf '=== SHADOWOPS PRODUCTION RUNTIME SMOKE ===\n'
printf 'BASE_URL=%s\n' "$BASE_URL"

require_http /health 200
require_http /ready 200
require_http / 200
require_http /layers 200
require_http /api/layers 200
require_http /projects/federated 200
require_http /projects/chatgpt 200
require_http /api/projects 200
require_http /nodes 200
require_http /api/nodes 200
require_http /workflows 200
require_http /api/workflows 200
require_http /jobs 200
require_http /runtime 302

runtime_path="$(runtime_location)"
if [[ "$runtime_path" != /runtime/* ]]; then
  printf 'FAIL %-30s redirect=%s\n' '/runtime' "$runtime_path" >&2
  exit 1
fi
require_http "$runtime_path" 200

require_http /security 200
require_http /api/security/status 200
require_http /audit 200
require_http /api/audit/verify 200

projects_payload="$(curl -fsS --max-time 8 -H "Authorization: Bearer $READ_TOKEN" "$BASE_URL/api/projects")"

printf '%s' "$projects_payload" | python3 -c '
import json, sys
payload=json.load(sys.stdin)
projects=payload.get("projects", [])
assert payload.get("counts", {}).get("total", 0) >= 19, payload
assert len(projects) >= 19, len(projects)
assert len({item.get("id") for item in projects}) == len(projects)
chatgpt=next(item for item in projects if item.get("id") == "chatgpt:local-project")
assert chatgpt.get("synthetic") is False, chatgpt
if chatgpt.get("status") == "READY":
    assert chatgpt.get("real_data") is True, chatgpt
    assert chatgpt.get("reachable") is True, chatgpt
else:
    assert chatgpt.get("status") in {"DISCOVERED", "NOT_CONFIGURED", "DEGRADED", "UNAVAILABLE"}, chatgpt
'

health_payload="$(curl -fsS --max-time 8 -H "Authorization: Bearer $READ_TOKEN" "$BASE_URL/health")"
ready_payload="$(curl -fsS --max-time 8 -H "Authorization: Bearer $READ_TOKEN" "$BASE_URL/ready")"

printf '%s' "$health_payload" | python3 -c '
import json, sys
payload=json.load(sys.stdin)
status=str(payload.get("status", "")).upper()
assert status in {"OK", "READY", "HEALTHY"}, payload
'

printf '%s' "$ready_payload" | python3 -c '
import json, sys
payload=json.load(sys.stdin)
status=str(payload.get("status", "")).upper()
assert status in {"OK", "READY", "HEALTHY"}, payload
'

echo 'HEALTH_PAYLOAD=PASS'
echo 'READINESS_PAYLOAD=PASS'
echo 'PROJECT_CATALOG_SEED=PASS'
echo 'FINAL_STATUS=RUNTIME_SMOKE_PASS'
