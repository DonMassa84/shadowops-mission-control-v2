#!/usr/bin/env bash
set -euo pipefail

# TinyFish Fetch Script for ShadowOps
# Usage: tinyfish_fetch.sh <url> [--format markdown|html|json] [--output rag|file|stdout] [--links] [--image-links]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/config.json"
SCHEMAS_DIR="${SCRIPT_DIR}/../schemas"
WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"
STATE_DIR="${HOME}/.local/state/shadowops/tinyfish"
LOGS_DIR="${STATE_DIR}/logs"

# Defaults
FORMAT="markdown"
OUTPUT="stdout"
LINKS=false
IMAGE_LINKS=false
WORKFLOW_ID=""

# Parse arguments
URLS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --links)
      LINKS=true
      shift
      ;;
    --image-links)
      IMAGE_LINKS=true
      shift
      ;;
    --workflow-id)
      WORKFLOW_ID="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      URLS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "Usage: $0 <url> [--format markdown|html|json] [--output rag|file|stdout] [--links] [--image-links] [--workflow-id ID]" >&2
  exit 1
fi

# Generate workflow ID if not provided
if [[ -z "$WORKFLOW_ID" ]]; then
  WORKFLOW_ID="FETCH_$(date +%s)_$$"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="${LOGS_DIR}/${WORKFLOW_ID}_$(date +%Y%m%d_%H%M%S).jsonl"

mkdir -p "$LOGS_DIR"

# Log start
log_event() {
  local severity="$1"
  local status="$2"
  local title="$3"
  local summary="$4"
  local target="$5"
  local evidence="$6"
  local action_required="$7"
  local metadata="$8"
  
  cat <<EOLOG >> "$LOG_FILE"
{"source":"tinyfish","workflow":"$WORKFLOW_ID","timestamp":"$TIMESTAMP","severity":"$severity","status":"$status","title":"$title","summary":"$summary","target":"$target","evidence":$evidence,"action_required":$action_required,"metadata":$metadata}
EOLOG
}

# Build tinyfish fetch command
TF_CMD=("tinyfish" "fetch" "content" "get" "--format" "$FORMAT")
if [[ "$LINKS" == "true" ]]; then
  TF_CMD+=("--links")
fi
if [[ "$IMAGE_LINKS" == "true" ]]; then
  TF_CMD+=("--image-links")
fi
TF_CMD+=("${URLS[@]}")

# Execute fetch
START_TIME=$(date +%s%3N)
log_event "INFO" "SUCCESS" "Fetch started" "Fetching ${#URLS[@]} URL(s)" "${URLS[0]}" "null" "false" "{}"

if RESULT=$("${TF_CMD[@]}" 2>&1); then
  END_TIME=$(date +%s%3N)
  DURATION=$((END_TIME - START_TIME))
  
  # Parse result for content hash
  CONTENT_HASH=$(echo "$RESULT" | sha256sum | cut -d' ' -f1)
  
  log_event "INFO" "SUCCESS" "Fetch completed" "Successfully fetched ${#URLS[@]} URL(s) in ${DURATION}ms" "${URLS[0]}" "{\"url\":\"${URLS[0]}\",\"content_hash\":\"$CONTENT_HASH\",\"change_detected\":true}" "false" "{\"duration_ms\":$DURATION}"
  
  # Handle output
  case "$OUTPUT" in
    stdout)
      echo "$RESULT"
      ;;
    file)
      OUT_FILE="${STATE_DIR}/fetch_${WORKFLOW_ID}_$(date +%Y%m%d_%H%M%S).${FORMAT}"
      echo "$RESULT" > "$OUT_FILE"
      echo "Saved to $OUT_FILE"
      ;;
    rag)
      # Insert into RAG database (placeholder for actual implementation)
      echo "$RESULT" | jq -c --arg wf "$WORKFLOW_ID" --arg ts "$TIMESTAMP" '{doc_id: $wf, title: "TinyFish Fetch", path: $wf, content: ., timestamp: $ts, curated: true}'
      ;;
    *)
      echo "$RESULT"
      ;;
  esac
else
  END_TIME=$(date +%s%3N)
  DURATION=$((END_TIME - START_TIME))
  log_event "ERROR" "FAILED" "Fetch failed" "Failed to fetch ${URLS[0]}" "${URLS[0]}" "null" "false" "{\"duration_ms\":$DURATION,\"error\":\"$RESULT\"}"
  echo "ERROR: $RESULT" >&2
  exit 1
fi
