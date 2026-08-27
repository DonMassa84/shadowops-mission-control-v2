#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_URL="${SHADOWOPS_BASE_URL:-http://127.0.0.1:4013}"
RUNTIME_REQUIRED="${SHADOWOPS_RUNTIME_REQUIRED:-0}"
READ_TOKEN="${SHADOWOPS_READ_TOKEN:-}"

pass=0
fail=0

ok() {
  printf 'PASS %-30s %s\n' "$1" "${2:-}"
  pass=$((pass + 1))
}

bad() {
  printf 'FAIL %-30s %s\n' "$1" "${2:-}"
  fail=$((fail + 1))
}

run_gate() {
  local name="$1"
  shift
  if "$@"; then
    ok "$name"
  else
    bad "$name"
    return 1
  fi
}

http_code() {
  local path="$1"
  if [[ -n "$READ_TOKEN" ]]; then
    curl -sS --max-time 8 -H "Authorization: Bearer $READ_TOKEN" \
      -o /dev/null -w '%{http_code}' "$BASE_URL$path" 2>/dev/null || printf '000'
  else
    curl -sS --max-time 8 -o /dev/null -w '%{http_code}' "$BASE_URL$path" 2>/dev/null || printf '000'
  fi
}

api_get() {
  local path="$1"
  if [[ -n "$READ_TOKEN" ]]; then
    curl -fsS --max-time 8 -H "Authorization: Bearer $READ_TOKEN" "$BASE_URL$path"
  else
    curl -fsS --max-time 8 "$BASE_URL$path"
  fi
}

printf '=== SHADOWOPS PRODUCTION ACCEPTANCE ===\n'
printf 'ROOT=%s\n' "$ROOT"
printf 'BASE_URL=%s\n' "$BASE_URL"

run_gate format mix format --check-formatted
run_gate compile mix compile --warnings-as-errors
run_gate tests env -i \
  HOME="$HOME" \
  USER="${USER:-$(id -un)}" \
  LOGNAME="${USER:-$(id -un)}" \
  PATH="$PATH" \
  LANG="${LANG:-C.UTF-8}" \
  MIX_ENV=test \
  SHADOWOPS_START_PERSISTENCE=false \
  mix test --seed 12345
run_gate registry mix shadowops.registry validate
run_gate prod_compile env MIX_ENV=prod mix compile --warnings-as-errors

mix phx.routes > /tmp/shadowops-routes.txt
if grep -F '/layers' /tmp/shadowops-routes.txt >/dev/null && grep -F '/api/layers' /tmp/shadowops-routes.txt >/dev/null; then
  ok layer_routes
else
  bad layer_routes "browser or API Layer Health route missing"
fi

if grep -E 'POST[[:space:]]+/api/layers([[:space:]/]|$)' /tmp/shadowops-routes.txt >/dev/null; then
  bad layer_api_read_only "mutation route detected"
else
  ok layer_api_read_only
fi

if grep -F '/projects/federated' /tmp/shadowops-routes.txt >/dev/null && grep -F '/api/projects' /tmp/shadowops-routes.txt >/dev/null; then
  ok project_catalog_routes
else
  bad project_catalog_routes "browser or API project catalog route missing"
fi

if grep -E '(POST|PUT|PATCH|DELETE)[[:space:]]+/api/projects([[:space:]/]|$)' /tmp/shadowops-routes.txt >/dev/null; then
  bad project_catalog_read_only "mutation route detected"
else
  ok project_catalog_read_only
fi

if mix hex.audit >/tmp/shadowops-hex-audit.log 2>&1; then
  ok dependency_audit
else
  bad dependency_audit "see /tmp/shadowops-hex-audit.log"
fi

if mix help sobelow >/dev/null 2>&1; then
  if (cd "$ROOT/apps/shadowops_web" && mix sobelow --private --strict --exit high --threshold high) \
    >/tmp/shadowops-sobelow.log 2>&1; then
    ok phoenix_security_scan
  else
    bad phoenix_security_scan "Sobelow high-confidence finding or parse failure; see /tmp/shadowops-sobelow.log"
  fi
else
  bad phoenix_security_scan "Sobelow is required but unavailable"
fi

if grep -RInE --exclude-dir='_build' --exclude-dir='deps' --exclude='*.md' \
  '(FAKE_DATA|fake operational data|hardcoded online|synthetic[[:space:]]*:[[:space:]]*true)' \
  apps config 2>/dev/null | grep -vE 'test|fixture' >/tmp/shadowops-fake-state.log; then
  bad no_fake_state "suspicious production markers found"
else
  ok no_fake_state
fi

if grep -RInE --exclude-dir='_build' --exclude-dir='deps' \
  '(BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{20,})' \
  apps config scripts 2>/dev/null >/tmp/shadowops-secret-scan.log; then
  bad secret_scan "credential-like material found"
else
  ok secret_scan
fi

if api_get /health >/tmp/shadowops-health.json 2>/dev/null; then
  ok runtime_health

  for path in / /layers /projects/federated /projects/chatgpt /ready /settings /workflows /runs /nodes /services /agents /ai /security /approvals /audit /logs /knowledge /career /backups /evidence /legal /social/facebook /social/review /display/i7; do
    code="$(http_code "$path")"
    if [[ "$code" =~ ^(200|204|301|302|307|308)$ ]]; then
      ok "route:$path" "HTTP=$code"
    else
      bad "route:$path" "HTTP=$code"
    fi
  done

  if curl -fsS --max-time 8 "$BASE_URL/settings" | grep -q 'Production Integrations'; then
    ok integration_catalog_ui
  else
    bad integration_catalog_ui
  fi

  if payload="$(api_get /api/layers 2>/dev/null)"; then
    if printf '%s' "$payload" | python3 -c '
import json, sys
p=json.load(sys.stdin)
assert p.get("id") == "layer-health"
assert p.get("synthetic") is False
assert p.get("real_data") is True
assert p.get("total_layers") == 12
layers=p.get("layers", [])
assert len(layers) == 12
for layer in layers:
    if not layer.get("assessed"):
        assert layer.get("state") == "NOT_ASSESSED"
        assert layer.get("score") is None
        assert layer.get("coverage") is None
print(len(layers))
' >/tmp/shadowops-layer-count; then
      ok layer_truthfulness "layers=$(cat /tmp/shadowops-layer-count)"
    else
      bad layer_truthfulness
    fi
  else
    if [[ -n "$READ_TOKEN" ]]; then
      bad layer_api "authorized API request failed"
    else
      printf 'SKIP %-30s %s\n' layer_api 'read token not provided or API protected'
    fi
  fi

  if payload="$(api_get /api/projects 2>/dev/null)"; then
    if printf '%s' "$payload" | python3 -c '
import json, sys
p=json.load(sys.stdin)
assert p.get("synthetic") is False
projects=p.get("projects", [])
for item in projects:
    assert "local_export_path" not in item
    assert "secret" not in item
    if item.get("status") == "READY":
        assert item.get("real_data") is True, (item.get("id"), "positive_without_real_data")
        assert item.get("synthetic") is False, (item.get("id"), "positive_synthetic")
        assert item.get("reachable") is True, (item.get("id"), "positive_unreachable")
print(len(projects))
' >/tmp/shadowops-project-count; then
      ok project_catalog_truthfulness "projects=$(cat /tmp/shadowops-project-count)"
    else
      bad project_catalog_truthfulness
    fi
  else
    if [[ -n "$READ_TOKEN" ]]; then
      bad project_catalog_api "authorized API request failed"
    else
      printf 'SKIP %-30s %s\n' project_catalog_api 'read token not provided or API protected'
    fi
  fi

  if payload="$(api_get /api/connectors 2>/dev/null)"; then
    if printf '%s' "$payload" | python3 -c '
import json, sys
p=json.load(sys.stdin)
records=p.get("records", []) if isinstance(p, dict) else []
positive={"READY","ONLINE","CONNECTED"}
for item in records:
    status=str(item.get("status", ""))
    if status in positive:
        assert item.get("real_data") is True, (item.get("id"), "positive_without_real_data")
        assert item.get("synthetic") is False, (item.get("id"), "positive_synthetic")
        assert item.get("reachable") is True, (item.get("id"), "positive_unreachable")
print(len(records))
' >/tmp/shadowops-connector-count; then
      ok connector_truthfulness "records=$(cat /tmp/shadowops-connector-count)"
    else
      bad connector_truthfulness
    fi
  else
    if [[ -n "$READ_TOKEN" ]]; then
      bad connector_api "authorized API request failed"
    else
      printf 'SKIP %-30s %s\n' connector_api 'read token not provided or API protected'
    fi
  fi

  if api_get /api/audit/verify >/tmp/shadowops-audit.json 2>/dev/null; then
    if python3 - /tmp/shadowops-audit.json <<'PY'
import json, pathlib, sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert p.get('valid') is True or p.get('status') in {'READY','VALID','ok'}
PY
    then
      ok audit_chain
    else
      bad audit_chain
    fi
  else
    if [[ -n "$READ_TOKEN" ]]; then
      bad audit_api
    else
      printf 'SKIP %-30s %s\n' audit_api 'read token not provided or API protected'
    fi
  fi
else
  if [[ "$RUNTIME_REQUIRED" == "1" ]]; then
    bad runtime_health "runtime required but unreachable or unauthorized"
  else
    printf 'SKIP %-30s %s\n' runtime_health 'runtime not required in this execution context'
  fi
fi

printf '\nPASS_COUNT=%d\n' "$pass"
printf 'FAIL_COUNT=%d\n' "$fail"

if (( fail > 0 )); then
  echo 'FINAL_STATUS=PRODUCTION_ACCEPTANCE_FAIL'
  exit 1
fi

echo 'FINAL_STATUS=PRODUCTION_ACCEPTANCE_PASS'
