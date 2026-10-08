#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/ops/mcp/shadowops_runtime_mcp.py"

if command -v uv >/dev/null 2>&1; then
  exec uv run --script "$SERVER"
fi

if command -v python3 >/dev/null 2>&1 && python3 -c 'import httpx; import mcp' >/dev/null 2>&1; then
  exec python3 "$SERVER"
fi

cat >&2 <<'EOF'
ShadowOps runtime MCP dependencies are missing.

Preferred setup:
  install uv, then run this script again

Fallback setup:
  python3 -m pip install 'mcp>=2,<3' 'httpx>=0.28,<1'

No runtime service was modified.
EOF
exit 127
