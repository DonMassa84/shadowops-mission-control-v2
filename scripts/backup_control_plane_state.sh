#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${SHADOWOPS_STATE_DIR:-$HOME/.local/share/shadowops/state}"
BACKUP_ROOT="${SHADOWOPS_STATE_BACKUP_ROOT:-$HOME/.local/share/shadowops/backups/control-plane}"
RETENTION="${SHADOWOPS_STATE_BACKUP_RETENTION:-7}"

mkdir -p "$STATE_DIR" "$BACKUP_ROOT"
chmod 700 "$STATE_DIR" "$BACKUP_ROOT"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$BACKUP_ROOT/shadowops-state-$timestamp.tar.gz"
manifest="$archive.sha256"

files=()
for name in approvals.jsonl audit.jsonl runs.jsonl; do
  if [[ -f "$STATE_DIR/$name" ]]; then
    files+=("$name")
  fi
done

if (( ${#files[@]} == 0 )); then
  echo "STATE_BACKUP=SKIP reason=no_state_files"
  exit 0
fi

for name in "${files[@]}"; do
  python3 - "$STATE_DIR/$name" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
    if line.strip():
        try:
            json.loads(line)
        except Exception as exc:
            raise SystemExit(f'invalid_jsonl file={path.name} line={number}: {exc}')
PY
done

tar -C "$STATE_DIR" -czf "$archive.tmp" "${files[@]}"
mv "$archive.tmp" "$archive"
chmod 600 "$archive"
sha256sum "$archive" > "$manifest"
chmod 600 "$manifest"

tar -tzf "$archive" >/dev/null
sha256sum -c "$manifest" >/dev/null

mapfile -t old < <(
  find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'shadowops-state-*.tar.gz' -printf '%T@ %p\n' |
    sort -nr |
    tail -n +$((RETENTION + 1)) |
    cut -d' ' -f2-
)

for old_archive in "${old[@]:-}"; do
  [[ -n "$old_archive" ]] || continue
  rm -f -- "$old_archive" "$old_archive.sha256"
done

printf 'STATE_BACKUP=PASS archive=%s files=%d retention=%s\n' "$archive" "${#files[@]}" "$RETENTION"
