import pathlib
import unittest

ROOT = pathlib.Path(
    __file__
).resolve().parents[1]


class VerifiedE2EContract(
    unittest.TestCase
):

    def test_builtin_verified_workflow(self):
        text = (
            ROOT / "server.py"
        ).read_text()

        self.assertIn(
            "shadowops-verified-self-check",
            text
        )

        self.assertIn(
            '"L0"',
            text
        )

        self.assertIn(
            '"builtin-read-only"',
            text
        )

    def test_fail_closed_external(self):
        text = (
            ROOT / "server.py"
        ).read_text()

        self.assertIn(
            "execution_not_verified",
            text
        )

    def test_run_persistence(self):
        text = (
            ROOT / "server.py"
        ).read_text()

        self.assertIn(
            "RUNS",
            text
        )

        self.assertIn(
            "result_sha256",
            text
        )

    def test_audit_persistence(self):
        text = (
            ROOT / "server.py"
        ).read_text()

        self.assertIn(
            "AUDIT",
            text
        )

        self.assertIn(
            "event_sha256",
            text
        )

    def test_no_config_driven_shell(self):
        text = (
            ROOT / "server.py"
        ).read_text()

        self.assertNotIn(
            "shell=True",
            text
        )

        self.assertNotIn(
            "os.system(",
            text
        )


if __name__ == "__main__":
    unittest.main()
