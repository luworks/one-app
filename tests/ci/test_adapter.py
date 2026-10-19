"""Host-only CI regressions. No Swift, Xcode, simulator or full test execution."""
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
import shutil
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
        sources = {
            'ios/SceneRegistryTests/SceneRegistryTests.swift': 'final class SceneRegistryTests: XCTestCase {\n func testRegistry() {}\n}',
            'ios/TodayIntegrationTests/StoreUpgradeTests.swift': 'struct StoreUpgradeTests {\n @Test func baselineStorePreservesAllFieldsAcrossReopenAndMutation() {}\n}',
            'ios/TodayIntegrationTests/PlannerSessionTests.swift': 'struct PlannerSessionTests {\n @Test func isolatedSessionBehavior() {}\n}',
            'ios/TodaySnapshotTests/NativeSnapshotTests.swift': 'final class NativeSnapshotTests: XCTestCase {\n func testImage() {}\n}',
        }
        for selector in adapter.CORE_EXTRA + (
                'JourneyTests/testJ1_addTimedTaskFromOneLine', 'JourneyTests/testJ3_completeAndUndo',
                'CalendarAlarmTests/testWeekLateAlarmOpensItsEditorWithoutOtherEntries',
                'AskSuggestionTests/testPolitePlanRequestPreservesPreviewThroughOperationQuestionsUntilApply'):
            suite, method = selector.split('/')
            path = 'ios/OneUITests/' + suite + '.swift'
            sources[path] = sources.get(path, 'final class ' + suite + ': XCTestCase {\n') + ' func ' + method + '() {}\n'
        for name, text in sources.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text + ('}' if name.startswith('ios/OneUITests/') else ''))
        for args in (['init', '-q'], ['add', '.'],
                     ['-c', 'user.name=CI Tests', '-c', 'user.email=ci@example.invalid', 'commit', '-qm', 'Synthetic source']):
            subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.selection = base / 'selection.json'
        self.selection.write_text(json.dumps({'version': 1, 'mode': 'wide', 'reason': 'synthetic regression',
                                             'changed': [], 'targets': [], 'all_targets': True, 'snapshots': True}))
        self.calls = []
        # These host-injected execution fixtures exercise result authority. The
        # production workflow boundary is covered without mocks in test_producer.
        boundary = patch('scripts.ci.run.producer_boundary')
        boundary.start()
        self.addCleanup(boundary.stop)

    def invoke(self, *, runner=None, lane='business', **kwargs):
        options = dict(selection=self.selection, output=self.output, sha=self.sha, synthetic=True, no_distribute=True)
        options.update(kwargs)
        if lane == 'release':
            with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'workflow_dispatch', 'MANUAL_LANE': 'release'}):
                return adapter._main(self.root, lane, runner=runner or self.runner(), **options)
        return adapter._main(self.root, lane, runner=runner or self.runner(), **options)

    def report(self):
        return json.loads((self.output / 'report.json').read_text())

    def runner(self, raw="Test Case '-[DomainTests testRoundTrip]' passed\nTest Case 'SceneRegistryTests/SceneRegistryTests/testRegistry' passed\n", code=0, reason='exited', mutate=None):
        def run(root, argv, **options):
            self.calls.append((argv, options))
            if mutate:
                mutate()
            log = Path(self.temporary.name) / 'process.log'
            log.write_text(raw)
            return SimpleNamespace(returncode=code, reason=reason, log=log)
        return run

    def test_routine_instrumentation_is_scoped_and_invalidates_product_provenance(self):
        from scripts.devtools import core
        with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_LANE': 'core-ui'}):
            routine = core.fingerprint(self.root, tools={})
            self.assertEqual(core.native_test_options(), [
                '-enableCodeCoverage', 'NO', 'COMPILER_INDEX_STORE_ENABLE=NO',
                'SWIFT_ENABLE_EXPLICIT_MODULES=NO'])
            import runpy
            ui = runpy.run_path(str(ROOT / 'ios/Eval/run-e2e.py'))
            command = ui['ui_command'](['TodayUITests/JourneyTests/testJ3_completeAndUndo'],
                                       'synthetic-device', Path('derived'), Path('output'))
            self.assertEqual(command[command.index('-enableCodeCoverage') + 1], 'NO')
            self.assertIn('COMPILER_INDEX_STORE_ENABLE=NO', command)
            self.assertIn('SWIFT_ENABLE_EXPLICIT_MODULES=NO', command)
            self.assertIn('-only-testing:TodayUITests/JourneyTests/testJ3_completeAndUndo', command)
            self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
        for lane in ('extended', 'release', 'protected-release', ''):
            with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_LANE': lane}):
                self.assertEqual(core.native_test_options(), [])
                self.assertNotEqual(routine, core.fingerprint(self.root, tools={}))
        with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '0', 'TODAY_LANE': 'core-ui'}):
            self.assertEqual(core.native_test_options(), [])

    def test_shared_batch_uses_identical_product_fingerprint_for_all_consumers(self):
        from scripts.devtools import core, xcode_tests
        identities = []
        with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_CI_NATIVE_BATCH': '1'}):
            for lane in ('build', 'integration', 'snapshots', 'core-ui'):
                with patch.dict(os.environ, {'TODAY_LANE': lane}):
                    self.assertEqual(core.ci_test_scheme('TodayMock'), 'TodayCI')
                    identities.append(core.fingerprint(self.root, scheme='TodayCI', tools={}))
            self.assertTrue(all(identity == identities[0] for identity in identities))
            self.assertEqual(xcode_tests.test_scheme('snapshot'), 'TodayCI')
        with patch.dict(os.environ, {'TODAY_CI_NATIVE_BATCH': '0'}):
            self.assertEqual(core.ci_test_scheme('TodayMock'), 'TodayMock')

    def test_smoke_uses_ui_products_with_production_build_in_same_producer(self):
        from scripts.devtools import core
        project = json.loads((ROOT / 'ios/project.yml').read_text())
        targets = project['schemes']['TodayMock']['build']['targets']
        self.assertEqual(set(targets), {'Today', 'TodayMock'})
        with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_CI_NATIVE_BATCH': '1',
                                     'TODAY_CI_UI_ONLY': '1'}):
            identities = []
            for lane in ('build', 'core-ui'):
                with patch.dict(os.environ, {'TODAY_LANE': lane}):
                    self.assertEqual(core.ci_test_scheme('TodayCI'), 'TodayMock')
                    identities.append(core.fingerprint(self.root, scheme='TodayMock', tools={}))
            self.assertEqual(identities[0], identities[1])

    def test_batch_workflow_plan_accepts_shared_scheme_and_rejects_unknown_scheme(self):
        from scripts.devtools import cli, core
        environment = {'TODAY_CI_SYNTHETIC': '1', 'TODAY_CI_NATIVE_BATCH': '1', 'TODAY_LANE': 'build'}
        output = io.StringIO()
        with patch.dict(os.environ, environment), \
                patch.object(cli, 'inventory', return_value={'toolchain': {}}), redirect_stdout(output):
            self.assertEqual(cli.main(['plan', '--scheme', 'TodayCI', '--architecture', 'arm64'],
                                      root=self.root), 0)
            expected = core.fingerprint(self.root, scheme='TodayCI', architecture='arm64', tools={})
            report = json.loads(output.getvalue())
            self.assertEqual(report['fingerprint'], expected)
            self.assertEqual(report['compiler_module_cache'], core.compiler_module_cache(self.root, expected))
        with patch.object(cli, 'inventory') as inventory, redirect_stderr(io.StringIO()), \
                self.assertRaises(SystemExit) as rejected:
            cli.main(['plan', '--scheme', 'UnknownScheme'], root=self.root)
        self.assertEqual(rejected.exception.code, 2)
        inventory.assert_not_called()

    def test_real_finished_test_required_for_success(self):
        self.assertEqual(self.invoke(), 0)
        validate_report(self.report(), self.sha, 'business')
        self.assertEqual(self.report()['executed'], 2)
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
        self.assertEqual(self.report()['missing'], 2)
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
        path = self.root / 'ios/TodayIntegrationTests/StoreUpgradeTests.swift'
        path.unlink()
        subprocess.run(['git', 'add', '-u'], cwd=self.root, check=True, capture_output=True)
        subprocess.run(['git', '-c', 'user.name=CI Tests', '-c', 'user.email=ci@example.invalid',
                        'commit', '-qm', 'Remove synthetic selector'], cwd=self.root, check=True, capture_output=True)
        self.sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.root, text=True).strip()
        self.assertEqual(self.invoke(lane='integration'), 1)
        self.assertRegex(' '.join(self.report()['errors']), 'Zero discovered tests|Unknown selection: StoreUpgradeTests')
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
        self.assertEqual(self.invoke(lane='core-ui', runner=run), 1)
        self.assertEqual(self.report()['failed'], 1)
        self.assertEqual(self.report()['executed'], 7)
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
        self.assertEqual(self.invoke(lane='core-ui', runner=run), 0)
        self.assertEqual(self.report()['executed'], 7)
        self.assertNotIn('--full', self.calls[0][0])
        self.assertEqual(self.calls[0][1], {'timeout': 1200, 'heavy': True, 'grace': 20})

    def test_ui_rejects_runner_from_another_sha(self):
        def run(root, argv, **options):
            output = Path(argv[argv.index('--output') + 1])
            output.mkdir()
            (output / 'summary.json').write_text(json.dumps({'head': 'f' * 40}))
            return self.runner(raw='completed another revision')(root, argv, **options)
        self.assertEqual(self.invoke(lane='core-ui', runner=run), 1)
        self.assertIn('Runner SHA mismatch', ' '.join(self.report()['errors']))

    def native(self, lane='integration', *, statuses=('Passed',), code=0, diagnostic='', bundle=True, change=None, receipts=1):
        from scripts.devtools import xcode_tests
        kind, expected = adapter.test_plan(self.root, lane)
        directory = self.root / ('tests/results/devtools/logs/' + lane + '-xcode')
        directory.mkdir(parents=True)
        scheme = xcode_tests.test_scheme(kind)
        if bundle:
            store = directory / (scheme + '.xcresult') / 'Data'
            store.mkdir(parents=True)
            (store / 'binary').write_bytes(b'\x00opaque\xff')
            (store.parent / '.metadata.json').write_bytes(b'{"path":"/Users/example/synthetic"}')
        tree = [{'nodeType': 'Test Case', 'nodeIdentifier': test, 'result': status}
                for test in expected for status in statuses]
        native = xcode_tests.completed_report(adapter.contract, expected, kind, tree, 0, diagnostic)
        if change:
            change(native, directory)
        path = directory / (scheme + '.report.json')
        path.write_text(json.dumps(native))

        def test(root, group, **kwargs):
            self.assertEqual(group, kind)
            self.assertEqual(kwargs, {'only': expected, 'timeout': 600})
            print(json.dumps({'exit': 0, 'reason': 'exited', 'seconds': 0.1, 'log': str(directory / 'build.log')}))
            for _ in range(receipts):
                print(json.dumps({'report': str(path), 'status': native['status']}))
            print(json.dumps({'exit': 0, 'reason': 'exited', 'seconds': 0.1, 'log': str(directory / 'shutdown.log')}))
            (directory / 'shutdown.log').write_text('owned simulator shutdown finished')
            return code
        # Result storage is ignored by real repositories, including hosted CI.
        def batch(root, authority, groups, **kwargs):
            self.assertIs(authority, adapter.contract)
            self.assertEqual(groups, [kind])
            self.assertTrue(kwargs.pop('reuse'))
            return test(root, kind, **kwargs)

        batched = os.environ.get('TODAY_CI_NATIVE_BATCH') == '1'
        with patch.object(adapter, 'source_state', return_value='fixed'), patch.object(
                adapter.commands, 'test', side_effect=test) as direct, patch.object(
                xcode_tests, 'run', side_effect=batch) as shared:
            result = self.invoke(lane=lane)
        (shared if batched else direct).assert_called_once()
        (direct if batched else shared).assert_not_called()
        self.assertEqual(self.calls, [])
        return result

    def test_native_batch_reuses_product_authority_and_requires_fresh_leaves(self):
        with patch.dict(os.environ, {'TODAY_CI_SYNTHETIC': '1', 'TODAY_CI_NATIVE_BATCH': '1'}):
            for index, statuses in enumerate((('Passed',), ())):
                self.output = Path(self.temporary.name) / ('batch' + str(index))
                shutil.rmtree(self.root / 'tests/results/devtools/logs/integration-xcode', ignore_errors=True)
                self.assertEqual(self.native(statuses=statuses), 0 if statuses else 1)
                self.assertEqual(self.report()['status'], 'passed' if statuses else 'failed')

    def test_native_integration_and_snapshot_completed_leaf_success(self):
        for lane in ('integration', 'snapshots'):
            with self.subTest(lane=lane):
                self.output = Path(self.temporary.name) / lane
                self.assertEqual(self.native(lane), 0)
                validate_report(self.report(), self.sha, lane)
                self.assertEqual(self.report()['executed'], 2 if lane == 'integration' else 1)
                copied = next((self.output / 'native').glob('*.xcresult/Data/binary'))
                self.assertEqual(copied.read_bytes(), b'\x00opaque\xff')
                entries = {entry['path'] for entry in self.report()['artifact_provenance']['files']}
                self.assertIn('native/shutdown.log', entries)
                self.assertIn('native/' + copied.parent.parent.name + '/.metadata.json', entries)

    def test_native_failure_skip_zero_unknown_and_first_failure_fail_closed(self):
        for index, statuses in enumerate((('Failed', 'Passed'), ('Skipped',), (), ('Unknown',))):
            with self.subTest(statuses=statuses):
                self.output = Path(self.temporary.name) / str(index)
                directory = self.root / 'tests/results/devtools/logs/integration-xcode'
                shutil.rmtree(directory, ignore_errors=True)
                self.assertEqual(self.native(statuses=statuses), 1)
                self.assertEqual(self.report()['status'], 'failed')
                self.assertTrue(self.report()['errors'])

    def test_native_missing_extra_wrong_target_and_symlink_are_rejected(self):
        def missing(native, directory):
            native['attempts'] = []

        def wrong_target(native, directory):
            native['attempts'][0]['test'] = 'TodayUITests/StoreUpgradeTests/baselineStorePreservesAllFieldsAcrossReopenAndMutation'

        def extra(native, directory):
            native['attempts'].append(dict(native['attempts'][0], test='TodayTests/Other/testOther'))

        def symlink(native, directory):
            (directory / 'leak.log').symlink_to(self.selection)

        for index, change in enumerate((missing, wrong_target, extra, symlink)):
            with self.subTest(change=change.__name__):
                self.output = Path(self.temporary.name) / str(index)
                shutil.rmtree(self.root / 'tests/results/devtools/logs/integration-xcode', ignore_errors=True)
                self.assertEqual(self.native(change=change), 1)

    def test_bundle_staging_preserves_bytes_and_indexes_hashes(self):
        self.assertEqual(self.native(), 0)
        bundle = next((self.output / 'native').glob('*.xcresult'))
        target = Path(self.temporary.name) / 'staged'
        adapter.safe_artifacts(self.output, target, sha=self.sha, lane='integration')
        original = bundle / '.metadata.json'
        relative = original.relative_to(self.output)
        self.assertEqual((target / relative).read_bytes(), original.read_bytes())
        manifest = json.loads((target / 'manifest.json').read_text())
        self.assertIn(relative.as_posix(), [entry['path'] for entry in manifest['files']])

    def test_native_passing_leaves_cannot_hide_exit_or_log_failure(self):
        self.assertEqual(self.native(code=130, diagnostic='Test testImage failed after 0.1 seconds'), 1)
        self.assertEqual(self.report()['cancelled'], 1)
        self.assertIn('log_failure', self.report()['errors'])

    def test_native_missing_bundle_and_receipt_fail_closed(self):
        self.assertEqual(self.native(bundle=False), 1)
        self.assertIn('Missing completed native xcresult', ' '.join(self.report()['errors']))
        with patch.object(adapter.commands, 'test', return_value=0), patch.object(
                adapter, 'source_state', return_value='fixed'):
            self.assertEqual(self.invoke(lane='integration', output=self.output.with_name('missing')), 1)

    def test_native_duplicate_receipts_fail_closed(self):
        self.assertEqual(self.native(receipts=2), 1)
        self.assertIn('Missing or ambiguous native test receipt', ' '.join(self.report()['errors']))

    def test_native_build_timeout_publishes_closed_logs_but_never_passes(self):
        def failed_build(native, directory):
            native['attempts'] = []
            native['exit_code'] = 124
            native['status'] = 'failed'
            native['errors'] = ['native_build_exit:124']
            native['build_error'] = 'Native build failed; exit=124; log=/Users/synthetic/build.log'
            (directory / 'build.log').write_text('build-for-testing timed out; exit=124')

        self.assertEqual(self.native(lane='snapshots', code=124, bundle=False, change=failed_build), 1)
        report = self.report()
        self.assertEqual(report['executed'], 0)
        self.assertGreater(report['missing'], 0)
        self.assertIn('native_build_exit:124', report['errors'])
        self.assertIn('native_command_exit:124', report['errors'])
        self.assertTrue((self.output / 'native/build.log').is_file())
        target = Path(self.temporary.name) / 'failed-build-published'
        adapter.safe_artifacts(self.output, target, sha=self.sha, lane='snapshots')
        self.assertEqual((target / 'native/build.log').read_text(), 'build-for-testing timed out; exit=124')
        self.assertNotIn('/Users/synthetic', (target / 'report.json').read_text())
        with self.assertRaises(ValueError):
            validate_report(report, self.sha, 'snapshots')

    def test_release_does_not_accept_debug_products(self):
        dd = Path(self.temporary.name) / 'dd'
        products = dd / 'Build/Products/Debug-iphonesimulator/One.app'
        for relative in ('One', 'PlugIns/TodayWidgets.appex/TodayWidgets', 'PlugIns/ShareExtension.appex/ShareExtension'):
            path = products / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'debug executable')
        with patch.object(adapter, 'derived_data', return_value=dd):
            self.assertEqual(self.invoke(lane='release'), 1)
        self.assertEqual(self.report()['missing'], 3)
        self.assertEqual(self.report()['executed'], 0)

    def test_release_builds_release_products_but_refuses_missing_inspector(self):
        # Use a temporary DD, never the machine's shared build cache.
        with patch.object(adapter, 'derived_data', return_value=Path(self.temporary.name) / 'dd'):
            products = adapter.derived_data(self.root) / 'Build/Products/Release-iphonesimulator/One.app'
            for relative in ('One', 'PlugIns/TodayWidgets.appex/TodayWidgets', 'PlugIns/ShareExtension.appex/ShareExtension'):
                path = products / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'mocked executable')
            with patch('scripts.release.graph.check', return_value={'model_module': 'One'}) as graph_check:
                self.assertEqual(self.invoke(lane='release'), 1)
            graph_check.assert_called_once()
        self.assertEqual(self.report()['executed'], 3)
        self.assertIn('Release', self.calls[0][0])
        self.assertIn('Release artifact resources rejected: required_privacy_manifest_missing', ' '.join(self.report()['errors']))

    def test_release_source_and_resources_cannot_replace_actual_product_link_maps(self):
        import plistlib
        dd = Path(self.temporary.name) / 'dd'
        products = dd / 'Build/Products/Release-iphonesimulator/One.app'
        privacy = plistlib.dumps({'NSPrivacyTracking': False})
        (self.root / 'LICENSE').write_text('synthetic license')
        (self.root / 'ios/PrivacyInfo.xcprivacy').write_bytes(privacy)
        for relative in ('One', 'PlugIns/TodayWidgets.appex/TodayWidgets', 'PlugIns/ShareExtension.appex/ShareExtension'):
            path = products / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'synthetic executable')
        (products / 'LICENSE').write_text('synthetic license')
        (products / 'PrivacyInfo.xcprivacy').write_bytes(privacy)
        (products / 'ThirdPartyNotices.txt').write_text(
            'GeoNames https://www.geonames.org https://creativecommons.org/licenses/by/4.0/ transform')
        with patch.object(adapter, 'derived_data', return_value=dd), patch.object(
                adapter, 'source_state', return_value='fixed'), patch(
                'scripts.release.graph.check', return_value={'model_module': 'One'}):
            self.assertEqual(self.invoke(lane='release'), 1)
        self.assertIn('link_map_missing', str(self.report()['errors']))
        self.assertTrue((self.output / 'release-graph.json').is_file())
        self.assertIn('protected-release', adapter.UNSUPPORTED)
        self.assertFalse(any('archive' in argv for argv, _ in self.calls))

        # A completed Release link supplies three executable-bound maps. The
        # same validator used by archive validation rejects changed UUIDs/inputs.
        uid = '11111111-1111-1111-1111-111111111111'
        def linked(root, argv, **options):
            lines = []
            if argv[0] == 'xcodebuild':
                map_arg = next(x for x in argv if x.startswith('LD_MAP_FILE_PATH='))
                folder = Path(map_arg.split('=', 1)[1]).parent
                for name in ('One', 'TodayWidgets', 'ShareExtension'):
                    target = {'One': 'Today', 'TodayWidgets': 'TodayWidgets', 'ShareExtension': 'TodayShare'}[name]
                    path = folder / (target + '-' + name + '.map')
                    binary = products / name if name == 'One' else products / 'PlugIns' / (name + '.appex') / name
                    linked_binary = binary if name == 'One' else products.parent / (name + '.appex') / name
                    linked_binary.parent.mkdir(parents=True, exist_ok=True)
                    linked_binary.write_bytes(binary.read_bytes())
                    path.write_text('# Path: ' + str(linked_binary) + '\n# Arch: arm64\n# Object files:\n[  1] /synthetic/One.o\n# Sections:\n')
                    import shlex
                    lines.append('clang -Xlinker -map -Xlinker ' + shlex.quote(str(path)) + ' -o ' + shlex.quote(str(linked_binary)))
            return self.runner(raw='\n'.join(lines))(root, argv, **options)
        with patch.object(adapter, 'derived_data', return_value=dd), patch.object(
                adapter, 'source_state', return_value='fixed'), patch(
                'scripts.release.graph.check', return_value={'model_module': 'One'}), patch(
                'scripts.release.release.uuids', return_value=[(uid, 'arm64')]):
            result_code = self.invoke(lane='release', output=self.output.parent / 'linked', runner=linked)
            self.assertEqual(result_code, 0, (self.output.parent / 'linked/report.json').read_text())
        result = json.loads((self.output.parent / 'linked/report.json').read_text())
        self.assertEqual(result['executed'], 3)
        self.assertEqual(result['status'], 'passed')

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
        self.assertFalse((target / 'secret.log').exists())
        self.assertIn('command.log', [e['path'] for e in json.loads((target / 'manifest.json').read_text())['files']])
        (self.output / 'leak.log').symlink_to(self.output / 'report.json')
        report = self.report()
        report['artifact_provenance']['files'].append({'path': 'leak.log', 'bytes': 0, 'sha256': '0' * 64})
        (self.output / 'report.json').write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, 'symlink'):
            adapter.safe_artifacts(self.output, target.with_name('other'), sha=self.sha, lane='business')
        with self.assertRaisesRegex(ValueError, 'provenance'):
            adapter.safe_artifacts(self.output, target.with_name('wrong'), sha='wrong', lane='business')


if __name__ == '__main__':
    unittest.main()
