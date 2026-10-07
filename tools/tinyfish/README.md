# TinyFish Integration for ShadowOps

Web Intelligence & Automation Layer for ShadowOps infrastructure.

## Structure

```
tools/tinyfish/
├── config/           # Configuration files
├── workflows/        # Workflow definitions (JSON)
├── monitors/         # Monitor definitions (JSON)
├── profiles/         # Browser profile configs (JSON, not committed)
├── scripts/          # Executable scripts
├── schemas/          # JSON schemas for validation
├── tests/            # Test files
├── systemd/          # systemd service/timer templates
└── README.md         # This file
```

## Runtime Directories (not in repo)

```
~/.local/state/shadowops/tinyfish/
├── logs/              # Structured JSON logs
├── profiles/          # Browser context profiles (cookies, storage)
├── monitors/          # Monitor runtime state
└── workflows/         # Workflow runtime state

~/.cache/shadowops/tinyfish/     # Temporary data

~/.config/shadowops/tinyfish/    # Local config overrides
```

## Quick Start

### 1. Install TinyFish CLI
```bash
npm install -g @tiny-fish/cli
tinyfish auth login --source openclaw
# or set TINYFISH_API_KEY env var
```

### 2. Validate Configuration
```bash
# Check config
cat tools/tinyfish/config/config.json

# Validate workflow
python3 -m jsonschema -i workflows/JOB_MONITOR_DE_STUTTGART.json schemas/workflow.json
```

### 3. Run a Fetch Workflow
```bash
tools/tinyfish/scripts/tinyfish_fetch.sh "https://example.com" --output rag
```

### 4. Create a Monitor
```bash
tools/tinyfish/scripts/tinyfish_monitor_create.sh monitors/JOB_MONITOR_DE_STUTTGART.json
```

### 5. Deploy as systemd Timer
```bash
tools/tinyfish/scripts/tinyfish_systemd_deploy.sh JOB_MONITOR_DE_STUTTGART
```

## Automation Levels

| Level | Name | Use Case | Tool |
|-------|------|----------|------|
| 0 | MANUAL | One-off, high risk | — |
| 1 | FETCH | Read/extract only | `fetch` |
| 2 | MONITOR | Regular checks | `monitor` |
| 3 | WEB_AUTOMATION | Interaction needed | `agent` |
| 4 | PERSISTENT_WORKFLOW | Login + recurring | `profile` + `agent` |

## Security

- **Never commit**: `.env`, cookies, session files, browser profiles, tokens, passwords, private keys, personal documents
- **Use**: Environment variables, secret stores, systemd EnvironmentFile, OS keyring, GitHub Secrets
- **File permissions**: `chmod 600` for local secret files
- **Pre-commit**: Run secret scan before every commit

## Event Format

All workflows emit structured events to ShadowOps event layer:

```json
{
  "source": "tinyfish",
  "workflow": "JOB_MONITOR_DE_STUTTGART",
  "timestamp": "2026-10-07T10:00:00Z",
  "severity": "INFO",
  "status": "SUCCESS",
  "title": "New job postings found",
  "summary": "3 new Python positions in Stuttgart",
  "target": "https://jobs.example.com/search?q=python+stuttgart",
  "evidence": { "change_detected": true, "content_hash": "abc123..." },
  "action_required": false
}
```

## Status Values

- `SUCCESS` - Completed successfully
- `NO_CHANGE` - No meaningful changes detected
- `PARTIAL` - Partial success, some data extracted
- `BLOCKED` - Blocked by error, retry exhausted
- `FAILED` - Execution failed
- `REQUIRES_APPROVAL` - Waiting for human approval

## Retry Strategy

```
Attempt 1 → Error analysis → Attempt 2 → BLOCKED (if fails again)
```

No unbounded retries.

## Integration Points

- **workflow_engine**: Workflow definitions registered as ShadowOps workflows
- **shadowops_core adapters**: gmail_adapter, systemd_adapter, github_actions_adapter
- **systemd**: User services/timers for recurring execution
- **GitHub Actions**: CI validation, deployment
- **Event Bus**: TinyFish events → ShadowOps event layer → Rules/Agents/Notifications

## Development Workflow

1. Create workflow/monitor definition in `workflows/` or `monitors/`
2. Validate against schema
3. Test manually with `tinyfish` CLI
4. Add to `systemd/` if recurring
5. Run tests in `tests/`
6. Security review (SECRETS_IN_REPO=NO, etc.)
7. Commit on feature branch
8. Push and merge after CI passes

## Resource Control

- Max 2 concurrent browser runs
- Minimum monitor interval: 15 minutes
- Batch fetch: max 10 URLs
- Deduplication enabled by default
- Every monitor needs justified frequency

## Monitoring Priorities

1. **P1** - Job Monitoring (Stuttgart, IT, remote)
2. **P2** - GitHub Monitoring (workflow failures, releases, security)
3. **P3** - Technical Documentation Watch
4. **P4** - Price/Availability Monitor
5. **P5** - Portal Status Checks (where permitted)
