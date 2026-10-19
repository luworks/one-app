"""Host-only CI regressions. No Swift, Xcode, simulator or full test execution."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.devtools import ci_adapter as adapter  # noqa: E402
from scripts.ci.policy import validate_report  # noqa: E402


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.root, self.output = base / 'repo', base / 'output'
        self.root.mkdir()
        for name, suite in [('ios/Eval/Tests/OneLogicTests/DomainTests.swift', 'DomainTests'),
                            ('ios/OneUITests/CalendarSyncTests.swift', 'CalendarSyncTests'),
                            ('ios/OneUITests/RemindersSyncTests.swift', 'RemindersSyncTests'),
                            ('ios/OneUITests/EventSaveTests.swift', 'EventSaveTests')]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('final class ' + suite + ': XCTestCase {\n    func testRoundTrip() {}\n}\n')
        for args in (['init', '-q'], ['add', '.'],
                     ['-c', 'user.name=CI Tests', '-c', 'user.email=ci@example.invalid', 'commit', '-qm', 'Synthetic source']):
            subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.selection = base / 'selection.json'
        self.selection.write_text(json.dumps({'version': 1, 'mode': 'wide', 'reason': 'synthetic regression',
                                             'changed': [], 'targets': [], 'all_targets': True, 'snapshots': True}))
        self.calls = []

    def invoke(self, *, runner=None, lane='business', **kwargs):
        options = dict(selection=self.selection, output=self.output, sha=self.sha, synthetic=True, no_distribute=True)
        options.update(kwargs)
        return adapter._main(self.root, lane, runner=runner or self.runner(), **options)

    def report(self):
        return json.loads((self.output / 'report.json').read_text())

    def runner(self, raw="Test Case '-[DomainTests testRoundTrip]' passed\n", code=0, reason='exited', mutate=None):
        def run(root, argv, **options):
            self.calls.append((argv, options))
            if mutate:
                mutate()
            log = Path(self.temporary.name) / 'process.log'
            log.write_text(raw)
            return SimpleNamespace(returncode=code, reason=reason, log=log)
        return run

    def test_real_finished_test_required_for_success(self):
        self.assertEqual(self.invoke(), 0)
        validate_report(self.report(), self.sha, 'business')
        self.assertEqual(self.report()['executed'], 1)
        self.assertEqual(self.calls[0][0], ['swift', 'test', '--package-path', 'ios', '--jobs', '2'])
        self.assertTrue(self.calls[0][1]['heavy'])

    def test_exit_zero_without_results_and_badselector_fail(self):
        for raw in ('Build complete!\n', 'badselector\n',
                    "Test Case '-[DomainTests testRoundTrip]' passed\nno matching test\n"):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'output'
                self.assertEqual(self.invoke(runner=self.runner(raw), output=output), 1)
                report = json.loads((output / 'report.json').read_text())
                self.assertEqual(report['status'], 'failed')

    def test_failure_cannot_be_erased_by_later_pass(self):
        raw = "Test Case '-[DomainTests testRoundTrip]' failed\nTest Case '-[DomainTests testRoundTrip]' passed\n"
        self.assertEqual(self.invoke(runner=self.runner(raw)), 1)
        self.assertEqual(self.report()['failed'], 1)
        self.assertEqual(self.report()['executed'], 2)
        self.assertEqual(len(self.calls), 1)
        self.assertIn('failed', (self.output / 'command.log').read_text())

    def test_missing_selected_test_and_unexpected_test_rejected(self):
        self.assertEqual(self.invoke(runner=self.runner("Test Case '-[OtherTests testOther]' passed\n")), 1)
        self.assertEqual(self.report()['missing'], 1)
        self.assertIn('unexpected_test', self.report()['errors'])

    def test_process_failure_timeout_and_cancellation_cannot_pass(self):
        for code, reason in ((7, 'exited'), (124, 'timeout'), (130, 'cancelled')):
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'output'
                self.assertEqual(self.invoke(runner=self.runner(code=code, reason=reason), output=output), 1)
                report = json.loads((output / 'report.json').read_text())
                self.assertEqual(report['status'], 'failed')
                if reason == 'cancelled':
                    self.assertEqual(report['cancelled'], 1)

    def test_interrupted_and_missing_log_write_failed_report(self):
        for exception in (KeyboardInterrupt(), FileNotFoundError('missing log')):
            with self.subTest(exception=type(exception)), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'output'
                self.assertEqual(self.invoke(runner=lambda *a, **k: (_ for _ in ()).throw(exception), output=output), 1)
                self.assertEqual(json.loads((output / 'report.json').read_text())['status'], 'failed')

    def test_sha_source_and_safety_flags_checked_before_execution(self):
        for options in ({'sha': 'f' * 40}, {'synthetic': False}, {'no_distribute': False}, {'lane': 'unknown'}):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory:
                self.assertEqual(self.invoke(output=Path(directory) / 'out', **options), 1)
        self.assertEqual(self.calls, [])

    def test_dirty_checkout_and_source_mutation_rejected(self):
        source = self.root / 'ios/Eval/Tests/OneLogicTests/DomainTests.swift'
        self.assertEqual(self.invoke(runner=self.runner(mutate=lambda: source.write_text('changed'))), 1)
        self.assertIn('clean checkout', ' '.join(self.report()['errors']))
        self.assertEqual(self.invoke(output=Path(self.temporary.name) / 'another'), 1)
        self.assertEqual(len(self.calls), 1)

    def test_invalid_selection_and_unknown_group_selector_do_not_run(self):
        self.selection.write_text('{}')
        self.assertEqual(self.invoke(), 1)
        self.assertEqual(self.calls, [])

    def test_absent_authoritative_selector_rejected_before_runner(self):
        path = self.root / 'ios/OneUITests/EventSaveTests.swift'
        path.unlink()
        subprocess.run(['git', 'add', '-u'], cwd=self.root, check=True, capture_output=True)
        subprocess.run(['git', '-c', 'user.name=CI Tests', '-c', 'user.email=ci@example.invalid',
                        'commit', '-qm', 'Remove synthetic selector'], cwd=self.root, check=True, capture_output=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.assertEqual(self.invoke(lane='integration'), 1)
        self.assertIn('Unknown selection', ' '.join(self.report()['errors']))
        self.assertEqual(self.calls, [])

    def test_ui_log_failure_survives_passing_tree(self):
        def run(root, argv, **options):
            output = Path(argv[argv.index('--output') + 1])
            output.mkdir()
            expected = [argv[i + 1] for i, value in enumerate(argv) if value == '--only']
            (output / 'summary.json').write_text(json.dumps({'head': self.sha, 'selection': expected,
                'status': 'passed', 'stages': {'ui': 0, 'shutdown': 0}}))
            (output / 'xcresult-tests.json').write_text(json.dumps([
                {'nodeType': 'Test Case', 'nodeIdentifier': test, 'result': 'Passed'} for test in expected]))
            return self.runner(raw="Test Case '-[CalendarSyncTests testRoundTrip]' failed\n")(root, argv, **options)
        self.assertEqual(self.invoke(lane='integration', runner=run), 1)
        self.assertEqual(self.report()['failed'], 1)
        self.assertEqual(self.report()['executed'], 3)
        self.assertEqual(len(self.calls), 1)

    def test_ui_uses_structured_leaf_results(self):
        def run(root, argv, **options):
            self.calls.append((argv, options))
            output = Path(argv[argv.index('--output') + 1])
            output.mkdir()
            expected = [argv[i + 1] for i, value in enumerate(argv) if value == '--only']
            (output / 'summary.json').write_text(json.dumps({'head': self.sha, 'selection': expected,
                'status': 'passed', 'stages': {'ui': 0, 'shutdown': 0}}))
            (output / 'xcresult-tests.json').write_text(json.dumps([
                {'nodeType': 'Test Case', 'nodeIdentifier': test, 'result': 'Passed'} for test in expected]))
            return self.runner(raw='UI session completed\n')(root, argv, **options)
        self.assertEqual(self.invoke(lane='integration', runner=run), 0)
        self.assertEqual(self.report()['executed'], 3)
        self.assertNotIn('--full', self.calls[0][0])

    def test_ui_rejects_runner_from_another_sha(self):
        def run(root, argv, **options):
            output = Path(argv[argv.index('--output') + 1])
            output.mkdir()
            (output / 'summary.json').write_text(json.dumps({'head': 'f' * 40}))
            return self.runner(raw='completed another revision')(root, argv, **options)
        self.assertEqual(self.invoke(lane='integration', runner=run), 1)
        self.assertIn('Runner SHA mismatch', ' '.join(self.report()['errors']))

    def test_existing_report_never_overwritten(self):
        self.output.mkdir()
        (self.output / 'report.json').write_text('original')
        self.assertEqual(self.invoke(), 1)
        self.assertEqual((self.output / 'report.json').read_text(), 'original')
        self.assertEqual(self.calls, [])

    def test_output_file_returns_failure_without_replacing_it(self):
        self.output.write_text('preserve existing file')
        self.assertEqual(self.invoke(), 1)
        self.assertEqual(self.output.read_text(), 'preserve existing file')
        self.assertEqual(self.calls, [])

    def test_unsupported_and_manual_lanes_fail_without_work(self):
        for lane in adapter.UNSUPPORTED.keys() | {'extended'}:
            with self.subTest(lane=lane), tempfile.TemporaryDirectory() as directory:
                self.assertEqual(self.invoke(lane=lane, output=Path(directory) / 'out'), 1)
        self.assertEqual(self.calls, [])

    def test_build_checks_embedded_products_instead_of_exit_only(self):
        self.assertEqual(self.invoke(lane='build', runner=self.runner()), 1)
        self.assertEqual(self.report()['executed'], 0)
        self.assertEqual(self.report()['missing'], 3)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', self.calls[0][0])

    def test_format_does_not_rewrite_and_missing_receipts_fail(self):
        with patch.object(adapter.commands, 'format_sources', return_value=0) as format_sources:
            self.assertEqual(self.invoke(lane='format'), 1)
        format_sources.assert_called_once_with(self.root.resolve(), check=True)

    def test_artifact_allowlist_redaction_and_symlink_rejection(self):
        self.assertEqual(self.invoke(), 0)
        (self.output / 'private.sqlite').write_text('excluded')
        (self.output / 'secret.log').write_text('token=secretvalue /Users/example/private')
        target = Path(self.temporary.name) / 'artifacts'
        adapter.safe_artifacts(self.output, target, sha=self.sha, lane='business')
        self.assertFalse((target / 'private.sqlite').exists())
        self.assertNotIn('secretvalue', (target / 'secret.log').read_text())
        self.assertNotIn('/Users/example', (target / 'secret.log').read_text())
        (self.output / 'leak.log').symlink_to(self.output / 'report.json')
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            adapter.safe_artifacts(self.output, target.with_name('other'), sha=self.sha, lane='business')
        with self.assertRaisesRegex(ValueError, 'provenance'):
            adapter.safe_artifacts(self.output, target.with_name('wrong'), sha='wrong', lane='business')


if __name__ == '__main__':
    unittest.main()
