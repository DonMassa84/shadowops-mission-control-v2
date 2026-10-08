# ShadowOps Runtime MCP

## Purpose

Expose the existing ShadowOps Phoenix read API to MCP clients without creating a second control plane.

The gateway is deliberately read-only. It wraps only existing GET endpoints and does not expose workflow execution, node/service actions, approval decisions or any other mutation route.

## Architecture

```text
OpenCode / MCP client
        |
        | stdio (default)
        v
ShadowOps Runtime MCP gateway
        |
        | HTTP GET only
        v
127.0.0.1:14014/api/*
        |
        v
ShadowOps Phoenix runtime
```

For a future remote ChatGPT connection, the same gateway can use Streamable HTTP on loopback and be published only through an authenticated secure tunnel:

```text
ChatGPT
   |
secure authenticated tunnel
   |
127.0.0.1:8765/mcp
   |
ShadowOps Runtime MCP gateway
   |
127.0.0.1:14014/api/*
```

Do not expose port 8765 directly to the public Internet.

## Exposed MCP tools

### `shadowops_status`

Views:

- `health`
- `ready`
- `system_overview`
- `integrations`
- `agents`
- `ai_status`
- `ai_models`
- `security`
- `audit_verify`
- `knowledge`

### `shadowops_list`

Collections:

- `workflows`
- `runs`
- `nodes`
- `services`
- `logs`
- `approvals`

### `shadowops_get`

Detail views:

- `workflow`
- `run`
- `node`
- `service`
- `approval`

### `shadowops_snapshot`

Returns a compact combination of health, readiness, system overview and security status.

## Security properties

- Only allowlisted `/api/*` GET paths are constructed.
- Known write/action suffixes are rejected again in the gateway.
- Detail identifiers are URL-encoded before entering paths.
- The Phoenix write routes are not represented as MCP tools.
- The upstream defaults to `127.0.0.1` and remote upstream hosts fail closed.
- Streamable HTTP defaults to a loopback bind and refuses non-loopback binding unless explicitly overridden.
- HTTP redirects are disabled.
- Response size and string length are bounded.
- Sensitive JSON keys are recursively redacted.
- Common bearer/token/password patterns in string values are scrubbed.
- `SHADOWOPS_READ_TOKEN` is read only from the process environment and sent as an Authorization header; it is never returned by the gateway.

The Phoenix API already supports an optional read token. If configured there, provide the matching value only in the local environment.

## OpenCode local setup

The repository `opencode.jsonc` starts the gateway through:

```bash
bash scripts/run-shadowops-mcp.sh
```

The launcher prefers `uv` so the PEP 723 dependencies in the gateway script are isolated automatically. If `uv` is unavailable it will use `python3` only when `mcp` and `httpx` are already installed.

Recommended environment:

```bash
cd ~/Projects/shadowops-mission-control-v2
export SHADOWOPS_BASE_URL='http://127.0.0.1:14014'
# Only if the Phoenix read token is configured:
export SHADOWOPS_READ_TOKEN='...'

opencode mcp list
opencode mcp debug shadowops-runtime
```

Then ask OpenCode:

```text
Use the shadowops-runtime MCP server.
Get a runtime snapshot, then list services and workflows.
Read only. Do not perform or propose runtime mutations unless I explicitly ask.
```

## Standalone local verification

With `uv` installed:

```bash
uv run --script ops/mcp/shadowops_runtime_mcp.py
```

The default transport is stdio, so this command is normally launched by an MCP host rather than used interactively.

Run unit tests:

```bash
python3 -m pip install 'mcp>=2,<3' 'httpx>=0.28,<1'
python3 -m unittest discover -s ops/mcp -p 'test_*.py' -v
```

## Streamable HTTP mode for a secure tunnel

```bash
export SHADOWOPS_MCP_TRANSPORT='streamable-http'
export SHADOWOPS_MCP_HOST='127.0.0.1'
export SHADOWOPS_MCP_PORT='8765'
bash scripts/run-shadowops-mcp.sh
```

The MCP endpoint is then available locally at:

```text
http://127.0.0.1:8765/mcp
```

Keep the bind on loopback and put authentication/TLS at the secure tunnel or reverse-proxy boundary before any remote MCP client is allowed to reach it.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `SHADOWOPS_BASE_URL` | `http://127.0.0.1:14014` | Phoenix API base URL |
| `SHADOWOPS_READ_TOKEN` | unset | Optional Phoenix read bearer token |
| `SHADOWOPS_MCP_TIMEOUT_SECONDS` | `5` | Upstream request timeout |
| `SHADOWOPS_MCP_MAX_BYTES` | `524288` | Maximum accepted upstream payload |
| `SHADOWOPS_MCP_MAX_STRING_CHARS` | `16384` | Maximum returned string length |
| `SHADOWOPS_MCP_TRANSPORT` | `stdio` | `stdio` or `streamable-http` |
| `SHADOWOPS_MCP_HOST` | `127.0.0.1` | Streamable HTTP bind host |
| `SHADOWOPS_MCP_PORT` | `8765` | Streamable HTTP port |
| `SHADOWOPS_MCP_ALLOW_REMOTE_UPSTREAM` | unset | Explicit opt-in for a non-loopback Phoenix upstream |
| `SHADOWOPS_MCP_ALLOW_REMOTE_BIND` | unset | Explicit opt-in for non-loopback MCP binding; normally do not use |

## Non-goals

This MCP gateway does not:

- start or stop nodes;
- restart or mutate services;
- run workflows;
- approve or reject approvals;
- write to the ShadowOps runtime;
- publish secrets or raw local runtime state to GitHub;
- make a local MCP endpoint automatically accessible to ChatGPT.

Remote ChatGPT access is a separate deployment/security step and must preserve the same read-only boundary.
