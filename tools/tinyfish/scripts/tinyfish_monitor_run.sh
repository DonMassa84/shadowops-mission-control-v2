#!/usr/bin/env bash
set -euo pipefail

MONITOR_NAME="${1:-}"
if [[ -z "$MONITOR_NAME" ]]; then
    echo "Usage: $0 <monitor_name>" >&2
    exit 1
fi

CONFIG_DIR="/home/shadowmaker/Projects/shadowops-mission-control-v2/tools/tinyfish/monitors"
CONFIG_FILE="$CONFIG_DIR/${MONITOR_NAME}.json"
STATE_DIR="/home/shadowmaker/.local/state/shadowops/tinyfish"
CACHE_DIR="/home/shadowmaker/.cache/shadowops/tinyfish"

mkdir -p "$STATE_DIR" "$CACHE_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Monitor config not found: $CONFIG_FILE" >&2
    exit 1
fi

# Load env if exists
if [[ -f "/home/shadowmaker/.config/shadowops/tinyfish/env" ]]; then
    set -a
    source "/home/shadowmaker/.config/shadowops/tinyfish/env"
    set +a
fi

if [[ -z "${TINYFISH_API_KEY:-}" ]]; then
    echo "TINYFISH_API_KEY not set" >&2
    exit 1
fi

# Run the monitor using tinyfish CLI
cd /home/shadowmaker/Projects/shadowops-mission-control-v2
tinyfish run-monitor --config "$CONFIG_FILE" --state-dir "$STATE_DIR" --cache-dir "$CACHE_DIR" 2>&1
