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

## i7 LLM Worker Node Documentation

This repository includes documentation for the i7 LLM worker node (shadowserver):

- **Architecture**: [docs/architecture/I7_LLM_NODE.md](docs/architecture/I7_LLM_NODE.md)
- **Operations Runbook**: [docs/runbooks/I7_LLM_OPERATIONS.md](docs/runbooks/I7_LLM_OPERATIONS.md)
- **Recovery Report**: [docs/recovery/I7_RECOVERY_2026-10-08.md](docs/recovery/I7_RECOVERY_2026-10-08.md)
- **Runtime Tests**: [docs/testing/I7_RUNTIME_TESTS.md](docs/testing/I7_RUNTIME_TESTS.md)
- **Changelog**: [docs/recovery/I7_CHANGELOG_2026-10-08.md](docs/recovery/I7_CHANGELOG_2026-10-08.md)
- **Machine-Readable Metadata**:
  - Node: [meta/i7-llm-node.json](meta/i7-llm-node.json)
  - Models: [meta/i7-models.json](meta/i7-models.json)
- **Evidence**: [docs/recovery/evidence/i7/](docs/recovery/evidence/i7/)

## Quick Reference

```bash
# Connect to i7
ssh shadowserver-i7

# Check health
ssh shadowserver-i7 'cat /var/lib/shadowmaker-llm/status.json'

# Test Ollama (local)
ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11436/api/tags'

# Test Ollama (tailnet)
curl --max-time 10 http://100.98.17.110:11434/api/tags

# Backend selector
ssh shadowserver-i7 'shadow-llm-select'
```
