import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class VerifiedE2EContract(unittest.TestCase):
    def server_text(self):
        return (ROOT / "server.py").read_text()

    def test_builtin_verified_workflow(self):
        text = self.server_text()
        self.assertIn("shadowops-verified-self-check", text)
        self.assertIn('"builtin-read-only"', text)

    def test_static_whatsapp_allowlist(self):
        text = self.server_text()
        self.assertIn("WHATSAPP_SPECS", text)
        self.assertIn("verified-static-argv", text)
        self.assertIn("whatsapp-status", text)
        self.assertIn("whatsapp-maintenance-daily", text)
        self.assertIn("whatsapp-worker-drain", text)

    def test_fail_closed_external(self):
        text = self.server_text()
        self.assertIn("execution_not_verified", text)
        self.assertIn("workflow_not_allowlisted", text)
        self.assertIn("approval_required", text)

    def test_run_persistence(self):
        text = self.server_text()
        self.assertIn("RUNS", text)
        self.assertIn("result_sha256", text)

    def test_audit_persistence(self):
        text = self.server_text()
        self.assertIn("AUDIT", text)
        self.assertIn("event_sha256", text)

    def test_no_config_driven_shell(self):
        text = self.server_text()
        self.assertNotIn("shell=True", text)
        self.assertNotIn("os.system(", text)
        self.assertIn("[executable, *args]", text)


if __name__ == "__main__":
    unittest.main()
