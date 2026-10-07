#!/usr/bin/env bash
set -euo pipefail

# TinyFish Monitor Run Script for systemd
# Usage: tinyfish_monitor_run.sh <monitor_id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_ID="$1"

if [[ -z "$MONITOR_ID" ]]; then
  echo "Usage: $0 <monitor_id>" >&2
  exit 1
fi

STATE_DIR="${HOME}/.local/state/shadowops/tinyfish/monitors"
MONITORS_DIR="${SCRIPT_DIR}/../monitors"
MONITOR_FILE="${MONITORS_DIR}/${MONITOR_ID}.json"
ACTIVE_FILE="${STATE_DIR}/${MONITOR_ID}.active"
LOG_FILE="${HOME}/.local/state/shadowops/tinyfish/logs/${MONITOR_ID}_$(date +%Y%m%d_%H%M%S).jsonl"

mkdir -p "$(dirname "$LOG_FILE")"

if [[ ! -f "$MONITOR_FILE" ]]; then
  echo "Monitor definition not found: $MONITOR_FILE" >&2
  exit 1
fi

if [[ ! -f "$ACTIVE_FILE" ]]; then
  echo "Monitor $MONITOR_ID not active (run tinyfish_monitor_create.sh first)" >&2
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORKFLOW_ID="$MONITOR_ID"

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

log_event "INFO" "SUCCESS" "Monitor run started" "Executing monitor $MONITOR_ID" "$MONITOR_ID" "null" "false" "{}"

# Run the monitor via TinyFish CLI
# For now, we'll use search/fetch directly since monitor results need to be polled
# In production, this would use tinyfish monitor run <monitor_id> or check monitor results

MONITOR_TYPE=$(jq -r '.type' "$MONITOR_FILE")
CONFIG=$(jq -c '.config' "$MONITOR_FILE")

START_TIME=$(date +%s%3N)

if [[ "$MONITOR_TYPE" == "SEARCH" ]]; then
  QUERY=$(jq -r '.config.query' "$MONITOR_FILE")
  RECENCY=$(jq -r '.config.recency_minutes // 1440' "$MONITOR_FILE")
  LIMIT=$(jq -r '.config.result_limit // 10' "$MONITOR_FILE")
  
  if RESULT=$(tinyfish search query "$QUERY" --pretty 2>&1); then
    END_TIME=$(date +%s%3N)
    DURATION=$((END_TIME - START_TIME))
    
    # Check for new results (compare with last content hash)
    CONTENT_HASH=$(echo "$RESULT" | sha256sum | cut -d' ' -f1)
    LAST_HASH=$(jq -r '.state.content_hash // ""' "$MONITOR_FILE" 2>/dev/null || echo "")
    
    CHANGE_DETECTED=false
    if [[ "$CONTENT_HASH" != "$LAST_HASH" && -n "$LAST_HASH" ]]; then
      CHANGE_DETECTED=true
    fi
    
    # Update state
    jq --arg hash "$CONTENT_HASH" --arg ts "$TIMESTAMP" '.state.content_hash = $hash | .state.last_seen = $ts | .state.last_success = $ts' "$MONITOR_FILE" > "${MONITOR_FILE}.tmp" && mv "${MONITOR_FILE}.tmp" "$MONITOR_FILE"
    
    if [[ "$CHANGE_DETECTED" == "true" ]]; then
      log_event "INFO" "SUCCESS" "Changes detected" "New results found for monitor $MONITOR_ID" "$MONITOR_ID" "{\"content_hash\":\"$CONTENT_HASH\",\"change_detected\":true}" "false" "{\"duration_ms\":$DURATION}"
      echo "CHANGES_DETECTED: $MONITOR_ID"
    else
      log_event "INFO" "NO_CHANGE" "No changes" "No new results for monitor $MONITOR_ID" "$MONITOR_ID" "{\"content_hash\":\"$CONTENT_HASH\",\"change_detected\":false}" "false" "{\"duration_ms\":$DURATION}"
    fi
  else
    END_TIME=$(date +%s%3N)
    DURATION=$((END_TIME - START_TIME))
    log_event "ERROR" "FAILED" "Monitor failed" "Search failed for $MONITOR_ID" "$MONITOR_ID" "null" "false" "{\"duration_ms\":$DURATION,\"error\":\"$RESULT\"}"
    exit 1
  fi
  
elif [[ "$MONITOR_TYPE" == "FETCH" ]]; then
  URL=$(jq -r '.config.url' "$MONITOR_FILE")
  FORMAT=$(jq -r '.config.format // "markdown"' "$MONITOR_FILE")
  
  if RESULT=$(tinyfish fetch content get --format "$FORMAT" "$URL" 2>&1); then
    END_TIME=$(date +%s%3N)
    DURATION=$((END_TIME - START_TIME))
    
    CONTENT_HASH=$(echo "$RESULT" | sha256sum | cut -d' ' -f1)
    LAST_HASH=$(jq -r '.state.content_hash // ""' "$MONITOR_FILE" 2>/dev/null || echo "")
    
    CHANGE_DETECTED=false
    if [[ "$CONTENT_HASH" != "$LAST_HASH" && -n "$LAST_HASH" ]]; then
      CHANGE_DETECTED=true
    fi
    
    jq --arg hash "$CONTENT_HASH" --arg ts "$TIMESTAMP" '.state.content_hash = $hash | .state.last_seen = $ts | .state.last_success = $ts' "$MONITOR_FILE" > "${MONITOR_FILE}.tmp" && mv "${MONITOR_FILE}.tmp" "$MONITOR_FILE"
    
    if [[ "$CHANGE_DETECTED" == "true" ]]; then
      log_event "INFO" "SUCCESS" "Changes detected" "Content changed for $MONITOR_ID" "$MONITOR_ID" "{\"url\":\"$URL\",\"content_hash\":\"$CONTENT_HASH\",\"change_detected\":true}" "false" "{\"duration_ms\":$DURATION}"
      echo "CHANGES_DETECTED: $MONITOR_ID"
    else
      log_event "INFO" "NO_CHANGE" "No changes" "Content unchanged for $MONITOR_ID" "$MONITOR_ID" "{\"url\":\"$URL\",\"content_hash\":\"$CONTENT_HASH\",\"change_detected\":false}" "false" "{\"duration_ms\":$DURATION}"
    fi
  else
    END_TIME=$(date +%s%3N)
    DURATION=$((END_TIME - START_TIME))
    log_event "ERROR" "FAILED" "Monitor failed" "Fetch failed for $MONITOR_ID" "$MONITOR_ID" "null" "false" "{\"duration_ms\":$DURATION,\"error\":\"$RESULT\"}"
    exit 1
  fi
else
  log_event "ERROR" "FAILED" "Unknown monitor type" "Monitor type $MONITOR_TYPE not supported" "$MONITOR_ID" "null" "false" "{}"
  exit 1
fi
