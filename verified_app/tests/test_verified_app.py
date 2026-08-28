#!/usr/bin/env python3

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class VerifiedAppContract(unittest.TestCase):
    def inventory(self):
        return json.loads((ROOT / "data/workflows.json").read_text())

    def test_inventory_exists(self):
        self.assertTrue((ROOT / "data/workflows.json").exists())

    def test_schema(self):
        self.assertEqual(self.inventory()["schema"], "shadowops-verified-app-v1")

    def test_fail_closed(self):
        self.assertEqual(self.inventory()["policy"], "fail-closed")

    def test_acceptance_counts(self):
        workflows = self.inventory()["workflows"]
        self.assertEqual(len(workflows), 16)
        self.assertEqual(sum(x["execution_verified"] for x in workflows), 12)
        self.assertEqual(sum(x["start_enabled"] for x in workflows), 12)
        self.assertEqual(sum(x["approval_required"] for x in workflows), 2)

    def test_runtime_blockers_are_fail_closed(self):
        by_name = {x["name"]: x for x in self.inventory()["workflows"]}
        for name in ("whatsapp-doctor", "whatsapp-meta-status"):
            workflow = by_name[name]
            self.assertEqual(workflow["status"], "BLOCKED")
            self.assertFalse(workflow["execution_verified"])
            self.assertFalse(workflow["start_enabled"])
            self.assertIn("block_reason", workflow)

    def test_l2_is_approval_gated(self):
        workflows = self.inventory()["workflows"]
        l2 = [x for x in workflows if x["risk"] == "L2"]
        self.assertEqual(len(l2), 2)
        for workflow in l2:
            self.assertTrue(workflow["approval_required"])
            self.assertFalse(workflow["execution_verified"])
            self.assertFalse(workflow["start_enabled"])
            self.assertEqual(workflow["execution_status"], "APPROVAL_REQUIRED")

    def test_all_ids_are_canonical(self):
        for workflow in self.inventory()["workflows"]:
            self.assertTrue(workflow["id"].startswith("so:wf:v1:"))

    def test_unique_ids(self):
        ids = [x["id"] for x in self.inventory()["workflows"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_ui_exists(self):
        self.assertTrue((ROOT / "static/index.html").exists())
        self.assertTrue((ROOT / "static/app.css").exists())
        self.assertTrue((ROOT / "static/app.js").exists())

    def test_server_does_not_target_4013(self):
        server = (ROOT / "server.py").read_text()
        self.assertIn('"4014"', server)
        self.assertIn("production_mutation", server)
        self.assertNotIn("systemctl", server)
        self.assertNotIn("os.system(", server)
        self.assertNotIn("shell=True", server)


if __name__ == "__main__":
    unittest.main()
