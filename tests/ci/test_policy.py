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
import re  # noqa: E402 - standalone test import bootstrap
import subprocess  # noqa: E402 - standalone test import bootstrap

spec = importlib.util.spec_from_file_location('ci_run', ROOT / 'scripts/ci/run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.nodes = {
            'domain': {'paths': ['ios/Domain'], 'dependencies': []},
            'calendar': {'paths': ['ios/Calendar'], 'dependencies': ['domain']},
            'clock': {'paths': ['ios/Clock'], 'dependencies': []},
            'app': {'paths': ['ios/App'], 'dependencies': ['calendar', 'clock']}}

    def test_reverse_transitive_closure(self):
        result = policy.select(['ios/Domain/Date.swift'], self.nodes)
        self.assertEqual(result['targets'], ['app', 'calendar', 'domain'])
        self.assertFalse(result['all_targets'])

    def test_unrelated_feature_excluded(self):
        self.assertEqual(policy.select(['ios/Clock/Timer.swift'], self.nodes)['targets'], ['app', 'clock'])

    def test_wide_fallbacks(self):
        for path in ('ios/Shared/Foo.swift', 'ios/Models.swift', 'ios/project.yml',
                     'ios/Package.swift', '.github/workflows/today.yml', 'new/unknown.swift',
                     'ios/Foo.xcconfig', 'ios/Packages/TodayShared/File.swift', 'ios/App/Info.plist',
                     'ios/App/App.entitlements', 'tests/fixtures/data.json'):
            with self.subTest(path=path):
                self.assertTrue(policy.select([path], self.nodes)['all_targets'])

    def test_empty_diff_is_wide(self):
        self.assertTrue(policy.select([], self.nodes)['all_targets'])

    def test_docs_only(self):
        result = policy.select(['docs/notes.md'], self.nodes)
        self.assertEqual(result['targets'], [])
        self.assertFalse(result['snapshots'])

    def test_graph_missing_reason(self):
        self.assertTrue(policy.select(['ios/Domain/File.swift'], {}, 'missing graph')['all_targets'])

    def test_actual_project_and_package_edges(self):
        project = {'targets': {'App': {'sources': ['App'], 'dependencies': [{'target': 'Widget'}, {'package': 'Domain'}]},
                               'Widget': {'sources': ['Widget'], 'dependencies': [{'package': 'Domain'}]}}}
        package = {'targets': [{'name': 'Domain', 'dependencies': []},
                               {'name': 'DomainTests', 'dependencies': [{'byName': ['Domain', None]}]}],
                   'products': [{'name': 'Domain', 'targets': ['Domain']}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ios/Domain').mkdir(parents=True)
            (root / 'ios/Domain/Package.swift').touch()
            (root / 'ios/project.yml').touch()
            with patch.object(policy, 'capture', side_effect=[json.dumps(project), json.dumps(package)]) as probe:
                nodes = policy.graph(root)
            self.assertIn('dump-package', probe.call_args_list[1].args[0])
            self.assertEqual(policy.select(['ios/Domain/Sources/A.swift'], nodes)['targets'],
                             ['ios/Domain:Domain', 'ios/Domain:DomainTests', 'xcode:App', 'xcode:Widget'])

    def test_missing_project_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'graph incomplete'):
                policy.graph(Path(directory))

    def test_unsupported_xcode_include_falls_wide(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ios').mkdir()
            (root / 'ios/project.yml').touch()
            with patch.object(policy, 'capture', return_value='{"include": ["other.yml"]}'):
                with self.assertRaisesRegex(ValueError, 'expanded graph'):
                    policy.graph(root)


class AggregateTests(unittest.TestCase):
    def needs(self, event='pull_request', ref='refs/pull/1/merge'):
        return {name: {'result': 'success' if name not in policy.LANES or policy.expected(event, ref, name) else 'skipped'}
                for name in ('helpers', 'prerequisite', *policy.LANES)}

    def test_pr_and_merge_queue_pass(self):
        for event in ('pull_request', 'merge_group'):
            self.assertEqual(policy.aggregate(self.needs(event), event, 'refs/pull/1/merge'), [])

    def test_main_release_required(self):
        needs = self.needs('push', 'refs/heads/main')
        self.assertFalse(policy.aggregate(needs, 'push', 'refs/heads/main'))
        needs['release']['result'] = 'skipped'
        self.assertTrue(policy.aggregate(needs, 'push', 'refs/heads/main'))

    def test_all_failure_states_rejected(self):
        for state in ('failure', 'cancelled', 'skipped', None, ''):
            for name in ('helpers', 'prerequisite', 'format', 'business', 'snapshots'):
                needs = self.needs()
                needs[name]['result'] = state
                self.assertTrue(policy.aggregate(needs, 'pull_request', 'refs/pull/1/merge'), (name, state))

    def test_missing_even_optional_job_rejected(self):
        for name in self.needs():
            needs = self.needs()
            del needs[name]
            self.assertTrue(policy.aggregate(needs, 'pull_request', 'refs/pull/1/merge'), name)

    def test_manual_selected_lane_cannot_skip(self):
        with patch.dict(os.environ, {'MANUAL_LANE': 'sanitizer'}):
            needs = self.needs('workflow_dispatch', 'refs/heads/main')
            self.assertFalse(policy.aggregate(needs, 'workflow_dispatch', 'refs/heads/main'))
            needs['sanitizer']['result'] = 'skipped'
            self.assertTrue(policy.aggregate(needs, 'workflow_dispatch', 'refs/heads/main'))

    def test_cancelled_exempt_job_still_fails(self):
        needs = self.needs()
        needs['extended']['result'] = 'cancelled'
        self.assertTrue(policy.aggregate(needs, 'pull_request', 'refs/pull/1/merge'))


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
                      patch.object(runner, 'execute', side_effect=lambda argv, **kw:
                                   subprocess.CompletedProcess(argv, 0, '')) as execute,
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
    def test_every_job_is_aggregated(self):
        text = (ROOT / '.github/workflows/today.yml').read_text()
        jobs = set(re.findall(r'^  ([a-z][a-z-]+):$', text.split('jobs:', 1)[1], re.M))
        expected = {'helpers', 'prerequisite', *policy.LANES}
        self.assertEqual(jobs, expected | {'today-required'})
        aggregate = text.split('  today-required:', 1)[1]
        needs = re.search(r'needs: \[(.*?)\]', aggregate).group(1).split(', ')
        self.assertEqual(set(needs), expected)
        self.assertIn('if: always()', aggregate)
        self.assertNotIn('paths:', text)
        self.assertNotIn('pull_request_target:', text)

    def test_release_protection_is_real(self):
        self.assertFalse(release_guard.protected({}))
        self.assertFalse(release_guard.protected({'protection_rules': [{'type': 'required_reviewers', 'reviewers': []}]}))
        rule = {'type': 'required_reviewers', 'reviewers': [{'reviewer': {'login': 'luworks'}}], 'prevent_self_review': True}
        self.assertTrue(release_guard.protected({'protection_rules': [rule]}))
        rule['prevent_self_review'] = False
        self.assertFalse(release_guard.protected({'protection_rules': [rule]}))


if __name__ == '__main__':
    unittest.main()
