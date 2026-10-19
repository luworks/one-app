"""Host-only native cache behavior using real product trees and synthetic Xcode."""
from contextlib import contextmanager
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.devtools import commands, core, xcode_tests  # noqa: E402 - standalone test import bootstrap

METHOD = 'TodayTests/StoreUpgradeTests/baselineStorePreservesAllFieldsAcrossReopenAndMutation'
CONTRACT = commands.testing_contract(ROOT)


class NativeProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='native provenance space ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'ios').mkdir()
        self.source = self.root / 'ios/Input.swift'
        self.source.write_text('source one')
        self.lock = self.root / 'ios/Package.resolved'
        self.lock.write_text('locked one')
        self.tools = patch.object(core, 'toolchain', return_value={'xcode': '27', 'sdk': '27.0'})
        self.tools.start()
        self.addCleanup(self.tools.stop)
        self.calls = []

    def fp(self, scheme='TodayTests', **options):
        return core.fingerprint(self.root, scheme=scheme, architecture='arm64', **options)

    def products(self, scheme='TodayTests', modern=True):
        directory = core.derived_data(self.root) / 'Build/Products'
        app = directory / ('Debug-iphonesimulator/' + scheme + '-Runner.app')
        bundle = app / ('PlugIns/' + scheme + '.xctest')
        bundle.mkdir(parents=True, exist_ok=True)
        (app / 'Runner').write_text('host binary')
        (bundle / 'Tests').write_text('test binary')
        (bundle / 'resource.txt').write_text('resource one')
        target = {'TestHostPath': '__TESTROOT__/Debug-iphonesimulator/' + scheme + '-Runner.app',
                  'TestBundlePath': '__TESTHOST__/PlugIns/' + scheme + '.xctest',
                  'DependentProductPaths': ['__TESTROOT__/Debug-iphonesimulator/' + scheme + '-Runner.app']}
        data = {'TestConfigurations': [{'TestTargets': [target]}]} if modern else {scheme: target}
        path = directory / (scheme + '_iphonesimulator27.0-arm64.xctestrun')
        path.write_bytes(plistlib.dumps(data))
        return path, app, bundle

    def invoke(self, command):
        self.calls.append(command)
        self.products(command[command.index('-scheme') + 1])
        return SimpleNamespace(returncode=0, reason='exited', log=self.root / 'synthetic.log')

    def ensure(self, scheme='TodayTests'):
        return core.ensure_test_products(self.root, scheme, self.invoke)

    def test_scheme_and_build_environment_invalidate_source_identity(self):
        before = self.fp()
        self.assertNotEqual(before, self.fp('TodaySnapshotTests'))
        for options in ({'sdk': 'iphoneos'}, {'configuration': 'Release'}):
            self.assertNotEqual(before, self.fp(**options))
        with patch.object(core, 'toolchain', return_value={'xcode': '28', 'sdk': '28.0'}):
            self.assertNotEqual(before, self.fp())
        self.assertNotEqual(before, core.fingerprint(self.root, scheme='TodayTests', architecture='x86_64'))
        self.assertEqual(core.fingerprint(self.root)['inputs']['scheme'], 'Today')
        with self.assertRaises(ValueError):
            core.fingerprint(self.root, scheme='')

    def test_unchanged_reuses_but_dirty_source_lock_and_resource_rebuild(self):
        first = self.ensure()
        self.assertEqual(self.ensure(), first)
        self.assertEqual(len(self.calls), 1)
        for path in (self.source, self.lock, first.parent / 'Debug-iphonesimulator/TodayTests-Runner.app/PlugIns/TodayTests.xctest/resource.txt'):
            path.write_text(path.read_text() + ' changed')
            self.ensure()
        self.assertEqual(len(self.calls), 4)
        self.assertTrue(all(command[1] == 'build-for-testing' for command in self.calls))
        self.assertEqual(self.calls[0][self.calls[0].index('-derivedDataPath') + 1], str(core.derived_data(self.root)))

    def test_whole_host_bundle_and_xctestrun_are_guarded(self):
        path = self.ensure()
        current = self.fp()
        host = path.parent / 'Debug-iphonesimulator/TodayTests-Runner.app'
        extra = host / 'new resource'
        extra.write_text('added')
        self.assertFalse(core.provenance(self.root, current, kind='build-for-testing')['valid'])
        extra.unlink()
        self.assertTrue(core.provenance(self.root, current, kind='build-for-testing')['valid'])
        path.write_bytes(b'invalid plist')
        self.assertFalse(core.provenance(self.root, current, kind='build-for-testing')['valid'])

    def test_separate_schemes_and_build_kinds_cannot_substitute(self):
        one = self.ensure()
        two = self.ensure('TodaySnapshotTests')
        self.assertNotEqual(one, two)
        self.assertTrue(core.provenance(self.root, self.fp(), kind='build-for-testing')['valid'])
        self.assertFalse(core.provenance(self.root, self.fp())['valid'])
        self.assertFalse(core.provenance(self.root, self.fp(), kind='build-for-testing', xctestrun=two)['valid'])
        with self.assertRaisesRegex(ValueError, 'scheme'):
            core.record_build(self.root, self.fp(), [two], returncode=0, kind='build-for-testing', xctestrun=two)

    def test_old_schema_and_stale_publication_fail_closed(self):
        path, _, _ = self.products(modern=False)
        current = self.fp()
        core.record_build(self.root, current, [path], returncode=0, kind='build-for-testing', xctestrun=path)
        self.assertTrue(core.provenance(self.root, current, kind='build-for-testing')['valid'])
        legacy = {'sha256': 'old', 'inputs': {'schema': 1}}
        self.assertFalse(core.provenance(self.root, legacy)['valid'])
        self.source.write_text('changed during build')
        with self.assertRaisesRegex(ValueError, 'Source changed'):
            core.record_build(self.root, current, [path], returncode=0, kind='build-for-testing', xctestrun=path)

    def test_foreign_and_symlink_products_are_rejected_without_deleting_them(self):
        path, _, bundle = self.products()
        foreign = self.root / 'foreign tests.xctest'
        foreign.mkdir()
        marker = foreign / 'Tests'
        marker.write_text('foreign binary')
        path.write_bytes(plistlib.dumps({'TodayTests': {'TestBundlePath': str(foreign)}}))
        with self.assertRaisesRegex(ValueError, 'Foreign'):
            core.record_build(self.root, self.fp(), [path], returncode=0, kind='build-for-testing', xctestrun=path)
        self.assertEqual(marker.read_text(), 'foreign binary')
        path, _, bundle = self.products()
        (bundle / 'foreign link').symlink_to(marker)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            core.record_build(self.root, self.fp(), [path], returncode=0, kind='build-for-testing', xctestrun=path)
        self.assertEqual(marker.read_text(), 'foreign binary')
        self.assertFalse(core.provenance(self.root / 'other worktree', self.fp())['valid'])

    def test_symlinked_derived_data_cannot_turn_into_shared_cache(self):
        foreign = self.root / 'foreign cache'
        foreign.mkdir()
        dd = core.derived_data(self.root)
        dd.parent.mkdir(parents=True)
        dd.symlink_to(foreign, target_is_directory=True)
        product = foreign / 'app binary'
        product.write_text('foreign bytes')
        with self.assertRaisesRegex(ValueError, 'Symlink derived-data'):
            core.record_build(self.root, self.fp(), [dd / product.name], returncode=0)
        self.assertEqual(product.read_text(), 'foreign bytes')

    def test_missing_ambiguous_and_empty_products_do_not_publish(self):
        for mode in ('missing', 'ambiguous', 'empty'):
            with self.subTest(mode=mode):
                scheme = 'Scheme' + mode
                def invoke(command):
                    if mode != 'missing':
                        path, app, bundle = self.products(scheme)
                        if mode == 'ambiguous':
                            path.with_name(scheme + '_other.xctestrun').write_bytes(path.read_bytes())
                        else:
                            (bundle / 'Tests').unlink()
                            (bundle / 'resource.txt').unlink()
                    return SimpleNamespace(returncode=0, reason='exited')
                with self.assertRaises(ValueError):
                    core.ensure_test_products(self.root, scheme, invoke)
                self.assertFalse(core.provenance(self.root, self.fp(scheme), kind='build-for-testing')['valid'])

    def test_failed_timeout_and_cancelled_builds_never_authorize_test_reuse(self):
        for code, reason in ((65, 'exited'), (124, 'timeout'), (130, 'cancelled')):
            with self.subTest(reason=reason):
                def invoke(command):
                    self.products()
                    return SimpleNamespace(returncode=code, reason=reason, log=self.root / 'failed.log')
                with self.assertRaises(core.NativeBuildError) as caught:
                    core.ensure_test_products(self.root, 'TodayTests', invoke)
                self.assertEqual(caught.exception.returncode, code)
                self.assertFalse(core.provenance(self.root, self.fp(), kind='build-for-testing')['valid'])

    def test_source_change_during_build_rejects_products(self):
        def invoke(command):
            result = self.invoke(command)
            self.source.write_text('source changed in flight')
            return result
        with self.assertRaisesRegex(ValueError, 'changed during build'):
            core.ensure_test_products(self.root, 'TodayTests', invoke)
        self.assertFalse(core.provenance(self.root, self.fp(), kind='build-for-testing')['valid'])

    def run_adapter(self, *, leaves=None, parser_error=False, test_code=0, change_source=False, build_code=0):
        journal = Mock()
        output = self.root / ('evidence ' + str(len(self.calls)))
        output.mkdir()
        evidence = SimpleNamespace(path=output / 'initial.log', session='synthetic', journal=journal,
                                   record=Mock(), close=Mock())

        @contextmanager
        def lock(*args):
            yield

        def process(argv, *, cwd, evidence, timeout):
            self.calls.append(argv)
            content, code = '', 0
            if argv[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                content = json.dumps({'devices': {xcode_tests.RUNTIME: []}})
            elif argv[:3] == ['xcrun', 'simctl', 'create']:
                content = '00000000-0000-0000-0000-000000000001'
            elif argv[:2] == ['xcodebuild', 'build-for-testing']:
                self.products()
                code = build_code
            elif argv[:2] == ['xcodebuild', 'test-without-building']:
                bundle = Path(argv[argv.index('-resultBundlePath') + 1])
                bundle.mkdir()
                (bundle / 'raw evidence').write_text('complete bundle')
                code = test_code
                if change_source:
                    self.source.write_text('changed during tests')
            elif argv[:3] == ['xcrun', 'xcresulttool', 'get']:
                content = ('invalid JSON' if parser_error else json.dumps({'failedTests': 0} if 'summary' in argv else
                    {'testNodes': [{'nodeType': 'Test Case', 'nodeIdentifier': value, 'result': 'Passed'}
                                   for value in ([METHOD] if leaves is None else leaves)]}))
            evidence.path.write_text(content)
            return SimpleNamespace(returncode=code, reason='exited' if code != 124 else 'timeout', log=evidence.path)

        source_inventory = CONTRACT.inventory(ROOT)
        with patch.object(CONTRACT, 'inventory', return_value=source_inventory), \
                patch.multiple(xcode_tests, host_lock=lock, dd_lock=lock, ResourceLock=lock), \
                patch.object(xcode_tests, 'Evidence', return_value=evidence), \
                patch.object(xcode_tests, 'run_process', side_effect=process), \
                patch.object(xcode_tests, 'selected', return_value={'unit': [METHOD], 'integration': [METHOD]}), \
                patch('scripts.devtools.resolve.locked_arguments', return_value=['-disableAutomaticPackageResolution']):
            code = xcode_tests.run(self.root, CONTRACT, ['ios-unit', 'integration'], reuse=True)
        reports = list(output.rglob('*.report.json'))
        return code, [json.loads(path.read_text()) for path in reports], journal

    def test_adapter_builds_once_then_runs_without_building_with_authoritative_reports(self):
        code, reports, journal = self.run_adapter()
        self.assertEqual(code, 0)
        self.assertEqual(reports[0]['status'], 'passed')
        self.assertGreaterEqual(journal.artifact.call_count, 2)
        self.assertEqual(self.run_adapter()[0], 0)
        self.assertEqual(sum(c[:2] == ['xcodebuild', 'build-for-testing'] for c in self.calls), 1)
        tests = [c for c in self.calls if c[:2] == ['xcodebuild', 'test-without-building']]
        self.assertEqual(len(tests), 2)
        self.assertEqual(tests[0].count('-only-testing:' + METHOD + '()'), 1)
        self.assertIn('-xctestrun', tests[0])
        build_index = next(i for i, c in enumerate(self.calls) if c[:2] == ['xcodebuild', 'build-for-testing'])
        ready_index = next(i for i, c in enumerate(self.calls) if c[:3] == ['xcrun', 'simctl', 'bootstatus'])
        test_index = next(i for i, c in enumerate(self.calls) if c[:2] == ['xcodebuild', 'test-without-building'])
        self.assertLess(build_index, ready_index)
        self.assertLess(ready_index, test_index)
        self.assertEqual(self.calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])

    def test_adapter_zero_parser_timeout_and_source_changes_stay_failed(self):
        for options in ({'leaves': []}, {'parser_error': True}, {'test_code': 124}, {'change_source': True}):
            with self.subTest(options=options):
                code, reports, _ = self.run_adapter(**options)
                self.assertNotEqual(code, 0)
                self.assertEqual(reports[0]['status'], 'failed')
                self.assertEqual(self.calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])

    def test_adapter_failed_build_never_runs_tests_and_preserves_exit(self):
        code, reports, _ = self.run_adapter(build_code=130)
        self.assertEqual(code, 130)
        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0]['status'], 'failed')
        self.assertEqual(reports[0]['executed_count'], 0)
        self.assertIn('native_build_exit:130', reports[0]['errors'])
        self.assertFalse(any(c[:2] == ['xcodebuild', 'test-without-building'] for c in self.calls))
        self.assertEqual(self.calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])

    def test_adapter_build_timeout_retains_failure_receipt_without_test_or_ready_wait(self):
        code, reports, _ = self.run_adapter(build_code=124)
        self.assertEqual(code, 124)
        self.assertEqual(reports[0]['exit_code'], 124)
        self.assertIn('native_build_exit:124', reports[0]['errors'])
        self.assertIn('log=', reports[0]['build_error'])
        self.assertFalse(any(c[:3] == ['xcrun', 'simctl', 'bootstatus'] for c in self.calls))
        self.assertFalse(any(c[:2] == ['xcodebuild', 'test-without-building'] for c in self.calls))
        self.assertEqual(self.calls[-1][:3], ['xcrun', 'simctl', 'shutdown'])


if __name__ == '__main__':
    unittest.main()
