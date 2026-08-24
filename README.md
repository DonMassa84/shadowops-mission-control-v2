# ShadowOps Mission Control V2

Production-oriented Phoenix/LiveView operations console for ShadowOps.

## Local development

```bash
cd ~/Projects/shadowops-mission-control-v2
PORT=14014 ./scripts/run-local-v2.sh
Open:

http://127.0.0.1:14014/mission
http://127.0.0.1:14014/mission/projects
http://127.0.0.1:14014/mission/career
http://127.0.0.1:14014/mission/ihk
http://127.0.0.1:14014/mission/infrastructure
http://127.0.0.1:14014/mission/display
http://127.0.0.1:14014/mission/display/control
Security

This repository must not contain:

API tokens
SSH private keys
Gmail/Google OAuth secrets
financial raw data
legal raw case data
private message content
local runtime state

Runtime data remains local and is consumed through adapters/manifests.
