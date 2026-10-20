"""Synthetic CI plumbing only: no Xcode build, simulator or phone."""
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.ci import failure, smoke  # noqa: E402 - direct script execution from any cwd


class FailureCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.addCleanup(patch.stopall)
        qa = self.root / 'tests/qa'
        qa.mkdir(parents=True)
        for name in ('journal.py', 'activity-v1.sql'):
            shutil.copyfile(ROOT / 'tests/qa' / name, qa / name)
        patch.object(failure, 'probe', return_value='synthetic-source').start()
        self.evidence = failure.FailureEvidence(self.root, self.root / 'temp', smoke.PRODUCTS, lane='synthetic')

    def tearDown(self):
        # Keep synthetic command bytes and closed tar evidence after temp cleanup,
        # indexed with the same primary-checkout journal as ./dev's test log.
        evidence = failure.Evidence(ROOT, 'synthetic-' + self.evidence.session, failure.Redactor())
        try:
            files = [path for path in self.root.rglob('*') if path.is_file() and
                     (path.suffix in ('.log', '.json') or path.name.endswith('.tar.gz')) and
                     'archives' not in path.relative_to(self.root).parts]
            evidence.journal.archive_files(self.root, evidence.session, files=sorted(files))
        finally:
            evidence.close()

    def test_pre_result_failure_preserves_exit_raw_hash_redacted_export_and_no_fake_bundle(self):
        with patch.dict(os.environ, {'CI_TEST_TOKEN': 'private-secret'}):
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                self.evidence.run(sys.executable, '-c',
                                  "import os,sys; print(os.environ['CI_TEST_TOKEN']); print(os.getcwd()); sys.exit(37)")
        self.assertEqual(caught.exception.returncode, 37)
        self.evidence.finish(37, self.root / 'missing.xcresult')
        raw = (self.evidence.private / '00.raw.log').read_bytes()
        exported = (self.evidence.export / '00.log').read_text()
        self.assertIn(b'private-secret', raw)
        self.assertNotIn('private-secret', exported)
        self.assertNotIn(str(self.root), exported)
        data = json.loads((self.evidence.export / 'metadata.json').read_text())
        self.assertEqual((data['exit'], data['xcresult']), (37, 'not_created'))
        self.assertEqual(data['first_failure']['exit'], 37)
        self.assertEqual(data['commands'][0]['raw_sha256'], hashlib.sha256(raw).hexdigest())
        self.assertFalse(list(self.evidence.export.glob('*.tar.gz')))
        with self.assertRaises(subprocess.CalledProcessError):
            self.evidence.run(sys.executable, '-c', 'raise SystemExit(9)')
        self.assertEqual(self.evidence.first_failure['exit'], 37)

    def test_signal_keeps_partial_output_and_unconfirmed_result_out_of_export(self):
        # The child cancels this owned runner; its existing signal handler reaps the child.
        code = self.evidence.run(sys.executable, '-c',
                                 'import os,signal,time; print("before-signal", flush=True); os.kill(os.getppid(), signal.SIGINT); time.sleep(20)',
                                 check=False)
        self.assertEqual(code, 130)
        self.assertEqual(self.evidence.commands[0]['reason'], 'cancelled')
        result = self.root / 'partial.xcresult'
        result.mkdir()
        (result / 'partial').write_text('unfinished')
        self.evidence.finish(code, result)
        self.assertIn('before-signal', (self.evidence.export / '00.log').read_text())
        data = json.loads((self.evidence.export / 'metadata.json').read_text())
        self.assertEqual(data['xcresult'], 'unconfirmed_not_uploaded')
        self.assertFalse(list(self.evidence.export.glob('*.tar.gz')))

    def test_only_closed_result_is_archived_byte_exact_with_log_export_limit(self):
        result = self.root / 'synthetic.xcresult'
        (result / 'Data').mkdir(parents=True)
        raw = b'\x00synthetic closed bytes\xff'
        (result / 'Data/object').write_bytes(raw)
        self.evidence.run(sys.executable, '-c', 'print("x" * 200)')
        with patch.object(failure, 'LOG_LIMIT', 80):
            self.evidence.finish(1, result, closed=True)
        with tarfile.open(self.evidence.export / 'smoke.xcresult.tar.gz') as archive:
            self.assertEqual(archive.extractfile('smoke.xcresult/Data/object').read(), raw)
        self.assertIn('Export truncated', (self.evidence.export / '00.log').read_text())
        self.assertIn('x' * 100, (self.evidence.private / '00.raw.log').read_text())
        self.assertTrue(list((self.root / 'tests/results/archives').rglob('Data/object')))
        # Oversize affects upload only; the complete closed source stays journal-archived.
        oversized = failure.FailureEvidence(self.root, self.root / 'temp', smoke.PRODUCTS, lane='synthetic')
        with patch.object(failure, 'RESULT_LIMIT', 1):
            oversized.finish(1, result, closed=True)
        self.assertTrue(list((self.root / 'tests/results/archives' / oversized.session).rglob('Data/object')))
        self.assertFalse(list(oversized.export.glob('*.tar.gz')))
        broken = failure.FailureEvidence(self.root, self.root / 'temp', smoke.PRODUCTS, lane='synthetic')
        with patch.object(tarfile.TarFile, 'add', side_effect=OSError('synthetic disk error')):
            broken.finish(1, result, closed=True)
        self.assertFalse(list(broken.export.glob('*.tar.gz')))
        # A prior successful command cannot consume the first failure's log allowance.
        failed = failure.FailureEvidence(self.root, self.root / 'temp', smoke.PRODUCTS, lane='synthetic')
        failed.run(sys.executable, '-c', 'print("success" * 200)')
        failed.run(sys.executable, '-c', 'print("head" + "x" * 200 + "known-error-tail"); raise SystemExit(37)', check=False)
        with patch.object(failure, 'LOG_LIMIT', 100):
            failed.finish(37, self.root / 'missing.xcresult')
        exported = (failed.export / '01.log').read_text()
        self.assertIn('head', exported)
        self.assertIn('known-error-tail', exported)
        self.assertLessEqual(sum(log.stat().st_size for log in failed.export.glob('*.log')), 100)

    def test_smoke_still_rejects_missing_skipped_duplicate_and_extra_leaves(self):
        names = [test.rsplit('/', 1)[1] for test in smoke.TESTS]
        cases = [{'nodeType': 'Test Case', 'name': name, 'result': 'Passed'} for name in names]
        for nodes in (cases[:-1], cases + [cases[0]],
                      cases + [{'nodeType': 'Test Case', 'name': 'extra', 'result': 'Passed'}],
                      [dict(case, result='Skipped') for case in cases]):
            with self.subTest(nodes=nodes), patch.object(smoke, 'run', return_value=json.dumps({'testNodes': nodes})), \
                    self.assertRaises(SystemExit):
                smoke.verify()
        with patch.object(smoke, 'run', return_value=json.dumps({'testNodes': cases})):
            smoke.verify()

    def test_entry_preserves_first_command_exit_if_later_verification_fails(self):
        self.evidence.first_failure = {'exit': 65}
        with patch.object(smoke, 'FailureEvidence', return_value=self.evidence), \
                patch.object(smoke, 'main', side_effect=SystemExit('missing leaf')), \
                patch.object(smoke, 'RESULT', self.root / 'missing.xcresult'), \
                patch.object(smoke, 'RESULT_CLOSED', False):
            self.assertEqual(smoke.entry([]), 65)


if __name__ == '__main__':
    unittest.main()
