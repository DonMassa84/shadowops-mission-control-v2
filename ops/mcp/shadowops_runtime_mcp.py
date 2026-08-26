#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mcp>=2,<3",
#   "httpx>=0.28,<1",
# ]
# ///
"""Read-only MCP gateway for the local ShadowOps control plane.

The gateway exposes only allowlisted GET endpoints from the existing Phoenix API.
It never offers workflow execution, service actions, node actions or approval writes.
"""

from __future__ import annotations

import os
import re
from typing import Any, Literal
from urllib.parse import quote, urlparse

import httpx
from mcp.server.mcpserver import MCPServer

DEFAULT_BASE_URL = "http://127.0.0.1:14014"
DEFAULT_TIMEOUT_SECONDS = 5.0
DEFAULT_MAX_BYTES = 524_288

SENSITIVE_KEY = re.compile(
    r"(secret|token|password|passwd|cookie|authorization|credential|private[_-]?key|session|api[_-]?key)",
    re.IGNORECASE,
)
SENSITIVE_VALUE_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+"),
    re.compile(r"(?i)((?:token|password|passwd|secret|api[_-]?key)\s*[:=]\s*)[^\s,;]+"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
)
WRITE_PATH = re.compile(r"(?:/actions/(?:start|stop|restart|pause|resume)|/run|/approve|/reject)$")

StatusView = Literal[
    "health",
    "ready",
    "system_overview",
    "integrations",
    "agents",
    "ai_status",
    "ai_models",
    "security",
    "audit_verify",
    "knowledge",
]
CollectionView = Literal["workflows", "runs", "nodes", "services", "logs", "approvals"]
DetailView = Literal["workflow", "run", "node", "service", "approval"]

STATUS_PATHS: dict[str, str] = {
    "health": "/api/health",
    "ready": "/api/ready",
    "system_overview": "/api/system/overview",
    "integrations": "/api/integrations",
    "agents": "/api/agents",
    "ai_status": "/api/ai/status",
    "ai_models": "/api/ai/models",
    "security": "/api/security/status",
    "audit_verify": "/api/audit/verify",
    "knowledge": "/api/knowledge",
}

COLLECTION_PATHS: dict[str, str] = {
    "workflows": "/api/workflows",
    "runs": "/api/runs",
    "nodes": "/api/nodes",
    "services": "/api/services",
    "logs": "/api/logs/recent",
    "approvals": "/api/approvals",
}

DETAIL_PATHS: dict[str, str] = {
    "workflow": "/api/workflows/{id}",
    "run": "/api/runs/{id}",
    "node": "/api/nodes/{id}",
    "service": "/api/services/{id}",
    "approval": "/api/approvals/{id}",
}

mcp = MCPServer(
    "ShadowOps Runtime Read-Only",
    version="1.0.0",
    instructions=(
        "Read-only access to the local ShadowOps runtime. "
        "Never claim that a write/action was performed: this server exposes no write tools."
    ),
)


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be positive")
    return value


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be numeric") from exc
    if value <= 0:
        raise RuntimeError(f"{name} must be positive")
    return value


def _base_url() -> str:
    raw = os.getenv("SHADOWOPS_BASE_URL", DEFAULT_BASE_URL).strip().rstrip("/")
    parsed = urlparse(raw)

    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise RuntimeError("SHADOWOPS_BASE_URL must be an absolute http(s) URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise RuntimeError("SHADOWOPS_BASE_URL must not contain credentials, query or fragment")
    if parsed.path not in {"", "/"}:
        raise RuntimeError("SHADOWOPS_BASE_URL must not contain a path")

    host = parsed.hostname.lower()
    loopback_hosts = {"127.0.0.1", "localhost", "::1"}
    allow_remote = os.getenv("SHADOWOPS_MCP_ALLOW_REMOTE_UPSTREAM") == "1"
    if host not in loopback_hosts and not allow_remote:
        raise RuntimeError(
            "remote ShadowOps upstream rejected; set SHADOWOPS_MCP_ALLOW_REMOTE_UPSTREAM=1 only when intentional"
        )

    return raw


def _headers() -> dict[str, str]:
    headers = {"accept": "application/json", "user-agent": "shadowops-runtime-mcp/1.0"}
    token = os.getenv("SHADOWOPS_READ_TOKEN", "").strip()
    if token:
        headers["authorization"] = f"Bearer {token}"
    return headers


def _scrub_string(value: str) -> str:
    scrubbed = value
    for pattern in SENSITIVE_VALUE_PATTERNS:
        if pattern.groups:
            scrubbed = pattern.sub(r"\1[REDACTED]", scrubbed)
        else:
            scrubbed = pattern.sub("[REDACTED]", scrubbed)
    max_chars = _env_int("SHADOWOPS_MCP_MAX_STRING_CHARS", 16_384)
    if len(scrubbed) > max_chars:
        return scrubbed[:max_chars] + "...[TRUNCATED]"
    return scrubbed


def _sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            str(key): "[REDACTED]" if SENSITIVE_KEY.search(str(key)) else _sanitize(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_sanitize(item) for item in value]
    if isinstance(value, str):
        return _scrub_string(value)
    return value


def _read(path: str) -> dict[str, Any]:
    if not path.startswith("/api/"):
        return {"ok": False, "error": "non_api_path_rejected"}
    if WRITE_PATH.search(path):
        return {"ok": False, "error": "write_capability_rejected"}

    try:
        timeout = _env_float("SHADOWOPS_MCP_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)
        max_bytes = _env_int("SHADOWOPS_MCP_MAX_BYTES", DEFAULT_MAX_BYTES)
        with httpx.Client(timeout=timeout, follow_redirects=False, headers=_headers()) as client:
            response = client.get(_base_url() + path)
    except httpx.RequestError as exc:
        return {"ok": False, "error": "upstream_unavailable", "type": exc.__class__.__name__}
    except RuntimeError as exc:
        return {"ok": False, "error": "configuration_error", "detail": str(exc)}

    if response.status_code < 200 or response.status_code >= 300:
        return {"ok": False, "error": "upstream_http_error", "status": response.status_code}

    if len(response.content) > max_bytes:
        return {"ok": False, "error": "upstream_payload_too_large", "max_bytes": max_bytes}

    try:
        payload = response.json()
    except ValueError:
        return {"ok": False, "error": "upstream_non_json_response"}

    return {"ok": True, "source": path, "data": _sanitize(payload)}


def _detail_path(view: str, identifier: str) -> str | None:
    template = DETAIL_PATHS.get(view)
    if template is None:
        return None
    identifier = identifier.strip()
    if not identifier or len(identifier) > 180:
        return None
    return template.format(id=quote(identifier, safe=""))


@mcp.tool()
def shadowops_status(view: StatusView = "system_overview") -> dict[str, Any]:
    """Read one high-level ShadowOps status view."""
    path = STATUS_PATHS.get(view)
    if path is None:
        return {"ok": False, "error": "unknown_status_view"}
    return _read(path)


@mcp.tool()
def shadowops_list(view: CollectionView) -> dict[str, Any]:
    """List a read-only ShadowOps collection such as workflows, runs, nodes or services."""
    path = COLLECTION_PATHS.get(view)
    if path is None:
        return {"ok": False, "error": "unknown_collection_view"}
    return _read(path)


@mcp.tool()
def shadowops_get(view: DetailView, identifier: str) -> dict[str, Any]:
    """Read one workflow, run, node, service or approval by identifier."""
    path = _detail_path(view, identifier)
    if path is None:
        return {"ok": False, "error": "invalid_detail_request"}
    return _read(path)


@mcp.tool()
def shadowops_snapshot() -> dict[str, Any]:
    """Return a compact operational snapshot from health, readiness, system and security views."""
    return {
        "health": _read(STATUS_PATHS["health"]),
        "ready": _read(STATUS_PATHS["ready"]),
        "system_overview": _read(STATUS_PATHS["system_overview"]),
        "security": _read(STATUS_PATHS["security"]),
    }


def _run() -> None:
    transport = os.getenv("SHADOWOPS_MCP_TRANSPORT", "stdio").strip().lower()
    if transport == "stdio":
        mcp.run()
        return

    if transport != "streamable-http":
        raise RuntimeError("SHADOWOPS_MCP_TRANSPORT must be stdio or streamable-http")

    host = os.getenv("SHADOWOPS_MCP_HOST", "127.0.0.1").strip()
    if host not in {"127.0.0.1", "localhost", "::1"} and os.getenv("SHADOWOPS_MCP_ALLOW_REMOTE_BIND") != "1":
        raise RuntimeError(
            "non-loopback MCP bind rejected; use a secure tunnel or explicitly set SHADOWOPS_MCP_ALLOW_REMOTE_BIND=1"
        )
    port = _env_int("SHADOWOPS_MCP_PORT", 8765)
    mcp.run(
        transport="streamable-http",
        host=host,
        port=port,
        stateless_http=True,
        json_response=True,
    )


if __name__ == "__main__":
    _run()
