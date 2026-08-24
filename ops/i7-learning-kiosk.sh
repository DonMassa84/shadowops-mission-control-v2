#!/usr/bin/env bash
set -Eeuo pipefail
URL="${SHADOWOPS_LEARNING_URL:-http://127.0.0.1:4000/display/i7}"
for browser in chromium chromium-browser google-chrome google-chrome-stable; do
  command -v "$browser" >/dev/null 2>&1 && exec "$browser" --kiosk --no-first-run --disable-session-crashed-bubble --disable-infobars --autoplay-policy=user-gesture-required "$URL"
done
echo 'No supported Chromium browser found' >&2
exit 2
