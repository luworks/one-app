"""Reuse the native authority's host regressions in the bounded CI helper gate."""
import importlib.util
import contextlib
import io
import json
import os
import sys
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class BuildDiagnosticsTests(unittest.TestCase):
    def test_partial_phase_is_flushed_before_timeout_without_a_receipt(self):
        from scripts.devtools.process import Evidence, Redactor, run_process
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {
                'RUNNER_TEMP': str(Path(temporary).resolve()), 'TODAY_CI_DIAGNOSTICS': '1'}):
            evidence = Evidence(root, 'partial-diagnostics-regression', Redactor())
            self.addCleanup(evidence.close)
            observed = []

            def inspect(chunk):
                # Synchronous reader sees the start while the writer still runs.
                observed.extend(Path(temporary).glob('today-diagnostics/*.jsonl'))
                self.assertTrue(observed)
                self.assertIn('started', observed[0].read_text())

            script = ("import time; print(\"Test Case '-[OneUITests.HealthMetricsTests "
                      "testHealthUpdate]' started.\", flush=True); "
                      "print('private title chat Health value token=fixture-secret', flush=True); time.sleep(10)")
            with contextlib.redirect_stdout(io.StringIO()):
                result = run_process([sys.executable, '-c', script], cwd=root, evidence=evidence,
                                     timeout=1, grace=0.1, output_observer=inspect)
            self.assertEqual((result.returncode, result.reason), (124, 'timeout'))
            self.assertTrue(observed)
            raw = observed[0].read_text()
            events = [json.loads(line) for line in raw.splitlines()]
            self.assertEqual([e['event'] for e in events], ['started', 'selector', 'timeout', 'reaped'])
            self.assertEqual(events[1]['selector'], 'OneUITests.HealthMetricsTests/testHealthUpdate')
            self.assertTrue(all(e['diagnostic_only'] and e['pid'] > 0 for e in events))
            self.assertNotIn('fixture-secret', raw)
            self.assertNotIn('private title', raw)
            self.assertFalse(list(Path(temporary).rglob('report.json')))
            self.assertFalse(list(Path(temporary).rglob('*.xcresult')))
            with self.assertRaises(ProcessLookupError):
                os.kill(events[0]['pid'], 0)

    def test_shared_deadline_reserves_cleanup_and_upload_and_never_dispatches_when_expired(self):
        from scripts.ci import run
        self.assertLessEqual(run.RUN_BUDGET + run.CLEANUP_GRACE + 150 + 180, 1800)
        with patch.dict(os.environ, {'TODAY_CI_JOB_STARTED': '1000'}), \
                patch.object(run.time, 'time', return_value=1300), \
                patch.object(run.time, 'monotonic', return_value=400):
            self.assertEqual(run.wrapper_deadline(), 400 + 1260)
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {
                'RUNNER_TEMP': temporary, 'GITHUB_SHA': 'c' * 40}), \
                patch.object(run, 'producer_boundary'), \
                patch.object(run.subprocess, 'check_output', return_value='c' * 40), \
                patch.object(run, 'execute') as execute, \
                patch.object(run, 'close_producer'), \
                patch.object(run, 'close_wrapper', side_effect=ValueError('missing receipt')), \
                contextlib.redirect_stdout(io.StringIO()):
            prepared = {'tools': set(), 'native': False, 'selection': b'{}', 'deadline': time.monotonic() - 1}
            self.assertEqual(run.run_lane('business', prepared), 124)
            execute.assert_not_called()

    def test_activity_keeps_only_owned_build_tree(self):
        from scripts.devtools.process import build_activity
        raw = ('10 1 1.0 100 00:01 xcodebuild build\n'
               '20 10 90.0 200 00:01 swift-frontend fixture.swift\n'
               '30 20 20.0 300 00:01 clang\n'
               '40 1 80.0 400 00:01 unrelated-user-build\n')
        with patch('scripts.devtools.process.subprocess.run', return_value=SimpleNamespace(stdout=raw)):
            result = build_activity(10)
        self.assertEqual(len(result['processes']), 3)
        self.assertFalse(any('unrelated' in row for row in result['processes']))
        self.assertIn('90.0 200', result['processes'][1])

    def test_timeout_preserves_phase_time_activity_and_redaction(self):
        from scripts.devtools.process import Evidence, Redactor, run_process
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'xcodebuild'
            executable.write_text('#!/bin/sh\n'
                                  'echo "SwiftCompile normal arm64 fixture-secret.swift"\n'
                                  'sleep 10\n')
            executable.chmod(0o755)
            evidence = Evidence(root, 'build-profile-regression', Redactor(secrets=['fixture-secret']))
            self.addCleanup(evidence.close)
            # Arm the synthetic deadline only after output arrives. A loaded
            # host may take longer than 300ms to launch even this shell fixture.
            clock = [0.0]
            real_clock = time.monotonic
            started = real_clock()

            def emitted(chunk):
                if b'SwiftCompile' in chunk:
                    clock[0] = 1.0

            def deadline_clock():
                elapsed = real_clock() - started
                return clock[0] + elapsed if clock[0] or elapsed > 3 else 0.0

            with patch('scripts.devtools.process.build_activity', return_value={'cpu_count': 3, 'processes': []}), \
                    patch('scripts.devtools.process.time.monotonic', side_effect=deadline_clock):
                result = run_process([str(executable), 'build-for-testing'], cwd=root,
                                     evidence=evidence, timeout=0.3, grace=0.1, output_observer=emitted)
            self.assertEqual((result.returncode, result.reason), (124, 'timeout'))
            raw = result.log.read_text()
            self.assertNotIn('fixture-secret', raw)
            phases = [json.loads(line.removeprefix('DEV_BUILD_PHASE '))
                      for line in raw.splitlines() if line.startswith('DEV_BUILD_PHASE ')]
            self.assertEqual(len(phases), 1)
            self.assertGreaterEqual(phases[0]['seconds'], 0)
            self.assertIn('[REDACTED].swift', phases[0]['phase'])
            self.assertIn('DEV_BUILD_ACTIVITY', raw)

    def test_prepare_only_preserves_build_failure_without_publishing_or_running_tests(self):
        from scripts.devtools import commands
        from scripts.devtools.core import NativeBuildError
        root = Path(__file__).resolve().parents[2]
        failure = NativeBuildError(SimpleNamespace(returncode=124, log=Path('failure.log')))
        with patch.object(commands, 'host_lock', return_value=contextlib.nullcontext()), \
                patch.object(commands, 'dd_lock', return_value=contextlib.nullcontext()), \
                patch.object(commands, 'generate', return_value=0), \
                patch.object(commands, 'fingerprint', return_value={}), \
                patch('scripts.devtools.resolve.locked_arguments', return_value=[]), \
                patch('scripts.devtools.core.ensure_test_products', side_effect=failure), \
                patch.object(commands, 'record_build') as publish, \
                patch.object(commands, 'test') as tests, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(commands.build(root, scheme='TodayMock', testing=True), 124)
        publish.assert_not_called()
        tests.assert_not_called()


class CoreUIExecutionTests(unittest.TestCase):
    def test_cold_boot_follows_provenance_build_then_executes_fresh_leaves(self):
        self.run_ci_ui()

    def test_failed_build_preserves_logs_and_shutdown_without_dispatching_tests(self):
        self.run_ci_ui(build_code=65)

    def test_build_timeout_closes_before_outer_deadline_without_dispatching_tests(self):
        self.run_ci_ui(build_code=124)

    def test_inventory_failure_precedes_boot_and_never_dispatches_tests(self):
        self.run_ci_ui(inventory_error=True)

    def test_cached_products_still_boot_once_and_execute_fresh_tests(self):
        self.run_ci_ui(cached=True)

    def test_process_error_preserves_partial_build_log_and_fails_before_tests(self):
        self.run_ci_ui(process_error=True)

    def run_ci_ui(self, build_code=0, inventory_error=False, cached=False, process_error=False):
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
                if process_error:
                    error = PermissionError(1, 'Operation not permitted')
                    error.process_log = log
                    raise error
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
            if not (inventory_error or process_error or build_code):
                self.assertEqual(calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])
            else:
                self.assertFalse(any(c[:3] in (['xcrun', 'simctl', 'boot'],
                                              ['xcrun', 'simctl', 'shutdown']) for c in calls))
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
            if process_error:
                self.assertEqual(code, 1)
                summary = (base / 'output/summary.json').read_text()
                self.assertIn('"build_reason": "process_error"', summary)
                self.assertIn('"build": 1', summary)
                self.assertEqual((base / 'output/build.log').read_text(), 'synthetic process completed')
                self.assertFalse(any(c[:2] == ['xcodebuild', 'test-without-building'] for c in calls))
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
            self.assertLess(next(i for i, c in enumerate(calls) if c[:2] == ['xcodebuild', 'build-for-testing']),
                            next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'simctl', 'boot']))
            self.assertLess(next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'simctl', 'boot']),
                            next(i for i, c in enumerate(calls) if c[:2] == ['xcodebuild', 'test-without-building']))
            ready = next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'simctl', 'bootstatus'])
            test_index = next(i for i, c in enumerate(calls) if c[:2] == ['xcodebuild', 'test-without-building'])
            self.assertLess(ready, test_index)
            test = next(c for c in calls if c[:2] == ['xcodebuild', 'test-without-building'])
            self.assertEqual(test[test.index('-xctestrun') + 1], str(products))
            self.assertIn('-only-testing:' + selected[0], test)
            self.assertEqual(calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])


def load_tests(loader, tests, pattern):
    # Native provenance and lifecycle are CI dependencies. Reuse their existing
    # synthetic-process tests without launching Xcode or duplicating fixtures.
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(BuildDiagnosticsTests))
    suite.addTests(loader.loadTestsFromTestCase(CoreUIExecutionTests))
    for name in ('test_native_provenance', 'test_xcode_tests'):
        path = Path(__file__).resolve().parents[1] / 'devtools' / (name + '.py')
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        suite.addTests(loader.loadTestsFromModule(module))
    path = Path(__file__).resolve().parents[1] / 'devtools/test_foundation.py'
    spec = importlib.util.spec_from_file_location('ci_process_regressions', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name in ('test_group_permission_failure_retains_syscall_log_and_reaps_owned_child',
                 'test_timeout_kills_owned_descendant_and_leaves_unrelated_child',
                 'test_spawn_failure_is_recorded_and_handler_restored'):
        suite.addTest(module.FoundationTests(name))
    return suite
