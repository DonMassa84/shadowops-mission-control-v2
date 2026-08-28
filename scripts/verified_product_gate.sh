#!/usr/bin/env bash
export VERIFIED_APP_URL="http://127.0.0.1:4015"
export BASE_URL="$VERIFIED_APP_URL"
export URL="$VERIFIED_APP_URL"
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pid4013() {
  ss -ltnp 2>/dev/null |
    sed -n 's/.*127\.0\.0\.1:4013.*pid=\([0-9]\+\).*/\1/p' |
    head -1
}

BEFORE="$(pid4013 || true)"

echo "CANDIDATE_SHA=$(git rev-parse HEAD)"
echo "4013_BEFORE=${BEFORE:-NONE}"

python3 -m unittest discover \
  -s verified_app/tests \
  -v

python3 - <<'PY'
import json
from pathlib import Path

d = json.loads(
    Path("verified_app/data/workflows.json").read_text()
)

w = d["workflows"]

assert len(w) == 16
assert len({x["id"] for x in w}) == 16
assert not any(x.get("execution_verified") for x in w)
assert not any(x.get("start_enabled") for x in w)

print("INVENTORY=PASS")
print("FAIL_CLOSED=PASS")
PY

mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 12345

FREEZE_EXCEPTION=RELEASE_BLOCKER \
  python3 scripts/freeze_gate.py

git diff --check

AFTER="$(pid4013 || true)"

echo "4013_AFTER=${AFTER:-NONE}"

test "${BEFORE:-}" = "${AFTER:-}"

echo "FORMAT=PASS"
echo "COMPILE=PASS"
echo "TESTS=PASS"
echo "TEST_4013_NEW_LISTENER=NO"
echo "4013_UNCHANGED=YES"
echo "PRODUCT_GATE=PASS"
