#!/usr/bin/env bash
set -euo pipefail

# TinyFish Monitor Creation Script for ShadowOps
# Uses REST API since CLI doesn't have monitor command
# Usage: tinyfish_monitor_create.sh <monitor_definition.json>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_FILE="$1"

if [[ -z "$MONITOR_FILE" || ! -f "$MONITOR_FILE" ]]; then
  echo "Usage: $0 <monitor_definition.json>" >&2
  exit 1
fi

# Load API key
if [[ -z "${TINYFISH_API_KEY:-}" ]]; then
  if [[ -f ~/.config/shadowops/tinyfish/env ]]; then
    source ~/.config/shadowops/tinyfish/env
  fi
  if [[ -f ~/.config/environment.d/90-shadowmaker-ai.conf ]]; then
    source ~/.config/environment.d/90-shadowmaker-ai.conf
  fi
fi

if [[ -z "${TINYFISH_API_KEY:-}" ]]; then
  echo "TINYFISH_API_KEY not set" >&2
  exit 1
fi

# Validate against schema (optional)
if command -v python3 >/dev/null && python3 -c "import jsonschema, json, sys; schema=json.load(open('${SCRIPT_DIR}/../schemas/monitor.json')); data=json.load(open('$MONITOR_FILE')); jsonschema.validate(data, schema)" 2>/dev/null; then
  echo "✓ Monitor definition validates against schema"
else
  echo "⚠ Schema validation skipped (jsonschema not available) or failed"
fi

MONITOR_ID=$(jq -r '.id' "$MONITOR_FILE")
MONITOR_TYPE=$(jq -r '.type' "$MONITOR_FILE")
SCHEDULE=$(jq -r '.schedule_cron' "$MONITOR_FILE")
ENABLED=$(jq -r '.enabled' "$MONITOR_FILE")
PURPOSE=$(jq -r '.purpose // ""' "$MONITOR_FILE")
WEBHOOK=$(jq -r '.webhook_url // ""' "$MONITOR_FILE")

if [[ "$ENABLED" != "true" ]]; then
  echo "Monitor $MONITOR_ID is disabled, skipping creation"
  exit 0
fi

echo "Creating TinyFish monitor via API: $MONITOR_ID (type: $MONITOR_TYPE)"

# Build API payload
if [[ "$MONITOR_TYPE" == "FETCH" ]]; then
  URL=$(jq -r '.config.url' "$MONITOR_FILE")
  FORMAT=$(jq -r '.config.format // "markdown"' "$MONITOR_FILE")
  LINKS=$(jq -r '.config.links // false' "$MONITOR_FILE")
  IMAGE_LINKS=$(jq -r '.config.image_links // false' "$MONITOR_FILE")
  INCLUDE_SELECTORS=$(jq -c '.config.include_selectors // []' "$MONITOR_FILE")
  EXCLUDE_SELECTORS=$(jq -c '.config.exclude_selectors // []' "$MONITOR_FILE")
  
  PAYLOAD=$(jq -n \
    --arg name "$MONITOR_ID" \
    --arg type "fetch" \
    --arg schedule "$SCHEDULE" \
    --arg purpose "$PURPOSE" \
    --arg url "$URL" \
    --arg format "$FORMAT" \
    --argjson links "$LINKS" \
    --argjson image_links "$IMAGE_LINKS" \
    --argjson include_selectors "$INCLUDE_SELECTORS" \
    --argjson exclude_selectors "$EXCLUDE_SELECTORS" \
    --arg webhook "$WEBHOOK" \
    '{
      name: $name,
      type: $type,
      schedule_cron: $schedule,
      purpose: $purpose,
      config: {
        url: $url,
        format: $format,
        links: $links,
        image_links: $image_links,
        include_selectors: $include_selectors,
        exclude_selectors: $exclude_selectors
      },
      webhook_url: (if $webhook == "" then null else $webhook end)
    }')
    
elif [[ "$MONITOR_TYPE" == "SEARCH" ]]; then
  QUERY=$(jq -r '.config.query' "$MONITOR_FILE")
  RECENCY=$(jq -r '.config.recency_minutes // 1440' "$MONITOR_FILE")
  LIMIT=$(jq -r '.config.result_limit // 10' "$MONITOR_FILE")
  FORMAT=$(jq -r '.config.format // "json"' "$MONITOR_FILE")
  
  PAYLOAD=$(jq -n \
    --arg name "$MONITOR_ID" \
    --arg type "search" \
    --arg schedule "$SCHEDULE" \
    --arg purpose "$PURPOSE" \
    --arg query "$QUERY" \
    --argjson recency "$RECENCY" \
    --argjson limit "$LIMIT" \
    --arg format "$FORMAT" \
    --arg webhook "$WEBHOOK" \
    '{
      name: $name,
      type: $type,
      schedule_cron: $schedule,
      purpose: $purpose,
      config: {
        query: $query,
        recency_minutes: $recency,
        result_limit: $limit,
        format: $format
      },
      webhook_url: (if $webhook == "" then null else $webhook end)
    }')
else
  echo "Unknown monitor type: $MONITOR_TYPE" >&2
  exit 1
fi

# Create monitor via API
API_URL="https://api.search.tinyfish.ai/monitors"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
  -H "X-API-Key: $TINYFISH_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  MONITOR_RESULT=$(echo "$BODY" | jq -r '.id // .monitor_id // "unknown"')
  echo "✓ Monitor $MONITOR_ID created successfully (API ID: $MONITOR_RESULT)"
  
  # Save monitor ID mapping for systemd deployment
  STATE_DIR="${HOME}/.local/state/shadowops/tinyfish/monitors"
  mkdir -p "$STATE_DIR"
  echo "$MONITOR_RESULT" > "$STATE_DIR/${MONITOR_ID}.active"
  echo "$MONITOR_ID" > "$STATE_DIR/${MONITOR_ID}.local_id"
else
  echo "✗ Failed to create monitor $MONITOR_ID (HTTP $HTTP_CODE)" >&2
  echo "$BODY" >&2
  exit 1
fi
