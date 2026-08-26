#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-4013}"

case "$PORT" in
  ''|*[!0-9]*) echo "PORT must be numeric" >&2; exit 2 ;;
esac

if (( PORT < 1 || PORT > 65535 )); then
  echo "PORT must be between 1 and 65535" >&2
  exit 2
fi

echo "=== DEPENDENCIES ==="
mix deps.get

echo "=== FORMAT ==="
mix format --check-formatted

echo "=== COMPILE ==="
mix compile --warnings-as-errors

echo "=== TESTS ==="
mix test --seed 12345

echo "=== REGISTRY ==="
mix shadowops.registry validate

echo "=== ROUTES ==="
mix phx.routes | grep -E '/projects|/career|/display/i7|/api/integrations|/health|/ready'

echo "=== START ==="
echo "Starting ShadowOps on http://127.0.0.1:${PORT}"
exec env PORT="$PORT" mix phx.server
