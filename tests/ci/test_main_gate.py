"""Synthetic gate regressions. No network, native build, simulator or installation."""
import copy
import io
import json
import importlib.util
import plistlib
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.ci import main_gate as gate, policy  # noqa: E402


class MainSelectionTests(unittest.TestCase):
    def test_main_uses_fixed_small_native_selection_and_pr_stays_lean(self):
        changed = ['ios/Sources/Features/FeatureToday/DayAgenda.swift']
        selected = policy.main_selection(policy.select(changed))
        source = {'ui': [], 'integration': []}
        with patch('scripts.testing.contract.expand', side_effect=lambda ids, source, kind: list(ids)):
            self.assertEqual(policy.execution_selection(selected, source, 'core-ui', ['whole suite']), list(policy.MAIN_UI))
            self.assertEqual(policy.execution_selection(selected, source, 'integration', ['whole suite']), list(policy.MAIN_INTEGRATION))
        self.assertEqual(policy.main_lanes(selected), ['format', 'lint', 'business', 'build', 'integration', 'core-ui'])
        self.assertNotIn('integration', policy.routine_lanes(policy.select(changed)))
        docs = policy.main_selection(policy.select(['ios/README.md']))
        self.assertEqual(policy.main_lanes(docs), ['format', 'lint'])
        for path in ('ios/Package.swift', '.github/workflows/today.yml'):
            self.assertIn('integration', policy.main_lanes(policy.main_selection(policy.select([path]))))
            self.assertIn('snapshots', policy.routine_lanes(policy.select([path])))

    def test_missing_critical_source_leaf_blocks_instead_of_using_mock(self):
        with self.assertRaisesRegex(ValueError, 'Unknown selection'):
            policy.execution_selection(policy.main_selection(policy.select(['ios/Package.swift'])),
                                       {'ui': []}, 'core-ui', ['empty Mock'])


class MainInstallTests(unittest.TestCase):
    def setUp(self):
        self.sha, self.tree = 'a' * 40, 'b' * 40
        self.tools = {'xcode': {'ProductBuildVersion': '27A9275'}, 'sdks': {'iPhoneSimulator27.1.sdk': 'c' * 64}}
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.args = SimpleNamespace(commit=self.sha, main_run='42', build_receipt=self.root / 'build.json')
        self.product = {n: {'bundle_id': b, 'executable_sha256': 'd' * 64, 'info_sha256': 'e' * 64}
                        for n, b in gate.PRODUCTS.items()}
        self.receipt = {'schema': 1, 'profile': policy.MAIN_PROFILE, 'status': 'passed', 'sha': self.sha,
                        'tree': self.tree, 'event': 'push', 'ref': 'refs/heads/main', 'run_id': '42',
                        'run_attempt': '1', 'toolchain': self.tools, 'simulator_products': self.product, 'lanes': {}}
        for lane in ('format', 'lint', 'business', 'build', 'integration', 'core-ui'):
            record = {'executed': 1, 'source_sha256': 'd' * 64, 'report_sha256': 'e' * 64}
            if lane in ('business', 'integration', 'core-ui'):
                record['tests'] = self.leaf_report([lane + '/test'])
            self.receipt['lanes'][lane] = record
        self.build = {'source': self.sha, 'tree': self.tree, 'source_after': self.sha, 'dirty_after': '',
                      'exit': 0, 'toolchain': self.tools, 'signing_changes': False,
                      'automatic_provisioning_updates': False,
                      'app': str(self.root / 'Debug-iphoneos/One.app'), 'product_identity': self.product}
        app = Path(self.build['app'])
        app.mkdir(parents=True)
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleSupportedPlatforms': ['iPhoneOS']}))
        self.info = {'head_sha': self.sha, 'head_branch': 'main', 'event': 'push',
                     'path': '.github/workflows/today.yml', 'status': 'completed', 'conclusion': 'success', 'run_attempt': 1}
        self.main_sha = self.sha
        self.calls = []
        self.expand = patch.object(gate.contract, 'expand', side_effect=lambda ids, source, kind: [
            ('core-ui' if kind == 'ui' else 'integration') + '/test'])
        self.expand.start()
        self.addCleanup(self.expand.stop)

    def leaf_report(self, expected):
        return {'expected': expected, 'expected_count': len(expected), 'executed_count': len(expected),
                'exit_code': 0, 'status': 'passed',
                'attempts': [{'test': t, 'status': 'passed', 'source': 'xcresult', 'reason': ''} for t in expected]}

    def github(self, argv, root):
        path = argv[-1]
        self.calls.append(path)
        if path.endswith('commits/main'):
            return json.dumps({'sha': self.main_sha}).encode()
        if path.endswith('/42'):
            return json.dumps(self.info).encode()
        if '/42/artifacts?' in path:
            return json.dumps({'artifacts': [{'id': 51, 'name': 'today-main-acceptance-' + self.sha + '-1',
                                              'expired': False, 'size_in_bytes': 2000}]}).encode()
        if path.endswith('/51/zip'):
            output = io.BytesIO()
            with zipfile.ZipFile(output, 'w') as z:
                z.writestr('today-artifacts-main-acceptance/main-acceptance.json', json.dumps(self.receipt))
            return output.getvalue()
        raise AssertionError(path)

    def check(self):
        self.args.build_receipt.write_text(json.dumps(self.build))
        with (patch.object(gate, 'probe', side_effect=lambda argv, root: '' if 'status' in argv else self.tree if 'HEAD^{tree}' in argv else self.sha),
              patch.object(gate, 'tool_identity', return_value=self.tools),
              patch.object(gate, 'product_identity', return_value=self.product),
              patch.object(gate.contract, 'inventory', return_value={})):
            return gate.check_install(self.root, self.args, self.github)

    def test_sealer_requires_real_completed_main_leaves_and_never_publishes_failed_report(self):
        temporary = self.root / 'runner'
        temporary.mkdir()
        for lane, record in self.receipt['lanes'].items():
            folder = temporary / ('today-artifacts-' + lane)
            folder.mkdir()
            report = {'sha': self.sha, 'lane': lane, 'status': 'passed', 'executed': 1,
                      'failed': 0, 'cancelled': 0, 'missing': 0, 'errors': [], 'synthetic': True,
                      'source_sha256': 'c' * 64}
            (folder / 'report.json').write_text(json.dumps(report))
            selected = {'profile': policy.MAIN_PROFILE}
            if 'tests' in record:
                selected['execution'] = {'selected': record['tests']['expected']}
                (folder / 'test-report.json').write_text(json.dumps(record['tests']))
            (folder / 'accepted-selection.json').write_text(json.dumps(selected))
        env = {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/main',
               'GITHUB_SHA': self.sha, 'GITHUB_RUN_ID': '42', 'GITHUB_RUN_ATTEMPT': '1'}
        lanes = list(self.receipt['lanes'])
        def probe(argv, root):
            return '' if 'status' in argv else self.tree if 'HEAD^{tree}' in argv else self.sha
        with (patch.dict(os.environ, env), patch.object(gate, 'probe', side_effect=probe),
              patch.object(gate, 'tool_identity', return_value=self.tools),
              patch.object(gate, 'product_identity', return_value=self.product),
              patch.object(gate.contract, 'inventory', return_value={})):
            broken = temporary / 'today-artifacts-core-ui/test-report.json'
            valid = broken.read_bytes()
            bad = self.leaf_report(['core-ui/test'])
            bad['attempts'][0]['status'] = 'failed'
            broken.write_text(json.dumps(bad))
            with self.assertRaises(ValueError):
                gate.seal_acceptance(self.root, temporary, lanes)
            self.assertFalse((temporary / 'today-artifacts-main-acceptance').exists())
            broken.write_bytes(valid)
            gate.seal_acceptance(self.root, temporary, lanes)
        sealed = json.loads((temporary / 'today-artifacts-main-acceptance/main-acceptance.json').read_text())
        self.assertEqual(sealed['sha'], self.sha)
        self.assertEqual(sealed['physical_device'], 'not_tested')

    def test_existing_preflight_install_mode_blocks_without_ci_and_does_not_invoke_archive_setup(self):
        spec = importlib.util.spec_from_file_location('gate_release', ROOT / 'scripts/release/release.py')
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        self.args.for_install = True
        self.args.version, self.args.build = '1.0', '42'
        with (patch.object(release, 'check_git'), patch.object(release, 'check_tools') as archive_tools,
              patch.object(gate, 'check_install', side_effect=ValueError('offline'))):
            result = release.local_preflight(self.root, self.args).data
        self.assertEqual(result['status'], 'blocked')
        self.assertEqual(result['checks']['main_usability']['status'], 'blocked')
        archive_tools.assert_not_called()

    def test_exact_main_positive_does_not_install_and_rechecks_main(self):
        self.assertEqual(self.check()['sha'], self.sha)
        self.assertEqual(sum(p.endswith('commits/main') for p in self.calls), 2)
        self.assertTrue(all(p.startswith('repos/luworks/one-app/') for p in self.calls))

    def test_branch_old_main_running_failed_and_wrong_attempt_block(self):
        for field, value in [('head_sha', 'f' * 40), ('event', 'pull_request'), ('head_branch', 'feature'),
                             ('status', 'in_progress'), ('conclusion', 'failure'), ('path', 'other.yml')]:
            with self.subTest(field=field), patch.dict(self.info, {field: value}), self.assertRaises(ValueError):
                self.check()
        self.main_sha = 'f' * 40
        with self.assertRaisesRegex(ValueError, 'current_main_mismatch'):
            self.check()
        self.main_sha = self.sha
        self.receipt['run_attempt'] = '0'
        with self.assertRaisesRegex(ValueError, 'provenance_mismatch'):
            self.check()

    def test_missing_or_unexpected_skipped_failed_and_zero_leaf_block(self):
        for status in ('skipped', 'failed', 'cancelled', 'pending'):
            report = copy.deepcopy(self.receipt)
            self.receipt['lanes']['core-ui']['tests']['attempts'][0]['status'] = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.check()
            self.receipt = report
        self.receipt['lanes']['core-ui']['tests']['attempts'] = []
        with self.assertRaises(ValueError):
            self.check()

    def test_device_source_toolchain_or_product_drift_blocks(self):
        for field, value in [('source', 'f' * 40), ('source_after', 'f' * 40), ('tree', 'f' * 40),
                             ('dirty_after', ' M source.swift'), ('exit', 124), ('toolchain', {}),
                             ('product_identity', {}), ('signing_changes', True), ('app', '/tmp/Debug-iphonesimulator/One.app')]:
            with self.subTest(field=field), patch.dict(self.build, {field: value}), self.assertRaises(ValueError):
                self.check()

    def test_missing_artifact_offline_and_main_race_never_pass(self):
        with patch.object(self, 'github', side_effect=OSError('offline')), self.assertRaises(OSError):
            self.check()
        original = self.github
        def change_main(argv, root):
            data = original(argv, root)
            if argv[-1].endswith('/51/zip'):
                self.main_sha = 'f' * 40
            return data
        with patch.object(self, 'github', side_effect=change_main), self.assertRaisesRegex(ValueError, 'current_main_mismatch'):
            self.check()


if __name__ == '__main__':
    unittest.main()
