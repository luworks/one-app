"""Inline synthetic host fixtures; no native tools, network or user-data scans."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/ci'))
SPEC = importlib.util.spec_from_file_location('artifact_ci_run', ROOT / 'scripts/ci/run.py')
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SHA = 'c' * 40
LANE = 'integration'


class ArtifactIntegrityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.source, self.destination = self.base / 'synthetic-run-1', self.base / 'published'
        self.source.mkdir()
        self.payloads = {
            'native/TodayTests.xcresult/.metadata': b'\x00\xffhidden',
            'native/TodayTests.xcresult/Data/store': bytes(range(256)),
            'native/TodayTests.xcresult/Data/.hidden/info.json': b'{"path":"/Users/synthetic/test"}\n',
            'native/TodayTests.xcresult/Info.plist': b'untouched plist',
            'attempt-1.log': b'first failure token=fixture-value /Users/synthetic/test\n',
            'attempt-2.log': b'retry passed\n',
        }
        for relative, data in self.payloads.items():
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (self.source / 'native/TodayTests.xcresult/.empty').mkdir()
        self.report = {
            'sha': SHA, 'lane': LANE, 'synthetic': True, 'status': 'failed',
            'executed': 2, 'failed': 1, 'missing': 0, 'cancelled': 0,
            'artifact_provenance': {
                'version': 1, 'owner': 'today-ci', 'run_id': self.source.name,
                'sha': SHA, 'lane': LANE, 'synthetic': True,
                'closed': True, 'secrets_available': False,
                'bundles': ['native/TodayTests.xcresult'],
                'files': [{'path': relative, **runner.artifact_digest(data)}
                          for relative, data in self.payloads.items()],
            },
        }
        self.write_report()

    def write_report(self):
        (self.source / 'report.json').write_text(json.dumps(self.report))

    def stage(self):
        runner.stage(self.source, self.destination, SHA, LANE)

    def test_complete_bundle_immutable_and_logs_transformed_with_actual_hashes(self):
        before = {p: (self.source / p).read_bytes() for p in self.payloads}
        self.stage()
        manifest = json.loads((self.destination / 'manifest.json').read_text())
        self.assertEqual({e['path'] for e in manifest['files']}, set(before) | {'report.json'})
        for entry in manifest['files']:
            relative = entry['path']
            actual = (self.destination / relative).read_bytes()
            self.assertEqual(runner.artifact_digest(actual), {k: entry[k] for k in ('bytes', 'sha256')})
            self.assertEqual(entry['source'], runner.artifact_digest((self.source / relative).read_bytes()))
            if '.xcresult/' in relative:
                self.assertEqual(actual, before[relative])
                self.assertEqual(entry['transformation'], 'identity')
        first = (self.destination / 'attempt-1.log').read_text()
        self.assertIn('first failure', first)
        self.assertNotIn('fixture-value', first)
        self.assertIn('/Users/REDACTED', first)
        entries = {e['path']: e for e in manifest['files']}
        self.assertEqual(entries['attempt-1.log']['transformation'], 'sanitize-v1')
        self.assertEqual(entries['attempt-2.log']['transformation'], 'identity')
        self.assertTrue((self.destination / 'native/TodayTests.xcresult/.empty').is_dir())
        self.assertEqual(before, {p: (self.source / p).read_bytes() for p in before})
        self.assertEqual(json.loads((self.destination / 'report.json').read_text())['status'], 'failed')

    def test_blocking_secret_patterns_include_json_and_binary(self):
        for data in (b'{"token":"fixture"}', b'Bearer fixture', b'\x00ghp_fixture\xff',
                     b'-----BEGIN PRIVATE KEY-----', b"password='fixture'"):
            with self.subTest(data=data):
                self.assertTrue(runner.bundle_secret(data))
        self.assertFalse(runner.bundle_secret(b'{"path":"/Users/synthetic/data"}'))

    def test_missing_live_wrong_owner_sha_and_secret_runner_rejected_before_bundle_read(self):
        cases = [('closed', False), ('owner', 'other'), ('run_id', 'other-run'),
                 ('sha', 'd' * 40), ('lane', 'business'), ('synthetic', False),
                 ('secrets_available', True), ('secrets_available', None)]
        original = dict(self.report['artifact_provenance'])
        for key, value in cases:
            with self.subTest(key=key, value=value):
                self.report['artifact_provenance'] = dict(original, **{key: value})
                self.write_report()
                with patch.object(Path, 'rglob', side_effect=AssertionError('must not scan')):
                    with self.assertRaisesRegex(ValueError, 'ownership/provenance'):
                        self.stage()
                self.assertFalse(self.destination.exists())
        del self.report['artifact_provenance']
        self.write_report()
        with self.assertRaises(ValueError):
            self.stage()

    def test_outer_sha_and_synthetic_mismatch_rejected(self):
        for key, value in [('sha', 'd' * 40), ('synthetic', False), ('lane', 'business')]:
            with self.subTest(key=key):
                report = dict(self.report, **{key: value})
                (self.source / 'report.json').write_text(json.dumps(report))
                with self.assertRaisesRegex(ValueError, 'provenance'):
                    self.stage()

    def test_missing_hidden_file_from_inventory_rejected(self):
        self.report['artifact_provenance']['files'].pop(0)
        self.write_report()
        with self.assertRaisesRegex(ValueError, 'incomplete closed bundle'):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_closed_file_mutation_rejected_and_source_retained(self):
        path = self.source / 'attempt-1.log'
        path.write_bytes(b'changed first failure')
        with self.assertRaisesRegex(ValueError, 'bytes changed'):
            self.stage()
        self.assertFalse(self.destination.exists())
        self.assertEqual(path.read_bytes(), b'changed first failure')

    def test_blocking_secret_rejects_bundle_without_modification(self):
        relative = 'native/TodayTests.xcresult/Data/store'
        data = b'\x00token=fixture-blocking-secret\xff'
        (self.source / relative).write_bytes(data)
        for entry in self.report['artifact_provenance']['files']:
            if entry['path'] == relative:
                entry.update(runner.artifact_digest(data))
        self.write_report()
        with self.assertRaisesRegex(ValueError, 'blocking secret'):
            self.stage()
        self.assertFalse(self.destination.exists())
        self.assertEqual((self.source / relative).read_bytes(), data)
        self.assertEqual((self.source / 'attempt-1.log').read_bytes(), self.payloads['attempt-1.log'])

    def test_symlink_in_bundle_or_explicit_artifact_rejected(self):
        for relative in ['native/TodayTests.xcresult/.metadata', 'attempt-1.log']:
            with self.subTest(relative=relative):
                path = self.source / relative
                original = path.read_bytes()
                path.unlink()
                path.symlink_to(self.source / 'attempt-2.log')
                with self.assertRaisesRegex(ValueError, 'symlink'):
                    self.stage()
                path.unlink()
                path.write_bytes(original)
        report = self.source / 'report.json'
        report.unlink()
        report.symlink_to(self.source / 'attempt-2.log')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.stage()

    def test_only_explicit_generated_paths_are_read(self):
        (self.source / 'private.sqlite').write_bytes(b'private sentinel')
        (self.source / 'unowned').symlink_to(self.base / 'not-to-be-scanned')
        read = Path.read_bytes
        def bounded_read(path):
            if path.name == 'private.sqlite':
                self.fail('private file must never be read')
            return read(path)
        with patch.object(Path, 'read_bytes', bounded_read):
            self.stage()
        self.assertFalse((self.destination / 'private.sqlite').exists())
        self.assertFalse((self.destination / 'unowned').exists())

    def test_traversal_private_extension_and_workspace_inventory_rejected(self):
        for relative in ['../outside.log', '/tmp/outside.log', 'native/../attempt-1.log',
                         'native\\outside.log', '.', 'private.sqlite']:
            with self.subTest(relative=relative):
                entry = self.report['artifact_provenance']['files'][0]
                original = entry['path']
                entry['path'] = relative
                self.write_report()
                with self.assertRaises(ValueError):
                    self.stage()
                entry['path'] = original
        self.report['artifact_provenance']['bundles'] = ['.']
        self.write_report()
        with self.assertRaises(ValueError):
            self.stage()

    def test_source_symlink_and_destination_overlap_rejected(self):
        alias = self.base / 'alias'
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ValueError):
            runner.stage(alias, self.destination, SHA, LANE)
        with self.assertRaises(ValueError):
            runner.stage(self.source, self.source / 'upload', SHA, LANE)
        self.destination.mkdir()
        with self.assertRaises(ValueError):
            self.stage()

    def test_mutation_during_copy_never_publishes(self):
        write = Path.write_bytes
        mutated = False
        def mutate(path, data):
            nonlocal mutated
            result = write(path, data)
            if not mutated and path.name == 'attempt-1.log' and path.parent != self.source:
                mutated = True
                write(self.source / 'attempt-1.log', b'late mutation')
            return result
        with patch.object(Path, 'write_bytes', mutate):
            with self.assertRaisesRegex(ValueError, 'changed during staging'):
                self.stage()
        self.assertFalse(self.destination.exists())


if __name__ == '__main__':
    unittest.main()
