"""Reuse the native authority's host regressions in the bounded CI helper gate."""
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class CoreUIExecutionTests(unittest.TestCase):
    def test_boot_overlaps_one_provenance_build_then_executes_fresh_leaves(self):
        self.run_ci_ui()

    def test_failed_build_preserves_logs_and_shutdown_without_dispatching_tests(self):
        self.run_ci_ui(build_code=65)

    def test_build_timeout_closes_before_outer_deadline_without_dispatching_tests(self):
        self.run_ci_ui(build_code=124)

    def test_inventory_failure_precedes_boot_and_never_dispatches_tests(self):
        self.run_ci_ui(inventory_error=True)

    def test_cached_products_still_boot_once_and_execute_fresh_tests(self):
        self.run_ci_ui(cached=True)

    def run_ci_ui(self, build_code=0, inventory_error=False, cached=False):
        path = Path(__file__).resolve().parents[2] / 'ios/Eval/run-e2e.py'
        spec = importlib.util.spec_from_file_location('ci_ui_runner', path)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        selected = ['TodayUITests/JourneyTests/testJ3_completeAndUndo']
        calls = []
        journal = Mock()

        def action(command, function, **kwargs):
            calls.append(command)
            return 'synthetic-head' if command[0] == 'git' else SimpleNamespace(returncode=0)

        journal.action.side_effect = action
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            products = base / 'TodayMock.xctestrun'
            products.write_bytes(b'synthetic products')

            def logged(command, logfile, *args):
                calls.append(command)
                logfile.write_text('synthetic process completed')
                return build_code if command[1] == 'build-for-testing' else 0

            def ensure(root, scheme, invoke, **kwargs):
                self.assertEqual(scheme, 'TodayMock')
                self.assertEqual(kwargs['flags'], ['-disableAutomaticPackageResolution'])
                self.assertFalse(any(c[:3] == ['xcrun', 'simctl', 'boot'] for c in calls))
                calls.append(['source-inventory'])
                if inventory_error:
                    raise RuntimeError('Git source inventory failed: timeout after 30s')
                if cached:
                    return products
                result = invoke(['xcodebuild', 'build-for-testing', '-project', 'ios/Today.xcodeproj'])
                if result.returncode:
                    from scripts.devtools.core import NativeBuildError
                    raise NativeBuildError(result)
                return products

            def execute(root, command, *, timeout):
                self.assertEqual(timeout, 600)
                log = base / 'owned-build.log'
                logged(command, log)
                return SimpleNamespace(returncode=build_code, reason='timeout' if build_code == 124 else 'exited', log=log)

            with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_LANE': 'core-ui'}), \
                    patch.object(runner, 'derived_data', return_value=base / 'dd'), \
                    patch.object(runner, 'RunJournal', return_value=journal), \
                    patch.object(runner, 'select_simulator', return_value='owned'), \
                    patch.object(runner, 'run_logged', side_effect=logged), \
                    patch.object(runner, 'execute', side_effect=execute), \
                    patch.object(runner, 'ensure_test_products', side_effect=ensure) as build, \
                    patch.object(runner, 'read_xcresult', return_value=[{
                        'test': selected[0], 'status': 'passed', 'source': 'xcresult'}]), \
                    patch('scripts.devtools.resolve.locked_arguments', return_value=['-disableAutomaticPackageResolution']):
                code = runner.main(['--only', selected[0], '--derived-data', str(base / 'dd'),
                                    '--output', str(base / 'output'), '--simulator-name', 'Today-CI-Unit'])
            build.assert_called_once()
            if not inventory_error:
                self.assertEqual(calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])
            if inventory_error:
                self.assertEqual(code, 1)
                summary = (base / 'output/summary.json').read_text()
                self.assertIn('Git source inventory failed', summary)
                self.assertIn('"shutdown_reason": "not_booted"', summary)
                self.assertFalse(any(c[:3] == ['xcrun', 'simctl', 'shutdown'] for c in calls))
                self.assertFalse(any(c[:3] == ['xcrun', 'simctl', 'boot'] for c in calls))
                self.assertFalse(any(c[0] == 'xcodebuild' for c in calls))
                return
            if cached:
                self.assertEqual(code, 0)
                self.assertEqual(sum(c[:3] == ['xcrun', 'simctl', 'boot'] for c in calls), 1)
                self.assertFalse(any(c[:2] == ['xcodebuild', 'build-for-testing'] for c in calls))
                return
            if build_code:
                self.assertEqual(code, 1)
                summary = (base / 'output/summary.json').read_text()
                self.assertIn('exit=' + str(build_code), summary)
                if build_code == 124:
                    self.assertIn('"build_reason": "timeout"', summary)
                self.assertTrue((base / 'output/build.log').is_file())
                self.assertFalse(any(c[:2] == ['xcodebuild', 'test-without-building'] for c in calls))
                return
            self.assertEqual(code, 0)
            self.assertLess(next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'simctl', 'boot']),
                            next(i for i, c in enumerate(calls) if c[:2] == ['xcodebuild', 'build-for-testing']))
            self.assertLess(next(i for i, c in enumerate(calls) if c[:2] == ['xcodebuild', 'build-for-testing']),
                            next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'simctl', 'bootstatus']))
            test = next(c for c in calls if c[:2] == ['xcodebuild', 'test-without-building'])
            self.assertEqual(test[test.index('-xctestrun') + 1], str(products))
            self.assertIn('-only-testing:' + selected[0], test)
            self.assertEqual(calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])


def load_tests(loader, tests, pattern):
    # Native provenance and lifecycle are CI dependencies. Reuse their existing
    # synthetic-process tests without launching Xcode or duplicating fixtures.
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(CoreUIExecutionTests))
    for name in ('test_native_provenance', 'test_xcode_tests'):
        path = Path(__file__).resolve().parents[1] / 'devtools' / (name + '.py')
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        suite.addTests(loader.loadTestsFromModule(module))
    return suite
