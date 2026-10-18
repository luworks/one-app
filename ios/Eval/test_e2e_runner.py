"""Host-only runner contracts. No Xcode, Swift, simulator or device commands execute."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("e2e", Path(__file__).with_name("run-e2e.py"))
e2e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e2e)


class RunnerContracts(unittest.TestCase):
    def test_dry_run_does_not_probe_or_write(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "must-not-exist"
            with patch.object(e2e.subprocess, "Popen", side_effect=AssertionError("process launched")), \
                 patch.object(e2e.subprocess, "run", side_effect=AssertionError("process launched")), \
                 patch.object(e2e.subprocess, "check_output", side_effect=AssertionError("probe launched")), \
                 contextlib.redirect_stdout(io.StringIO()) as stdout:
                code = e2e.main(["--full", "--dry-run", "--logic", "--output", str(output)])
            plan = json.loads(stdout.getvalue())
            self.assertEqual(code, 0)
            self.assertFalse(output.exists())
            self.assertEqual(plan["commands"][0], ["swift", "test", "--jobs", "2"])
            command = plan["commands"][1]
            self.assertIn("-only-testing:OneUITests", command)
            self.assertEqual(command[command.index("-parallel-testing-enabled") + 1], "NO")
            self.assertFalse(any("CODE_SIGN" in arg or "Provisioning" in arg for arg in command))

    def test_failure_and_interrupt_retain_summary_and_shutdown(self):
        for result, expected_code, expected_status in ((7, 7, "failed"), (KeyboardInterrupt(), 130, "interrupted")):
            with self.subTest(result=result), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "evidence"
                calls = []
                def fake_run(command, **kwargs):
                    calls.append(command)
                    return subprocess.CompletedProcess(command, 0)
                with patch.object(e2e, "capture", return_value="fake-head"), \
                     patch.object(e2e, "select_simulator", return_value="owned-id"), \
                     patch.object(e2e, "run_logged", side_effect=result if isinstance(result, BaseException) else None,
                                  return_value=result), \
                     patch.object(e2e.subprocess, "run", side_effect=fake_run), \
                     contextlib.redirect_stdout(io.StringIO()):
                    code = e2e.main(["--only", "JourneyTests", "--output", str(output)])
                self.assertEqual(code, expected_code)
                self.assertEqual(calls[-1], ["xcrun", "simctl", "shutdown", "owned-id"])
                summary = json.loads((output / "summary.json").read_text())
                self.assertEqual(summary["status"], expected_status)
                self.assertEqual(summary["stages"]["shutdown"], 0)

    def test_preexisting_output_is_preserved_without_device_probe(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "summary.json").write_text("retained evidence")
            with patch.object(e2e, "select_simulator", side_effect=AssertionError("device probe")), \
                 contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(e2e.main(["--full", "--output", directory]), 1)
            self.assertEqual((output / "summary.json").read_text(), "retained evidence")

    def test_setup_failure_retains_summary_before_git_metadata_is_available(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            with patch.object(e2e, "capture", side_effect=OSError("git unavailable")), \
                 patch.object(e2e, "select_simulator", side_effect=AssertionError("device probe")), \
                 contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(e2e.main(["--full", "--output", str(output)]), 1)
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(summary["status"], "failed")
            self.assertEqual(summary["error"], "git unavailable")

    def test_active_or_wrong_owner_simulator_is_not_booted_or_shutdown(self):
        args = e2e.parser().parse_args(["--full", "--simulator-id", "owned-id"])
        for name, state in (("Today-QA", "Booted"), ("Today-Another", "Shutdown")):
            with self.subTest(name=name, state=state), patch.object(e2e, "capture", return_value=json.dumps({
                "devices": {"runtime": [{"name": name, "udid": "owned-id", "state": state}]}
            })):
                with self.assertRaises(ValueError):
                    e2e.select_simulator(args)

    def test_log_preserves_failure_exit_code_and_case_order(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            directory = Path(directory)
            attempts = []
            # A real harmless Python child exercises the pipe; no platform tools.
            command = [sys.executable, "-c", "print(\"Test Case '-[OneUITests.Sample testFirst]' passed (1 s).\"); "
                       "print(\"Test Case '-[OneUITests.Sample testSecond]' skipped (0 s).\"); "
                       "print('error: retained detail'); raise SystemExit(7)"]
            code = e2e.run_logged(command, directory / "ui.log", directory / "progress.jsonl", attempts)
            self.assertEqual(code, 7)
            self.assertEqual([a["status"] for a in attempts], ["passed", "skipped"])
            self.assertIn("error: retained detail", (directory / "ui.log").read_text())
            self.assertEqual(len((directory / "progress.jsonl").read_text().splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
