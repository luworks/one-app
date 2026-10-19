"""Closed producer/wrapper host fixtures, with no native tools or live bundles."""
import contextlib
import io
import json
import os
import shutil
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.ci import run as producer  # noqa: E402
from scripts.devtools import ci_adapter as adapter  # noqa: E402
from scripts.devtools.core import canonical_root  # noqa: E402

SHA = 'c' * 40


class ProducerTests(unittest.TestCase):
    def setUp(self):
        evidence = canonical_root(ROOT) / 'tests/results/reconstruction'
        evidence.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='ci-wrapper-fixture-', dir=evidence)
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.output = self.base / 'today-business'
        self.output.mkdir()
        self.env = {
            'GITHUB_ACTIONS': 'true', 'GITHUB_WORKFLOW': 'Today CI',
            'TODAY_CI_SYNTHETIC': '1', 'GITHUB_EVENT_NAME': 'pull_request',
            'GITHUB_SHA': SHA, 'RUNNER_TEMP': str(self.base),
        }
        environment = patch.dict(os.environ, self.env, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        self.report = {'sha': SHA, 'lane': 'business', 'synthetic': True,
                       'status': 'passed', 'executed': 1, 'failed': 0, 'cancelled': 0, 'missing': 0}

    def write(self, name, data):
        path = self.output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def close(self):
        producer.close_producer(self.output, self.report, roots=('command.log', 'native'))

    def test_closed_adapter_wrapper_stage_round_trip_and_hashes(self):
        original = b'\x00\xffhidden binary'
        self.write('native/TodayTests.xcresult/.hidden/store', original)
        self.write('native/TodayTests.xcresult/info.json', b'{"user":"/Users/synthetic/fixture"}')
        self.write('native/shutdown.log', b'shutdown finished\n')
        self.write('command.log', b'first failed; retry passed /Users/synthetic/fixture\n')
        self.write('private.sqlite', b'never read or inventoried')
        self.close()
        before = (self.output / 'command.log').read_bytes()
        producer.close_wrapper(self.output, SHA, 'business', 'wrapper finished\n')
        self.assertEqual((self.output / 'command.log').read_bytes(), before)
        self.assertNotIn(b'/Users/synthetic', before)
        self.assertEqual((self.output / 'native/TodayTests.xcresult/.hidden/store').read_bytes(), original)
        report = json.loads((self.output / 'report.json').read_text())
        receipt = report['artifact_provenance']
        self.assertEqual((receipt['sha'], receipt['lane'], receipt['run_id']), (SHA, 'business', self.output.name))
        self.assertNotIn('report.json', [e['path'] for e in receipt['files']])
        for entry in receipt['files']:
            self.assertEqual(producer.artifact_digest((self.output / entry['path']).read_bytes()),
                             {k: entry[k] for k in ('bytes', 'sha256')})
        target = self.base / 'published'
        producer.stage(self.output, target, SHA, 'business')
        self.assertFalse((target / 'private.sqlite').exists())
        self.assertEqual((target / 'native/TodayTests.xcresult/.hidden/store').read_bytes(), original)
        self.assertEqual((target / 'wrapper-command.log').read_text(), 'wrapper finished\n')

    def test_boundary_requires_workflow_context_exact_sha_lane_and_directory(self):
        for key, value in [('GITHUB_ACTIONS', 'false'), ('GITHUB_WORKFLOW', 'Other'),
                           ('TODAY_CI_SYNTHETIC', '0'), ('GITHUB_EVENT_NAME', 'pull_request_target'),
                           ('GITHUB_SHA', 'abc'), ('RUNNER_TEMP', str(self.base / 'other'))]:
            with self.subTest(key=key), patch.dict(os.environ, {key: value}):
                with self.assertRaisesRegex(ValueError, 'boundary'):
                    self.close()
        self.assertFalse((self.output / 'report.json').exists())

    def test_environment_secrets_reject_before_runner_and_never_echo_values(self):
        self.output.rmdir()
        root = self.base / 'repo'
        root.mkdir()
        value = 'sensitive-fixture-value'
        with patch.dict(os.environ, {'DEPLOY_API_KEY': value}), patch.object(adapter.commands, 'execute') as run:
            with contextlib.redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(adapter._main(root, 'business', selection=self.base / 'none', output=self.output,
                                              sha=SHA, synthetic=True, no_distribute=True), 1)
        run.assert_not_called()
        report = json.loads((self.output / 'report.json').read_text())
        self.assertNotIn('artifact_provenance', report)
        self.assertNotIn(value, json.dumps(report) + stderr.getvalue())
        self.assertIn('secret-bearing environment rejected', str(report['errors']))

    def test_candidate_secrets_reject_without_rewriting_bundle_or_receipt(self):
        for name in ('command.log', 'native/TodayTests.xcresult/.hidden'):
            with self.subTest(name=name):
                path = self.write(name, b'password=fixture-secret')
                with self.assertRaisesRegex(ValueError, 'blocking secret'):
                    self.close()
                self.assertEqual(path.read_bytes(), b'password=fixture-secret')
                self.assertFalse((self.output / 'report.json').exists())
                path.unlink()

    def test_wrapper_secret_rejection_retains_only_redacted_diagnostics(self):
        self.close()
        receipt = (self.output / 'report.json').read_bytes()
        with self.assertRaisesRegex(ValueError, 'blocking secret'):
            producer.close_wrapper(self.output, SHA, 'business', 'token=fixture-credential')
        self.assertNotIn('fixture-credential', (self.output / 'wrapper-command.log').read_text())
        self.assertEqual((self.output / 'report.json').read_bytes(), receipt)

    def test_wrapper_rejects_mutation_and_does_not_reseal_it(self):
        self.write('command.log', b'closed\n')
        self.close()
        receipt = (self.output / 'report.json').read_bytes()
        self.write('command.log', b'late writer\n')
        with self.assertRaisesRegex(ValueError, 'bytes changed'):
            producer.close_wrapper(self.output, SHA, 'business', 'wrapper\n')
        self.assertEqual((self.output / 'report.json').read_bytes(), receipt)
        self.assertEqual((self.output / 'wrapper-command.log').read_text(), 'wrapper\n')

    def test_generated_roots_reject_symlinks_and_empty_bundles(self):
        bundle = self.output / 'native/TodayTests.xcresult'
        bundle.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, 'empty producer bundle'):
            self.close()
        leak = bundle / 'leak'
        leak.symlink_to(self.base / 'private')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.close()
        self.assertFalse((self.output / 'report.json').exists())

    def test_adapter_closes_only_after_execution_and_retains_failed_attempt(self):
        self.output.rmdir()
        root = self.base / 'repo'
        root.mkdir()
        selection = self.base / 'selection.json'
        selection.write_text(json.dumps({'version': 1, 'mode': 'wide', 'reason': 'fixture',
                                         'changed': [], 'targets': [], 'all_targets': True, 'snapshots': True}))

        def run(*args, **kwargs):
            self.assertFalse((self.output / 'report.json').exists())
            log = self.base / 'execution.log'
            log.write_text("Test Case '-[Tests testA]' failed\nTest Case '-[Tests testA]' passed\n")
            return SimpleNamespace(returncode=1, reason='exited', log=log)

        with patch.object(adapter, 'source_state', return_value='fixed'), patch.object(
                adapter, 'test_plan', return_value=('logic', ['TodayTests/Tests/testA'])), patch.object(
                adapter.contract, 'inventory', return_value={'logic': [{'suite': 'Tests', 'target': 'TodayTests',
                    'methods': [{'name': 'testA', 'framework': 'XCTest'}]}]}):
            self.assertEqual(adapter._main(root, 'business', selection=selection, output=self.output,
                                          sha=SHA, synthetic=True, no_distribute=True, runner=run), 1)
        report = json.loads((self.output / 'report.json').read_text())
        self.assertEqual(report['failed'], 1)
        self.assertTrue(report['artifact_provenance']['closed'])
        self.assertIn('failed', (self.output / 'command.log').read_text())
        producer.close_wrapper(self.output, SHA, 'business', 'failed adapter exited\n')
        producer.stage(self.output, self.base / 'failed-artifacts', SHA, 'business')

    def test_interrupted_ui_without_shutdown_never_walks_or_seals_bundle(self):
        self.output.rmdir()
        self.output = self.base / 'today-core-ui'
        root = self.base / 'repo'
        root.mkdir()
        selection = self.base / 'selection.json'
        selection.write_text(json.dumps({'version': 1, 'mode': 'wide', 'reason': 'fixture',
                                         'changed': [], 'targets': [], 'all_targets': True, 'snapshots': True}))

        def run(*args, **kwargs):
            self.write('runner/ui.xcresult/.live', b'potentially live; never inspect')
            log = self.base / 'cancelled.log'
            log.write_text('runner cancelled before summary or shutdown')
            return SimpleNamespace(returncode=130, reason='cancelled', log=log)

        with patch.object(adapter, 'source_state', return_value='fixed'), patch.object(
                adapter, 'test_plan', return_value=('ui', ['Tests/testA'])), patch.object(
                producer, 'close_producer', wraps=producer.close_producer) as close:
            self.assertEqual(adapter._main(root, 'core-ui', selection=selection,
                                          output=self.output, sha=SHA, synthetic=True,
                                          no_distribute=True, runner=run), 1)
        close.assert_not_called()
        report = json.loads((self.output / 'report.json').read_text())
        self.assertEqual(report['cancelled'], 1)
        self.assertNotIn('artifact_provenance', report)
        self.assertTrue((self.output / 'runner/ui.xcresult/.live').is_file())

    def wrapper(self, execute):
        with patch.object(sys, 'argv', ['run.py', 'business']), patch.object(
                producer.subprocess, 'check_output', return_value=SHA), patch.object(
                producer, 'execute', side_effect=execute), contextlib.redirect_stdout(io.StringIO()):
            return producer.main()

    def test_wrapper_orders_setup_before_selection_and_adapter(self):
        self.output.rmdir()
        calls = []

        def execute(argv, **kwargs):
            calls.append(argv)
            self.assertEqual(kwargs['timeout'], 600)
            self.assertEqual(kwargs['grace'], 30)
            if argv[0] == sys.executable:
                self.write('selection.json', b'{}')
            if argv[:2] == ['./dev', 'ci']:
                # The adapter still gets a fresh directory, with no setup logs
                # or setup receipt that could be mistaken for producer output.
                self.assertEqual([p.name for p in self.output.iterdir()], ['selection.json'])
                self.close()
            return SimpleNamespace(returncode=0, stdout=argv[1] + ' finished\n')

        self.assertEqual(self.wrapper(execute), 0)
        self.assertEqual([argv[:2] for argv in calls[:3]],
                         [['./dev', step] for step in ('bootstrap', 'generate', 'resolve')])
        self.assertEqual(calls[3][:3], [sys.executable, 'scripts/ci/policy.py', 'select'])
        self.assertEqual(calls[4][:3], ['./dev', 'ci', 'business'])
        log = (self.base / 'today-artifacts-business/wrapper-command.log').read_text()
        for step in ('bootstrap', 'generate', 'resolve', 'ci'):
            self.assertIn(step + ' finished', log)

    def test_wrapper_setup_first_failure_closes_evidence_and_never_dispatches(self):
        steps = ('bootstrap', 'generate', 'resolve', 'select')
        for failed_index in range(len(steps)):
            with self.subTest(step=steps[failed_index]):
                shutil.rmtree(self.output)
                calls = []

                def execute(argv, **kwargs):
                    calls.append(argv)
                    code = 23 if len(calls) - 1 == failed_index else 0
                    return SimpleNamespace(returncode=code, stdout='setup /Users/synthetic/fixture\n')

                self.assertEqual(self.wrapper(execute), 23)
                self.assertEqual(len(calls), failed_index + 1)
                self.assertFalse(any(argv[:2] == ['./dev', 'ci'] for argv in calls))
                target = self.base / 'today-artifacts-business'
                report = json.loads((target / 'report.json').read_text())
                self.assertEqual((report['status'], report['executed'], report['failed']), ('failed', 0, 1))
                self.assertEqual(report['errors'], ['setup_exit:23'])
                self.assertTrue(report['artifact_provenance']['closed'])
                log = (target / 'wrapper-command.log').read_bytes()
                self.assertNotIn(b'/Users/synthetic', log)
                receipt = report['artifact_provenance']['files']
                entry = next(e for e in receipt if e['path'] == 'wrapper-command.log')
                self.assertEqual(producer.artifact_digest(log), {k: entry[k] for k in ('bytes', 'sha256')})
                with self.assertRaises(ValueError):
                    producer.validate_report(report, SHA, 'business')
                shutil.rmtree(target)

    def test_wrapper_setup_timeout_or_spawn_failure_retains_failure(self):
        for error, code in ((None, 124),
                            (FileNotFoundError('private fixture path'), 1)):
            with self.subTest(error=type(error).__name__):
                shutil.rmtree(self.output)
                with patch.object(producer, 'close_wrapper', wraps=producer.close_wrapper) as close:
                    def execute(*args, **kwargs):
                        if error:
                            raise error
                        return SimpleNamespace(returncode=124, stdout='partial /Users/synthetic/fixture\ncommand timed out\n')
                    self.assertEqual(self.wrapper(execute), code)
                close.assert_called_once()
                target = self.base / 'today-artifacts-business'
                report = json.loads((target / 'report.json').read_text())
                self.assertEqual(report['errors'], ['setup_exit:' + str(code)])
                self.assertNotIn('private fixture path', (target / 'wrapper-command.log').read_text())
                shutil.rmtree(target)

    def test_wrapper_rejects_secret_detected_before_process_redaction(self):
        self.output.rmdir()
        self.assertEqual(self.wrapper(lambda *args, **kwargs: SimpleNamespace(
            returncode=31, stdout='token=[REDACTED]', secret_found=True)), 31)
        self.assertFalse((self.base / 'today-artifacts-business').exists())

    def test_owned_executor_retains_timeout_and_pre_redaction_secret_detection(self):
        secret = producer.execute([sys.executable, '-c', "print('token=fixture-credential')"], timeout=5)
        self.assertEqual(secret.returncode, 0)
        self.assertTrue(secret.secret_found)
        self.assertNotIn('fixture-credential', secret.stdout)
        stopped = producer.execute([sys.executable, '-c', 'import time; time.sleep(10)'],
                                   timeout=0.1, grace=0.1)
        self.assertEqual(stopped.returncode, 124)

    def test_wrapper_setup_secret_candidate_never_publishes(self):
        self.output.rmdir()
        self.assertEqual(self.wrapper(lambda *args, **kwargs: SimpleNamespace(
            returncode=31, stdout='token=fixture-credential')), 31)
        self.assertFalse((self.base / 'today-artifacts-business').exists())
        self.assertNotIn('fixture-credential', (self.output / 'wrapper-command.log').read_text())

    def test_wrapper_keeps_first_exit_and_invalid_report_fails(self):
        for code, invalid in ((7, False), (130, False), (0, 'missing'), (7, 'malformed'),
                              (0, 'malformed'), (0, 'zero'), (0, 'bad'), (0, 'unknown')):
            with self.subTest(code=code, invalid=invalid):
                shutil.rmtree(self.output)

                def execute(argv, **kwargs):
                    if argv[0] == sys.executable:
                        self.write('selection.json', b'{}')
                    if argv[:2] != ['./dev', 'ci']:
                        return SimpleNamespace(returncode=0, stdout='setup finished\n')
                    if invalid not in ('missing', 'malformed'):
                        self.report.update(status='failed', executed=1,
                                           failed=int(code == 7), cancelled=int(code == 130))
                        if invalid:
                            self.report.update(status='passed', failed=0, cancelled=0)
                        if invalid == 'zero':
                            self.report['executed'] = 0
                        elif invalid == 'bad':
                            self.report['executed'] = '1'
                        elif invalid == 'unknown':
                            self.report['status'] = 'unknown'
                        self.write('command.log', b'first failure retained\n')
                        self.close()
                    if invalid == 'malformed':
                        self.write('report.json', b'[]')
                    return SimpleNamespace(returncode=code, stdout='adapter exited\n')

                self.assertEqual(self.wrapper(execute), code or 1)
                target = self.base / 'today-artifacts-business'
                if invalid in ('missing', 'malformed'):
                    self.assertFalse(target.exists())
                    self.assertTrue((self.output / 'wrapper-command.log').read_text().endswith('adapter exited\n'))
                else:
                    self.assertEqual((target / 'command.log').read_text(), 'first failure retained\n')
                    shutil.rmtree(target)


if __name__ == '__main__':
    unittest.main()
