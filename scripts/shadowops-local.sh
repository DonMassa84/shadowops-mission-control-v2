#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
ShadowOps local all-developments control

Usage:
  scripts/shadowops-local.sh setup
  scripts/shadowops-local.sh certify
  scripts/shadowops-local.sh promote
  scripts/shadowops-local.sh status
  scripts/shadowops-local.sh coder "task"

Semantics:
  setup    Configure/test the complete development candidate on 127.0.0.1:4014.
  certify  Run full static/security/release gates and smoke the release on 4015.
  promote  Promote the exact certified artifact to stable 4013. Requires
           SHADOWOPS_PROMOTE_STABLE=YES and rolls back automatically on failure.
  status   Show stable/preview services, ports, git state and latest certificate.
  coder    Run the guarded OpenCode ShadowOps coder. AI execution is REMOTE_ONLY;
           local model providers are forbidden by repository policy.
EOF
}

cmd="${1:-}"
case "$cmd" in
  setup)
    exec bash scripts/local_all_developments.sh
    ;;
  certify)
    exec bash scripts/certify_all_developments.sh
    ;;
  promote)
    exec bash scripts/promote_stable_4013.sh
    ;;
  coder)
    shift
    [[ $# -gt 0 ]] || { usage >&2; exit 64; }
    exec bash scripts/shadowops-coder.sh "$@"
    ;;
  status)
    echo "=== GIT ==="
    git status --short --branch
    echo "HEAD=$(git rev-parse HEAD)"
    echo
    echo "=== PORTS ==="
    ss -ltnp 2>/dev/null | grep -E ':(4013|4014|4015)[[:space:]]' || true
    echo
    echo "=== SERVICES ==="
    systemctl --user status shadowops-phoenix.service --no-pager 2>/dev/null || true
    systemctl --user status shadowops-preview.service --no-pager 2>/dev/null || true
    echo
    echo "=== HTTP ==="
    for port in 4013 4014; do
      for endpoint in health ready; do
        code="$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/${endpoint}" 2>/dev/null || true)"
        printf 'PORT_%s_%s_HTTP=%s\n' "$port" "${endpoint^^}" "${code:-000}"
      done
    done
    echo
    echo "=== CERTIFICATION ==="
    cert_dir="${SHADOWOPS_CERT_DIR:-${HOME}/.local/state/shadowops/certified-releases}"
    latest="$(find "$cert_dir" -maxdepth 1 -type f -name '*.env' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
    if [[ -n "$latest" ]]; then
      echo "LATEST_CERT=$latest"
      grep -E '^(BRANCH|HEAD|CERTIFIED_AT|FORMAT|COMPILE|TESTS|CREDO|DIALYZER|SOBELOW|PRODUCTION_HANDOFF)=' "$latest" || true
    else
      echo "LATEST_CERT=NONE"
    fi
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 64
    ;;
esac
