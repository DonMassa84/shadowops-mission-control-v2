#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${PORT:-14014}"

echo "=== FORMAT ==="
mix format --check-formatted

echo "=== COMPILE ==="
mix compile --warnings-as-errors

echo "=== TESTS ==="
mix test

echo "=== ROUTES ==="
mix phx.routes | grep -E '/mission|/projects|/career|/display/i7|/api/integrations' || true

echo "=== START ==="
echo "Starting on http://127.0.0.1:${PORT}"
PORT="$PORT" mix phx.server
