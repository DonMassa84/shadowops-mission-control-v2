#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${SHADOWOPS_SERVICE:-shadowops-phoenix.service}"
STATE_DIR="${SHADOWOPS_STATE_DIR:-$HOME/.local/share/shadowops/state}"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

working_dir="$(systemctl --user show "$SERVICE" -p WorkingDirectory --value 2>/dev/null || true)"

if [[ -z "$working_dir" || ! -d "$working_dir" ]]; then
  echo "STATE_MIGRATION=SKIP reason=no_active_working_directory"
  exit 0
fi

legacy_var="$working_dir/var"
if [[ ! -d "$legacy_var" ]]; then
  echo "STATE_MIGRATION=SKIP reason=no_legacy_var path=$legacy_var"
  exit 0
fi

migrated=0
for name in approvals.jsonl audit.jsonl runs.jsonl; do
  src="$legacy_var/$name"
  dst="$STATE_DIR/$name"

  if [[ -s "$dst" ]]; then
    echo "STATE_FILE=$name action=preserve_existing"
    continue
  fi

  if [[ ! -s "$src" ]]; then
    echo "STATE_FILE=$name action=no_source"
    continue
  fi

  python3 - "$src" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
    if line.strip():
        try:
            json.loads(line)
        except Exception as exc:
            raise SystemExit(f'invalid_jsonl line={number}: {exc}')
PY

  tmp="$dst.tmp.$$"
  install -m 600 "$src" "$tmp"
  mv "$tmp" "$dst"
  sha256sum "$dst" > "$dst.sha256"
  chmod 600 "$dst.sha256"
  migrated=$((migrated + 1))
  echo "STATE_FILE=$name action=migrated"
done

printf 'STATE_MIGRATION=PASS migrated=%d source=%s target=%s\n' "$migrated" "$legacy_var" "$STATE_DIR"
