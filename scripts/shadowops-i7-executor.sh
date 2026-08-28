#!/usr/bin/env bash
set -Eeuo pipefail

JOB="${1:-}"
EXPECTED_SHA="${2:-}"
ROOT="${SHADOWOPS_I7_WORKSPACE:-$HOME/Projects/shadowops-mission-control-v2}"

fail() {
  printf 'I7_EXECUTOR=BLOCKED\nREASON=%s\n' "$1" >&2
  exit "${2:-64}"
}

[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || fail INVALID_EXPECTED_SHA

case "$JOB" in
  cpu_probe|format|compile|target_test|full_test|qa_bundle|diff_check)
    ;;
  *)
    fail JOB_NOT_ALLOWLISTED
    ;;
esac

command -v git >/dev/null 2>&1 || fail GIT_UNAVAILABLE
command -v mix >/dev/null 2>&1 || fail MIX_UNAVAILABLE
[[ -d "$ROOT/.git" ]] || fail WORKSPACE_UNAVAILABLE

ROOT_REAL="$(realpath -e "$ROOT")"
case "$ROOT_REAL" in
  "$HOME"/*) ;;
  *) fail WORKSPACE_OUTSIDE_HOME ;;
esac

HEAD="$(git -C "$ROOT_REAL" rev-parse HEAD 2>/dev/null || true)"
[[ "$HEAD" == "$EXPECTED_SHA" ]] || fail EXACT_HEAD_MISMATCH 42

printf 'I7_EXECUTOR=START\n'
printf 'JOB=%s\n' "$JOB"
printf 'EXPECTED_SHA=%s\n' "$EXPECTED_SHA"
printf 'HEAD=%s\n' "$HEAD"
printf 'HOSTNAME=%s\n' "$(hostname)"
printf 'NPROC=%s\n' "$(nproc)"
printf 'LOADAVG=%s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
printf 'STARTED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "$ROOT_REAL"

run_cpu_probe() {
  python3 - <<'PY'
import hashlib
import os
import time
workers = max(1, os.cpu_count() or 1)
started = time.monotonic()
h = b"shadowops-i7-cpu-probe"
for i in range(250000):
    h = hashlib.sha256(h + (i & 0xffff).to_bytes(2, "little")).digest()
elapsed = time.monotonic() - started
print(f"CPU_PROBE_CPUS={workers}")
print(f"CPU_PROBE_SECONDS={elapsed:.6f}")
print(f"CPU_PROBE_DIGEST={h.hex()}")
PY
}

case "$JOB" in
  cpu_probe)
    run_cpu_probe
    ;;
  format)
    mix format --check-formatted
    ;;
  compile)
    MIX_ENV=test mix compile --warnings-as-errors
    ;;
  target_test)
    MIX_ENV=test mix test \
      apps/shadowops_core/test/node_capability_router_test.exs \
      apps/shadowops_core/test/i7_node_test.exs \
      apps/shadowops_core/test/i7_remote_executor_test.exs \
      --seed 12345
    ;;
  full_test)
    MIX_ENV=test mix test --seed 12345
    ;;
  diff_check)
    git diff --check
    ;;
  qa_bundle)
    mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    MIX_ENV=test mix test --seed 12345
    git diff --check
    ;;
esac

printf 'FINISHED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'I7_EXECUTOR=PASS\n'
printf '4013_MUTATION=NO\n'
printf '4014_MUTATION=NO\n'
