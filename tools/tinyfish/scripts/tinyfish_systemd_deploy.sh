#!/usr/bin/env bash
set -euo pipefail

# TinyFish Systemd Deploy Script
# Usage: tinyfish_systemd_deploy.sh <monitor_id> [--user|--system]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_ID="$1"
SCOPE="${2:-user}"

if [[ -z "$MONITOR_ID" ]]; then
  echo "Usage: $0 <monitor_id> [--user|--system]" >&2
  exit 1
fi

MONITORS_DIR="${SCRIPT_DIR}/../monitors"
MONITOR_FILE="${MONITORS_DIR}/${MONITOR_ID}.json"
SYSTEMD_DIR="${SCRIPT_DIR}/../systemd"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

if [[ ! -f "$MONITOR_FILE" ]]; then
  echo "Monitor definition not found: $MONITOR_FILE" >&2
  exit 1
fi

SCHEDULE=$(jq -r '.schedule_cron' "$MONITOR_FILE")
if [[ -z "$SCHEDULE" || "$SCHEDULE" == "null" ]]; then
  echo "No schedule_cron defined in monitor" >&2
  exit 1
fi

# Convert cron to systemd OnCalendar format
# This is a simplified conversion - for production use a proper cron->systemd converter
CRON_TO_ONCALENDAR() {
  local cron="$1"
  # Basic conversion for common patterns
  # minute hour day month weekday
  read -r min hour day month weekday <<< "$cron"
  
  # Handle */n patterns
  if [[ "$min" == *"*/"* ]]; then
    local interval="${min#*/}"
    echo "*-*-* *:00/${interval}:00"
  elif [[ "$hour" == *"*/"* ]]; then
    local interval="${hour#*/}"
    echo "*-*-* *:${min}/${interval}:00"
  elif [[ "$min" != "*" && "$hour" != "*" ]]; then
    printf "*-*-* %02d:%02d:00" "$hour" "$min"
  elif [[ "$hour" != "*" ]]; then
    printf "*-*-* %02d:00:00" "$hour"
  else
    echo "*-*-* *:*:00"
  fi
}

ONCALENDAR=$(CRON_TO_ONCALENDAR "$SCHEDULE")

echo "Deploying monitor $MONITOR_ID as systemd ${SCOPE} service/timer"
echo "Schedule: $SCHEDULE -> OnCalendar: $ONCALENDAR"

mkdir -p "$SYSTEMD_USER_DIR"

# Generate service file
SERVICE_FILE="${SYSTEMD_USER_DIR}/tinyfish-monitor-${MONITOR_ID}.service"
cat > "$SERVICE_FILE" <<SVC_EOF
[Unit]
Description=TinyFish Monitor: ${MONITOR_ID}
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
Type=oneshot
EnvironmentFile=-%h/.config/shadowops/tinyfish/env
Environment=HOME=%h
Environment=USER=%u
WorkingDirectory=%h/Projects/shadowops-mission-control-v2
ExecStart=%h/Projects/shadowops-mission-control-v2/tools/tinyfish/scripts/tinyfish_monitor_run.sh ${MONITOR_ID}
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tinyfish-monitor-${MONITOR_ID}

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.local/state/shadowops/tinyfish %h/.cache/shadowops/tinyfish

[Install]
WantedBy=default.target
SVC_EOF

# Generate timer file
TIMER_FILE="${SYSTEMD_USER_DIR}/tinyfish-monitor-${MONITOR_ID}.timer"
cat > "$TIMER_FILE" <<TMR_EOF
[Unit]
Description=TinyFish Monitor Timer: ${MONITOR_ID}
Requires=tinyfish-monitor-${MONITOR_ID}.service

[Timer]
OnCalendar=${ONCALENDAR}
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
TMR_EOF

echo "Created: $SERVICE_FILE"
echo "Created: $TIMER_FILE"

# Reload and enable
if [[ "$SCOPE" == "user" ]]; then
  systemctl --user daemon-reload
  systemctl --user enable --now "tinyfish-monitor-${MONITOR_ID}.timer"
  echo "Enabled and started timer: tinyfish-monitor-${MONITOR_ID}.timer"
else
  sudo systemctl daemon-reload
  sudo systemctl enable --now "tinyfish-monitor-${MONITOR_ID}.timer"
  echo "Enabled and started system timer: tinyfish-monitor-${MONITOR_ID}.timer"
fi
