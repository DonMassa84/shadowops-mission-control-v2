#!/usr/bin/env python3

import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class VerifiedAppContract(unittest.TestCase):

    def test_inventory_exists(self):
        self.assertTrue((ROOT / "data/workflows.json").exists())

    def test_schema(self):
        data = json.loads((ROOT / "data/workflows.json").read_text())
        self.assertEqual(data["schema"], "shadowops-verified-app-v1")

    def test_fail_closed(self):
        data = json.loads((ROOT / "data/workflows.json").read_text())
        self.assertEqual(data["policy"], "fail-closed")

    def test_no_fake_execution_verified(self):
        data = json.loads((ROOT / "data/workflows.json").read_text())
        for workflow in data["workflows"]:
            self.assertFalse(workflow["execution_verified"])
            self.assertFalse(workflow["start_enabled"])

    def test_all_ids_are_canonical(self):
        data = json.loads((ROOT / "data/workflows.json").read_text())
        for workflow in data["workflows"]:
            self.assertTrue(workflow["id"].startswith("so:wf:v1:"))

    def test_unique_ids(self):
        data = json.loads((ROOT / "data/workflows.json").read_text())
        ids = [x["id"] for x in data["workflows"]]
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

if __name__ == "__main__":
    unittest.main()
