from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

MODULE_PATH = Path(__file__).with_name("shadowops_runtime_mcp.py")
SPEC = importlib.util.spec_from_file_location("shadowops_runtime_mcp", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
runtime_mcp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime_mcp)


class ShadowOpsRuntimeMCPTest(unittest.TestCase):
    def test_all_exposed_routes_are_api_reads(self) -> None:
        paths = list(runtime_mcp.STATUS_PATHS.values()) + list(runtime_mcp.COLLECTION_PATHS.values())
        for template in runtime_mcp.DETAIL_PATHS.values():
            paths.append(template.format(id="example"))

        for path in paths:
            self.assertTrue(path.startswith("/api/"), path)
            self.assertIsNone(runtime_mcp.WRITE_PATH.search(path), path)

    def test_write_routes_are_rejected_but_runs_collection_is_not(self) -> None:
        self.assertIsNone(runtime_mcp.WRITE_PATH.search("/api/runs"))
        self.assertIsNone(runtime_mcp.WRITE_PATH.search("/api/runs/run-123"))
        self.assertIsNotNone(runtime_mcp.WRITE_PATH.search("/api/workflows/demo/run"))
        self.assertIsNotNone(runtime_mcp.WRITE_PATH.search("/api/nodes/i7/actions/stop"))
        self.assertIsNotNone(runtime_mcp.WRITE_PATH.search("/api/approvals/42/approve"))
        self.assertIsNotNone(runtime_mcp.WRITE_PATH.search("/api/approvals/42/reject"))

    def test_detail_identifier_is_path_encoded(self) -> None:
        self.assertEqual(
            runtime_mcp._detail_path("workflow", "alpha/beta"),
            "/api/workflows/alpha%2Fbeta",
        )
        self.assertIsNone(runtime_mcp._detail_path("workflow", ""))
        self.assertIsNone(runtime_mcp._detail_path("unknown", "value"))

    def test_sensitive_keys_and_values_are_redacted(self) -> None:
        data = {
            "status": "ok",
            "api_token": "top-secret",
            "nested": {
                "message": "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
                "password": "do-not-return",
                "github": "ghp_abcdefghijklmnopqrstuvwxyz123456",
            },
        }
        cleaned = runtime_mcp._sanitize(data)

        self.assertEqual(cleaned["status"], "ok")
        self.assertEqual(cleaned["api_token"], "[REDACTED]")
        self.assertEqual(cleaned["nested"]["password"], "[REDACTED]")
        self.assertNotIn("abcdefghijklmnopqrstuvwxyz", cleaned["nested"]["message"])
        self.assertEqual(cleaned["nested"]["github"], "[REDACTED]")

    def test_default_upstream_is_loopback(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(runtime_mcp._base_url(), "http://127.0.0.1:14014")

    def test_remote_upstream_fails_closed(self) -> None:
        with patch.dict(
            os.environ,
            {"SHADOWOPS_BASE_URL": "https://shadowops.example.com"},
            clear=True,
        ):
            with self.assertRaises(RuntimeError):
                runtime_mcp._base_url()

    def test_remote_upstream_requires_explicit_override(self) -> None:
        with patch.dict(
            os.environ,
            {
                "SHADOWOPS_BASE_URL": "https://shadowops.example.com",
                "SHADOWOPS_MCP_ALLOW_REMOTE_UPSTREAM": "1",
            },
            clear=True,
        ):
            self.assertEqual(runtime_mcp._base_url(), "https://shadowops.example.com")

    def test_read_token_stays_in_authorization_header(self) -> None:
        with patch.dict(os.environ, {"SHADOWOPS_READ_TOKEN": "secret-value"}, clear=True):
            headers = runtime_mcp._headers()
            self.assertEqual(headers["authorization"], "Bearer secret-value")


if __name__ == "__main__":
    unittest.main()
