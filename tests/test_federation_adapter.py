#!/usr/bin/env python3
"""Offline-only tests for the sanitized federation adapter."""
import contextlib
import io
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from inspect_shadowops_federation import safe_summary, main


def fixture():
    return {
        "schema_version": 1,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "policy": {"mode": "READ_ONLY", "local_agent_execution": False,
                   "auto_merge": False, "auto_deploy": False,
                   "auto_email": False, "project_execution_allowed": False},
        "ihk_boundary": {"state": "UNKNOWN", "release_allowed": False},
        "repositories": [{"repository": "DonMassa84/shadowops",
                          "access": "OK", "secret": "SENSITIVE_MARKER"},
                         {"repository": "DonMassa84/private",
                          "access": "UNKNOWN"}],
        "websites": [{"url": "https://archiv-bruecke-frs.netlify.app/",
                      "state": "PASS"}],
        "handoff_proposals": [
            {"priority": "P0", "route": "human_review", "status": "PROPOSAL_ONLY",
             "requires_operator_approval": True, "execution_permitted": False,
             "details": "SENSITIVE_MARKER"},
        ],
    }


class LocalAdapterTests(unittest.TestCase):
    def test_only_bounded_aggregates_leave_adapter(self):
        out = safe_summary(fixture())
        self.assertEqual(out["repository_total"], 2)
        self.assertEqual(out["repository_unknown"], 1)
        self.assertEqual(out["proposals_p0"], 1)
        self.assertEqual(out["ihk"], "BLOCKED_UNVERIFIED")
        self.assertFalse(out["agent_execution_allowed"])
        self.assertNotIn("SENSITIVE_MARKER", json.dumps(out))
        self.assertNotIn("DonMassa84/private", json.dumps(out))

    def test_fail_closed_on_open_execution_flag(self):
        for key in ("local_agent_execution", "auto_merge", "auto_deploy",
                    "auto_email", "project_execution_allowed"):
            data = fixture()
            data["policy"][key] = True
            with self.subTest(key=key), self.assertRaises(ValueError):
                safe_summary(data)

    def test_refuses_unsafe_handoff(self):
        for field, value in [("requires_operator_approval", False),
                             ("execution_permitted", True),
                             ("route", "run_shell"),
                             ("status", "EXECUTING")]:
            data = fixture()
            data["handoff_proposals"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                safe_summary(data)

    def test_ihk_release_cannot_be_open_or_missing(self):
        for value in (True, None):
            data = fixture()
            data["ihk_boundary"]["release_allowed"] = value
            with self.assertRaises(ValueError):
                safe_summary(data)

    def test_missing_source_is_not_permitted(self):
        with self.assertRaises(ValueError):
            safe_summary({})
        data = fixture()
        data["repositories"] = "all"
        with self.assertRaises(ValueError):
            safe_summary(data)

    def test_freshness_fails_closed_for_stale_or_future_artifacts(self):
        sample_time = datetime(2026, 10, 22, 20, tzinfo=timezone.utc)
        data = fixture()
        data["generated_utc"] = sample_time.isoformat()
        self.assertEqual(safe_summary(data, now=sample_time)["proposals_p0"], 1)
        for value in (
            None,
            "2026-10-22T20:00:00",
            (sample_time - timedelta(days=3)).isoformat(),
            (sample_time + timedelta(hours=2)).isoformat(),
            "bad-timestamp",
        ):
            data["generated_utc"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                safe_summary(data, now=sample_time)

    def test_cli_reads_external_file_without_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "snapshot.json"
            path.write_text(json.dumps(fixture()), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = main(["--input", str(path)])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(output.getvalue())["proposals_p0"], 1)
            self.assertEqual([x.name for x in Path(folder).iterdir()], ["snapshot.json"])


if __name__ == "__main__":
    unittest.main()
