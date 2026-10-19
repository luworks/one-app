"""Closed producer/wrapper host fixtures, with no native tools or live bundles."""
import contextlib
import io
import json
import os
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

SHA = 'c' * 40


class ProducerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
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
                adapter, 'test_plan', return_value=('logic', ['Tests/testA'])):
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

    def test_wrapper_keeps_first_exit_and_missing_report_fails(self):
        for code, missing in ((7, False), (130, False), (0, True), (7, 'malformed')):
            with self.subTest(code=code, missing=missing):
                # Each wrapper owns one fresh directory.
                import shutil
                shutil.rmtree(self.output)

                def execute(argv, **kwargs):
                    if argv[0] == sys.executable:
                        self.write('selection.json', b'{}')
                    else:
                        if not missing:
                            self.report.update(status='failed', failed=int(code == 7), cancelled=int(code == 130))
                            self.write('command.log', b'first failure retained\n')
                            self.close()
                        if missing == 'malformed':
                            self.write('report.json', b'[]')
                        return SimpleNamespace(returncode=code, stdout='adapter exited\n')
                    return SimpleNamespace(returncode=0)

                with patch.object(sys, 'argv', ['run.py', 'business']), patch.object(
                        producer.subprocess, 'check_output', return_value=SHA), patch.object(
                        producer.subprocess, 'run', side_effect=execute), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(producer.main(), code or 1)
                target = self.base / 'today-artifacts-business'
                if missing:
                    self.assertFalse(target.exists())
                    self.assertEqual((self.output / 'wrapper-command.log').read_text(), 'adapter exited\n')
                else:
                    self.assertEqual((target / 'command.log').read_text(), 'first failure retained\n')
                    shutil.rmtree(target)


if __name__ == '__main__':
    unittest.main()
