#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${PORT:-14014}"
BASE="http://127.0.0.1:${PORT}"

echo "FORMAT=CHECKING"
mix format --check-formatted
echo "FORMAT=PASS"

echo "COMPILE=CHECKING"
mix compile --warnings-as-errors
echo "COMPILE=PASS"

echo "TESTS=CHECKING"
mix test
echo "TESTS=PASS"

echo "=== ROUTES ==="
mix phx.routes | grep -E '/mission|/display/i7|/api/integrations' || true

echo "=== HTTP ==="
for route in \
  /mission \
  /mission/projects \
  /mission/career \
  /mission/ihk \
  /mission/infrastructure \
  /mission/display \
  /mission/display/control
do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE}${route}" || true)"
  echo "${route}=${code}"
done

echo "=== SECRET LEAK SCAN ==="
if rg -n \
  'ghp_[A-Za-z0-9]+|github_pat_|AIza[0-9A-Za-z_-]+|-----BEGIN .*PRIVATE KEY-----' \
  . \
  -g '!deps/**' \
  -g '!_build/**' \
  -g '!node_modules/**'
then
  echo "SECRET_LEAK_SCAN=FAIL"
  exit 1
else
  echo "SECRET_LEAK_SCAN=PASS"
fi

echo "FINAL_STATUS=LOCAL_ACCEPTANCE_COMPLETE"
