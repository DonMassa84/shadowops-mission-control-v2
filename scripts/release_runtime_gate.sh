#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${PORT:-4013}"
export PORT
export SHADOWOPS_START_PERSISTENCE="${SHADOWOPS_START_PERSISTENCE:-false}"
export SHADOWOPS_SECRET_KEY_BASE="${SHADOWOPS_SECRET_KEY_BASE:-$(openssl rand -hex 64)}"
export SHADOWOPS_READ_TOKEN="${SHADOWOPS_READ_TOKEN:-$(openssl rand -hex 32)}"
export SHADOWOPS_WRITE_TOKEN="${SHADOWOPS_WRITE_TOKEN:-$(openssl rand -hex 32)}"
export SHADOWOPS_STATE_DIR="${SHADOWOPS_STATE_DIR:-${RUNNER_TEMP:-/tmp}/shadowops-state}"
mkdir -p "$SHADOWOPS_STATE_DIR"

RELEASE_BIN="_build/prod/rel/shadowops/bin/shadowops"

cleanup() {
  timeout 10s "$RELEASE_BIN" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -x "$RELEASE_BIN" ]]; then
  echo 'Production release executable is missing' >&2
  exit 1
fi

# `start` is the foreground release command. The CI gate must continue to the
# health probes, so launch the release with the built-in daemon command instead.
timeout 20s "$RELEASE_BIN" daemon

ready=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 \
    -H "Authorization: Bearer $SHADOWOPS_READ_TOKEN" \
    "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" != "1" ]]; then
  echo 'Production release did not become healthy' >&2
  timeout 10s "$RELEASE_BIN" rpc 'IO.inspect(:init.get_status())' || true
  exit 1
fi

echo 'RELEASE_HEALTH=PASS'

timeout 180s env \
  SHADOWOPS_BASE_URL="http://127.0.0.1:${PORT}" \
  SHADOWOPS_READ_TOKEN="$SHADOWOPS_READ_TOKEN" \
  bash scripts/runtime_smoke.sh

echo 'FINAL_STATUS=RELEASE_RUNTIME_GATE_PASS'
