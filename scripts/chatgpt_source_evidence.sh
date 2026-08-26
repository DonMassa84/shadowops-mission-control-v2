#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${SHADOWOPS_CHATGPT_EXPORT_DIR:?Set SHADOWOPS_CHATGPT_EXPORT_DIR to a user-controlled ChatGPT export directory}"

if [[ ! -d "$SHADOWOPS_CHATGPT_EXPORT_DIR" ]]; then
  echo "CHATGPT_SOURCE_GATE=FAIL"
  echo "ERROR=EXPORT_DIR_NOT_FOUND"
  exit 2
fi

case "$SHADOWOPS_CHATGPT_EXPORT_DIR" in
  "$ROOT"|"$ROOT"/*)
    echo "CHATGPT_SOURCE_GATE=FAIL"
    echo "ERROR=EXPORT_MUST_NOT_BE_INSIDE_REPOSITORY"
    exit 3
    ;;
esac

export MIX_ENV="${MIX_ENV:-prod}"

mix shadowops.chatgpt.catalog

CATALOG="${SHADOWOPS_PROJECT_CATALOG:-$HOME/.local/state/shadowops/project_catalog.json}"
DOMAIN="${SHADOWOPS_CHATGPT_MANIFEST:-$HOME/.local/share/shadowops/domains/chatgpt.json}"
IMPORT_ROOT="${SHADOWOPS_IMPORT_DIR:-$HOME/.local/share/shadowops/imports}"
IMPORT="$IMPORT_ROOT/chatgpt_project.json"

for path in "$CATALOG" "$DOMAIN" "$IMPORT"; do
  if [[ ! -s "$path" ]]; then
    echo "CHATGPT_SOURCE_GATE=FAIL"
    echo "ERROR=EXPECTED_EVIDENCE_MISSING"
    echo "PATH=$path"
    exit 4
  fi
done

elixir -e '
  paths = System.argv()
  Enum.each(paths, fn path ->
    body = File.read!(path)
    case Jason.decode(body) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "invalid evidence JSON #{path}: #{Exception.message(reason)}"
    end
  end)
' "$CATALOG" "$DOMAIN" "$IMPORT"

if command -v rg >/dev/null 2>&1; then
  if rg -n -i 'authorization|bearer|cookie|refresh[_-]?token|access[_-]?token|client[_-]?secret|private raw message' \
    "$CATALOG" "$DOMAIN" "$IMPORT" >/tmp/shadowops-chatgpt-sensitive-scan.txt; then
    echo "CHATGPT_SOURCE_GATE=FAIL"
    echo "ERROR=SENSITIVE_MATERIAL_IN_NORMALIZED_EVIDENCE"
    cat /tmp/shadowops-chatgpt-sensitive-scan.txt
    exit 5
  fi
fi

printf '%s\n' \
  "CHATGPT_SOURCE_GATE=PASS" \
  "CATALOG=$CATALOG" \
  "DOMAIN=$DOMAIN" \
  "IMPORT=$IMPORT" \
  "NEXT=verify authenticated /api/projects and /projects/chatgpt on the existing runtime"
