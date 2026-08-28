#!/usr/bin/env bash
set -euo pipefail

PORT=4013

listener() {
  ss -ltnp 2>/dev/null | grep ":${PORT} " || true
}

BEFORE="$(listener)"

echo "=== 4013 BEFORE ==="
printf '%s\n' "$BEFORE"

BEFORE_PID="$(
  printf '%s\n' "$BEFORE" |
  sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' |
  head -1
)"

set +e
MIX_ENV=test mix test
TEST_RC=$?
set -e

AFTER="$(listener)"

echo "=== 4013 AFTER ==="
printf '%s\n' "$AFTER"

AFTER_PID="$(
  printf '%s\n' "$AFTER" |
  sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' |
  head -1
)"

TEST_STARTED_4013_LISTENER=NO

if [ -z "$BEFORE_PID" ] && [ -n "$AFTER_PID" ]; then
  TEST_STARTED_4013_LISTENER=YES
fi

if [ -n "$BEFORE_PID" ] &&
   [ -n "$AFTER_PID" ] &&
   [ "$BEFORE_PID" != "$AFTER_PID" ]; then
  TEST_STARTED_4013_LISTENER=YES
fi

echo "TEST_RC=$TEST_RC"
echo "PORT_4013_BEFORE_PID=${BEFORE_PID:-NONE}"
echo "PORT_4013_AFTER_PID=${AFTER_PID:-NONE}"
echo "TEST_STARTED_4013_LISTENER=$TEST_STARTED_4013_LISTENER"

if [ "$TEST_RC" -ne 0 ]; then
  exit "$TEST_RC"
fi

if [ "$TEST_STARTED_4013_LISTENER" != "NO" ]; then
  echo "SAFETY_GATE=FAIL"
  exit 91
fi

echo "SAFETY_GATE=PASS"
