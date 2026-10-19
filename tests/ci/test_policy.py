"""Synthetic policy regressions: no builds, package resolution or workflow dispatch."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/ci'))
import policy  # noqa: E402 - standalone test import bootstrap
import prerequisite  # noqa: E402 - standalone test import bootstrap
import release_guard  # noqa: E402 - standalone test import bootstrap
import subprocess  # noqa: E402 - standalone test import bootstrap

spec = importlib.util.spec_from_file_location('ci_run', ROOT / 'scripts/ci/run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SelectionTests(unittest.TestCase):
    def test_feature_minimum_and_core_logic(self):
        feature = policy.select(['ios/Sources/Features/FeatureClock/TimerView.swift'])
        self.assertEqual(feature['targets'], ['ios:FeatureClock'])
        self.assertEqual(policy.routine_lanes(feature), ['format', 'lint', 'business', 'build', 'core-ui'])
        core = policy.select(['ios/Sources/TodayCore/AutonomyPolicy.swift'])
        self.assertEqual(policy.routine_lanes(core), ['format', 'lint', 'business', 'build'])
        self.assertFalse(feature['snapshots'])

    def test_wide_fallbacks(self):
        for path in ('ios/Sources/TodayShared/Foo.swift', 'ios/Sources/One/Models.swift',
                     'ios/project.yml', 'ios/Package.swift', '.github/workflows/today.yml',
                     'new/unknown.swift', 'ios/Config/Debug.xcconfig',
                     'ios/App/Info.plist', 'tests/fixtures/data.json', 'scripts/ci/policy.py',
                     'ios/Sources/TodayCore/Schema.swift',
                     'ios/Sources/Features/FeatureHealth/HealthModel.swift'):
            with self.subTest(path=path):
                result = policy.select([path])
                self.assertTrue(result['all_targets'])
                self.assertEqual(set(policy.routine_lanes(result)),
                                 {'format', 'lint', 'business', 'build', 'core-ui', 'integration', 'snapshots'})

    def test_empty_diff_is_wide(self):
        self.assertTrue(policy.select([])['all_targets'])

    def test_docs_only_and_mixed_diff(self):
        result = policy.select(['docs/notes.md', 'ios/README.md'])
        self.assertEqual(result['targets'], [])
        self.assertFalse(result['snapshots'])
        self.assertEqual(policy.routine_lanes(result), ['format', 'lint'])
        mixed = policy.select(['docs/notes.md', 'ios/Sources/TodayCore/AutonomyPolicy.swift'])
        self.assertIn('build', policy.routine_lanes(mixed))
        self.assertTrue(policy.select(['docs/executable.py'])['all_targets'])

    def test_diff_failure_and_forged_receipt_widen(self):
        self.assertTrue(policy.select(['README.md'], reason='diff unavailable')['all_targets'])
        self.assertIn('integration', policy.routine_lanes({'changed': ['ios/Package.swift'], 'all_targets': False}))


class RiskExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from scripts.testing import contract
        cls.contract = contract
        cls.source = contract.inventory(ROOT)
        cls.broad = contract.plan(['core'], cls.source)['selectors']['ui']
        cls.logic = contract.plan(['unit'], cls.source)['selectors']['logic']

    def test_feature_selects_bounded_actual_methods(self):
        for feature in policy.FEATURE_UI:
            selection = policy.select(['ios/Sources/Features/' + feature + '/Screen.swift'])
            result = policy.execution_selection(selection, self.source, 'core-ui', self.broad)
            self.assertGreater(len(result), 0)
            self.assertLessEqual(len(result), 2)
            self.assertEqual(result, self.contract.expand(policy.FEATURE_UI[feature], self.source, 'ui'))
            logic = policy.execution_selection(selection, self.source, 'business', self.logic)
            self.assertGreater(len(logic), 0)
            self.assertLess(len(logic), len(self.logic))

    def test_completion_delete_risk_retains_undo_regression(self):
        for path in ('ios/Sources/TodayCore/ReminderCompletionFence.swift',
                     'ios/Sources/Features/FeatureReminders/ReminderListScreen.swift',
                     'ios/Sources/Features/FeatureToday/DeleteActions.swift'):
            selection = policy.select([path])
            self.assertIn('core-ui', policy.routine_lanes(selection))
            tests = policy.execution_selection(selection, self.source, 'core-ui', self.broad)
            self.assertIn('TodayUITests/JourneyTests/testJ3_completeAndUndo', tests)

    def test_changed_logic_uses_exact_authority_and_unknown_keeps_all(self):
        selection = policy.select(['ios/Sources/TodayCore/AutonomyPolicy.swift'])
        self.assertEqual(policy.execution_selection(selection, self.source, 'business', self.logic),
                         self.contract.expand(['AutonomyPolicyTests'], self.source, 'logic'))
        selection = policy.select(['ios/Sources/TodayCore/NewRule.swift'])
        self.assertEqual(policy.execution_selection(selection, self.source, 'business', self.logic), self.logic)

    def test_missing_mapped_test_is_error_not_zero_success(self):
        selection = policy.select(['ios/Sources/Features/FeatureClock/Screen.swift'])
        with patch.dict(policy.FEATURE_UI, {'FeatureClock': ('MissingTests/testMissing',)}):
            with self.assertRaisesRegex(ValueError, 'Unknown selection'):
                policy.execution_selection(selection, self.source, 'core-ui', self.broad)

    def test_manual_and_unknown_changes_keep_broad(self):
        selection = policy.select(['ios/Sources/Features/FeatureClock/TimerView.swift'])
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'workflow_dispatch'}):
            self.assertEqual(policy.execution_selection(selection, self.source, 'core-ui', self.broad), self.broad)
        for path in ('ios/Package.swift', 'unknown.swift'):
            self.assertEqual(policy.execution_selection(policy.select([path]), self.source, 'core-ui', self.broad), self.broad)

    def test_changed_ui_test_is_not_hidden_by_core(self):
        selection = policy.select(['ios/OneUITests/TimerTests.swift'])
        selected = policy.execution_selection(selection, self.source, 'core-ui', self.broad)
        for test in self.contract.expand(['TimerTests'], self.source, 'ui'):
            self.assertIn(test, selected)


class ReportTests(unittest.TestCase):
    def report(self):
        return {'sha': 'abc', 'lane': 'business', 'status': 'passed', 'executed': 1,
                'failed': 0, 'cancelled': 0, 'missing': 0, 'synthetic': True}

    def test_positive_report(self):
        policy.validate_report(self.report(), 'abc', 'business')

    def test_zero_negative_missing_and_false_success(self):
        for key, value in (('executed', 0), ('executed', -1), ('executed', True),
                           ('failed', 1), ('cancelled', 1), ('missing', 1), ('sha', 'wrong'),
                           ('status', 'skipped'), ('lane', 'integration'), ('synthetic', False)):
            report = self.report()
            report[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                policy.validate_report(report, 'abc', 'business')
        for key in self.report():
            report = self.report()
            del report[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                policy.validate_report(report, 'abc', 'business')

    def closed_receipt(self, source, files, bundles):
        report = dict(self.report(), sha='c' * 40)
        report['artifact_provenance'] = {
            'version': 1, 'owner': 'today-ci', 'run_id': source.name,
            'sha': report['sha'], 'lane': 'business', 'closed': True,
            'synthetic': True, 'secrets_available': False, 'bundles': bundles,
            'files': [{'path': path, **runner.artifact_digest((source / path).read_bytes())}
                      for path in files]}
        (source / 'report.json').write_text(json.dumps(report))

    def test_sanitized_sha_linked_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            source, dest = Path(directory) / 'raw', Path(directory) / 'staged'
            source.mkdir()
            (source / 'command.log').write_text('token=secretvalue /Users/example/data ghp_example')
            (source / 'private.sqlite').write_text('excluded')
            (source / 'crash.crash').write_text('synthetic crash')
            (source / 'test.xcresult').mkdir()
            (source / 'test.xcresult/data').write_bytes(b'synthetic bundle')
            self.closed_receipt(source, ['command.log', 'crash.crash', 'test.xcresult/data'], ['test.xcresult'])
            runner.stage(source, dest, 'c' * 40, 'business')
            manifest = json.loads((dest / 'manifest.json').read_text())
            self.assertEqual(manifest['sha'], 'c' * 40)
            self.assertEqual(len(manifest['files']), 4)
            self.assertFalse((dest / 'private.sqlite').exists())
            self.assertNotIn('secretvalue', (dest / 'command.log').read_text())
            self.assertNotIn('/Users/example', (dest / 'command.log').read_text())

    def test_symlinks_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'raw'
            source.mkdir()
            self.closed_receipt(source, [], [])
            (source / 'leak.log').symlink_to(source / 'report.json')
            report = json.loads((source / 'report.json').read_text())
            report['artifact_provenance']['files'].append({'path': 'leak.log', 'bytes': 0, 'sha256': '0' * 64})
            (source / 'report.json').write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError, 'symlink'):
                runner.stage(source, Path(directory) / 'dest', 'c' * 40, 'business')

    def test_private_artifacts_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            report = self.report()
            report['synthetic'] = False
            (source / 'report.json').write_text(json.dumps(report))
            with self.assertRaises(ValueError):
                runner.stage(source, source / 'dest', 'abc', 'business')


class PrerequisiteTests(unittest.TestCase):
    def test_exact_supported_synthetic_probe(self):
        self.assertFalse(prerequisite.verify('arm64', 'Xcode 27.1\nBuild version 27A9275\n',
            'iphoneos27.1 iphonesimulator27.1', {'runtimes': [{'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-0',
                                                           'version': '27.0', 'isAvailable': True}]}))

    def test_current_hosted_inventory_fails_explicitly(self):
        errors = prerequisite.verify('arm64', 'Xcode 26.6\nBuild version 17F113',
                                     'iphoneos26.5 iphonesimulator26.5', {'runtimes': []})
        self.assertEqual(len(errors), 3)
        self.assertIn('27A9275', errors[0])

    def test_wrong_architecture_and_unavailable_runtime(self):
        errors = prerequisite.verify('x86_64', 'Xcode 27.1\nBuild version 27A9275',
            'iphoneos27.1 iphonesimulator27.1', {'runtimes': [{'version': '27.0', 'isAvailable': False}]})
        self.assertEqual(len(errors), 2)


class SetupTests(unittest.TestCase):
    @staticmethod
    def finished(argv, **kwargs):
        if 'select' in argv:
            Path(argv[argv.index('--output') + 1]).write_text('{}')
        return subprocess.CompletedProcess(argv, 0, '')

    def test_routine_selects_once_and_stops_before_unexecuted_lanes(self):
        for paths, fail_at in [(['README.md'], None),
                               (['ios/Sources/TodayCore/AutonomyPolicy.swift'], 'build'),
                               (['ios/Sources/Features/FeatureToday/TaskActions.swift'], 'core-ui')]:
            with self.subTest(paths=paths), tempfile.TemporaryDirectory() as directory:
                selection = policy.select(paths)
                def select_command(argv, **kwargs):
                    Path(argv[argv.index('--output') + 1]).write_text(json.dumps(selection))
                    return subprocess.CompletedProcess(argv, 0, '')
                def lane_command(lane, prepared):
                    self.assertEqual(json.loads(prepared['selection']), selection)
                    return 1 if lane == fail_at else 0
                with (patch.dict(os.environ, {'RUNNER_TEMP': directory}),
                      patch.object(sys, 'argv', ['run.py', 'routine']),
                      patch.object(runner, 'execute', side_effect=select_command) as execute,
                      patch.object(runner, 'run_lane', side_effect=lane_command) as run):
                    self.assertEqual(runner.main(), int(fail_at is not None))
                self.assertEqual(execute.call_count, 1)
                expected = policy.routine_lanes(selection)
                if fail_at:
                    expected = expected[:expected.index(fail_at) + 1]
                self.assertEqual([call.args[0] for call in run.call_args_list], expected)

    def test_selection_failure_never_dispatches_checks(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'RUNNER_TEMP': directory}), patch.object(
                sys, 'argv', ['run.py', 'routine']), patch.object(runner, 'execute', return_value=
                subprocess.CompletedProcess([], 9, 'diff authority failed')), patch.object(runner, 'run_lane') as run:
            self.assertEqual(runner.main(), 9)
        run.assert_not_called()

    def test_batch_prepares_native_once_and_stops_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            sha = 'd' * 40
            report = {'sha': sha, 'lane': 'build', 'status': 'passed', 'executed': 1,
                      'failed': 0, 'cancelled': 0, 'missing': 0, 'synthetic': True}
            with (patch.dict(os.environ, {'GITHUB_SHA': sha, 'RUNNER_TEMP': directory}),
                  patch.object(sys, 'argv', ['run.py', 'build', 'integration', 'snapshots', 'core-ui']),
                  patch.object(runner.subprocess, 'check_output', return_value=sha),
                  patch.object(runner, 'producer_boundary'),
                  patch.object(runner, 'execute', side_effect=self.finished) as execute,
                  patch.object(runner, 'close_wrapper', return_value=report),
                  patch.object(runner, 'validate_report'), patch.object(runner, 'stage')):
                self.assertEqual(runner.main(), 0)
            commands = [call.args[0] for call in execute.call_args_list]
            self.assertEqual(commands.count(['./dev', 'generate']), 1)
            self.assertEqual(commands.count(['./dev', 'resolve']), 1)
            self.assertEqual(sum('select' in command for command in commands), 1)
            self.assertEqual([command[2] for command in commands if command[:2] == ['./dev', 'ci']],
                             ['build', 'integration', 'snapshots', 'core-ui'])
        with patch.object(runner, 'run_lane', return_value=1) as run, patch.object(
                sys, 'argv', ['run.py', 'build', 'integration']):
            self.assertEqual(runner.main(), 1)
            self.assertEqual(run.call_count, 1)

    def test_only_consumed_tools_and_dependencies_are_prepared(self):
        for lane in policy.LANES:
            with self.subTest(lane=lane), tempfile.TemporaryDirectory() as directory:
                sha = 'c' * 40
                report = {'sha': sha, 'lane': lane, 'status': 'passed', 'executed': 1,
                          'failed': 0, 'cancelled': 0, 'missing': 0, 'synthetic': True}
                with (patch.dict(os.environ, {'GITHUB_SHA': sha, 'RUNNER_TEMP': directory}),
                      patch.object(sys, 'argv', ['run.py', lane]),
                      patch.object(runner.subprocess, 'check_output', return_value=sha),
                      patch.object(runner, 'producer_boundary'),
                      patch.object(runner, 'execute', side_effect=self.finished) as execute,
                      patch.object(runner, 'close_wrapper', return_value=report),
                      patch.object(runner, 'stage')):
                    self.assertEqual(runner.main(), 0)
                commands = [call.args[0] for call in execute.call_args_list]
                prepared = [c for c in commands if c[:2] == ['./dev', 'bootstrap']]
                tools = {'format': ['swift-format'], 'lint': ['swiftlint', 'ruff', 'actionlint'],
                         'business': []}.get(lane, ['xcodegen'])
                self.assertEqual(prepared, [['./dev', 'bootstrap', *[
                    arg for name in tools for arg in ('--tool', name)]]] if tools else [])
                native = lane not in ('format', 'lint', 'business')
                for step in ('generate', 'resolve'):
                    self.assertEqual(['./dev', step] in commands, native)
                self.assertEqual(commands[-1][:3], ['./dev', 'ci', lane])

    def test_setup_failure_never_runs_or_passes_lane(self):
        with tempfile.TemporaryDirectory() as directory:
            sha = 'c' * 40
            failed = {'sha': sha, 'lane': 'build', 'status': 'failed', 'executed': 0,
                      'failed': 1, 'cancelled': 0, 'missing': 0, 'synthetic': True}
            with (patch.dict(os.environ, {'GITHUB_SHA': sha, 'RUNNER_TEMP': directory}),
                  patch.object(sys, 'argv', ['run.py', 'build']),
                  patch.object(runner.subprocess, 'check_output', return_value=sha),
                  patch.object(runner, 'producer_boundary'),
                  patch.object(runner, 'execute', return_value=subprocess.CompletedProcess([], 9, '')) as execute,
                  patch.object(runner, 'close_producer') as close,
                  patch.object(runner, 'close_wrapper', return_value=failed),
                  patch.object(runner, 'stage')):
                self.assertEqual(runner.main(), 9)
            self.assertEqual(execute.call_count, 1)
            self.assertEqual(close.call_args.args[1]['executed'], 0)


class WorkflowTests(unittest.TestCase):
    def test_release_protection_is_real(self):
        self.assertFalse(release_guard.protected({}))
        self.assertFalse(release_guard.protected({'protection_rules': [{'type': 'required_reviewers', 'reviewers': []}]}))
        rule = {'type': 'required_reviewers', 'reviewers': [{'reviewer': {'login': 'luworks'}}], 'prevent_self_review': True}
        self.assertTrue(release_guard.protected({'protection_rules': [rule]}))
        rule['prevent_self_review'] = False
        self.assertFalse(release_guard.protected({'protection_rules': [rule]}))


if __name__ == '__main__':
    unittest.main()
