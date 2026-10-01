import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).parents[1] / "publish_tasks.py"
SPEC = importlib.util.spec_from_file_location("publish_tasks", MODULE)
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads((Path(__file__).parents[1] / "tasks.json").read_text())

    def test_versioned_document_is_valid_and_has_unique_ids(self):
        publisher.validate(self.document)
        self.assertEqual(len(self.document["tasks"]), len({item["id"] for item in self.document["tasks"]}))

    def test_unknown_or_private_field_is_rejected(self):
        changed = copy.deepcopy(self.document)
        changed["tasks"][0]["account"] = "private"
        with self.assertRaises(ValueError):
            publisher.validate(changed)

    def test_private_and_done_tasks_never_cross_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tasks.json"
            data = copy.deepcopy(self.document)
            private = dict(data["tasks"][0], id="private-fixture", visibility="private")
            done = dict(data["tasks"][0], id="done-fixture", status="done")
            data["tasks"] += [private, done]
            source.write_text(json.dumps(data))
            sent = []
            def runner(command, **kwargs):
                sent.extend(json.loads(kwargs["input"])["tasks"])
                return subprocess.CompletedProcess(command, 0, stdout=b"UPDATED\n")
            publisher.publish(source, Path(directory) / "state/status.json", runner)
            self.assertNotIn("private-fixture", [item["id"] for item in sent])
            self.assertNotIn("done-fixture", [item["id"] for item in sent])

    def test_failed_transport_preserves_last_success(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tasks.json"
            source.write_text(json.dumps(self.document))
            status = Path(directory) / "state/status.json"
            publisher.atomic_status(status, {"last_success": "previous-success"})
            def runner(command, **kwargs):
                raise subprocess.TimeoutExpired(command, 45)
            with self.assertRaises(subprocess.TimeoutExpired):
                publisher.publish(source, status, runner)
            self.assertEqual(json.loads(status.read_text())["last_success"], "previous-success")
            self.assertEqual(json.loads(status.read_text())["status"], "error")

    def test_publish_uses_fixed_receiver_and_records_success(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tasks.json"
            source.write_text(json.dumps(self.document))
            calls = []

            def runner(command, **kwargs):
                calls.append((command, kwargs))
                return subprocess.CompletedProcess(command, 0, stdout=b"UPDATED\n")

            status = Path(directory) / "state/status.json"
            self.assertTrue(publisher.publish(source, status, runner))
            self.assertEqual(command := calls[0][0][-1], "/home/schattenmacher/Projects/learning-kiosk/scripts/install-task-content.py")
            self.assertEqual(json.loads(status.read_text())["status"], "ok")


if __name__ == "__main__":
    unittest.main()
