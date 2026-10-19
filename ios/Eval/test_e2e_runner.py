"""Host-only runner contracts. No Xcode, Swift, simulator or device commands execute."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("e2e", Path(__file__).with_name("run-e2e.py"))
e2e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e2e)


class RunnerContracts(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        real_journal = e2e.Journal
        patcher = patch.object(e2e, "Journal", side_effect=lambda: real_journal(Path(directory.name) / "activity.sqlite"))
        patcher.start()
        self.addCleanup(patcher.stop)

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
            self.assertIn("-only-testing:TodayUITests", command)
            self.assertEqual(command[command.index("-jobs") + 1], "2")
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

    def test_same_name_wrong_model_or_runtime_is_rejected(self):
        args = e2e.parser().parse_args(["--full"])
        for runtime, device_type in ((args.runtime, "another-model"), ("another-runtime", args.device_type)):
            with self.subTest(runtime=runtime, device_type=device_type), patch.object(e2e, "capture", return_value=json.dumps({
                "devices": {runtime: [{"name": args.simulator_name, "udid": "owned-id", "state": "Shutdown",
                                       "deviceTypeIdentifier": device_type}]}
            })):
                with self.assertRaisesRegex(ValueError, "model/runtime"):
                    e2e.select_simulator(args)

    def test_observation_modes_never_open_database(self):
        with patch.object(e2e, "Journal", side_effect=AssertionError("database opened")), \
             patch.object(e2e.subprocess, "check_output", side_effect=AssertionError("process")), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(e2e.main(["--inventory"]), 0)
            self.assertEqual(e2e.main(["--full", "--dry-run"]), 0)
            with self.assertRaises(SystemExit) as result:
                e2e.main(["--help"])
            self.assertEqual(result.exception.code, 0)

    def test_default_output_is_primary_checkout_results(self):
        with patch.object(e2e, "Journal", side_effect=AssertionError("database opened")), \
             contextlib.redirect_stdout(io.StringIO()) as stdout:
            self.assertEqual(e2e.main(["--full", "--dry-run"]), 0)
        plan = json.loads(stdout.getvalue())
        self.assertEqual(Path(plan["output"]).parent, e2e.results_root() / "runs")

    def test_journal_failure_does_not_replace_test_failure(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(e2e, "Journal", side_effect=OSError("journal unavailable")), \
             patch.object(e2e, "capture", return_value="head"), \
             patch.object(e2e, "select_simulator", return_value="owned-id"), \
             patch.object(e2e, "run_logged", return_value=7), \
             patch.object(e2e.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            output = Path(directory) / "evidence"
            self.assertEqual(e2e.main(["--full", "--output", str(output)]), 7)
            self.assertEqual(json.loads((output / "summary.json").read_text())["journal_errors"], ["journal unavailable"])

    def test_real_command_records_ui_and_test_events(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            directory = Path(directory)
            journal = e2e.RunJournal("host", [])
            fixture = e2e.ROOT / "tests/qa/fixtures/attempts.log"
            command = [sys.executable, "-c", "from pathlib import Path; print(Path(" + repr(str(fixture)) + ").read_text()); raise SystemExit(7)"]
            self.assertEqual(e2e.run_logged(command, directory / "ui.log", directory / "progress.jsonl", [], journal), 7)
            rows = journal.store.query("host")
            self.assertEqual([r["kind"] for r in rows].count("qa.ui.operation"), 3)
            self.assertEqual([r["kind"] for r in rows].count("qa.test"), 4)
            self.assertEqual(json.loads(rows[-1]["props"])["exit_code"], 7)
            operations = [r for r in rows if r["kind"] == "qa.ui.operation"]
            self.assertEqual([r["subject_ref"] for r in operations],
                             ["-[OneUITests.Sample testFirst]", "-[OneUITests.Sample testSecond]", "-[OneUITests.Sample testSecond]"])
            journal.store.close()

    def test_external_output_is_retained_after_original_is_removed_without_reimport(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "external"
            bundle = output / "fake.xcresult/Data"
            bundle.mkdir(parents=True)
            (output / "ui.log").write_bytes(b"original raw log\r\n")
            (bundle / "object").write_bytes(b"result object")
            journal = e2e.RunJournal("external-host", [])
            db = journal.store.path
            journal.record("qa.test", "already recorded live", status="passed", subject="testLive")
            journal.finish(output, {"status": "passed"})
            shutil.rmtree(output)
            from journal import Journal, digest
            reopened = Journal(db)
            self.addCleanup(reopened.close)
            rows = reopened.query("external-host")
            self.assertEqual(len([r for r in rows if r["kind"] == "qa.test"]), 1)
            retained = Path(next(r["action"] for r in rows if r["kind"] == "qa.archive"))
            self.assertEqual((retained / "ui.log").read_bytes(), b"original raw log\r\n")
            self.assertEqual((retained / "fake.xcresult/Data/object").read_bytes(), b"result object")
            for row in rows:
                if row["kind"] == "qa.artifact":
                    self.assertEqual(digest(row["action"]), json.loads(row["props"])["sha256"])

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
