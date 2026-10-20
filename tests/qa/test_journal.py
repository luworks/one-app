"""Small real-SQLite contracts; no Apple tools or devices."""
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import textwrap
import unittest

spec = importlib.util.spec_from_file_location('journal', Path(__file__).with_name('journal.py'))
j = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j)


class JournalTests(unittest.TestCase):
    def test_migration_is_exact_app_contract(self):
        source = (j.ROOT / 'ios/Sources/TodayData/ActivityStore.swift').read_text()
        sql = re.search(r'static let migrations: \[String\] = \[\s*"""\n(.*?)\n\s*"""', source, re.S).group(1)
        self.assertEqual(j.SCHEMA.read_text(), textwrap.dedent(sql) + '\n')

    def test_checkpoint_reopen_partial_attempts_and_final_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'live'
            source.mkdir()
            fixture = Path(__file__).with_name('fixtures') / 'attempts.log'
            log = source / 'ui.log'
            log.write_bytes(fixture.read_bytes() + b"Test Case 'partial' passed")
            bundle = source / 'ui.xcresult'
            bundle.mkdir()
            (bundle / 'data').write_bytes(b'result')
            (source / 'command.json').write_text(json.dumps({'cmd': ['python', '-V']}))
            db = root / 'results/activity.sqlite'
            journal = j.Journal(db)
            first = journal.import_run(source, 'sample')
            self.assertEqual(len(journal.import_run(source, 'sample')), len(first))
            self.assertEqual([json.loads(r['props'])['status'] for r in first if r['kind'] == 'qa.test'],
                             ['started', 'failed', 'started', 'passed'])
            self.assertTrue(any(r['kind'] == 'qa.ui.operation' for r in first))
            self.assertFalse(any(r['kind'] == 'qa.artifact' for r in first))
            self.assertFalse((db.parent / 'runs').exists())
            journal.close()
            journal = j.Journal(db)
            self.assertEqual(len(journal.query('sample')), len(first))
            with log.open('ab') as stream:
                stream.write(b' (1 s).\n')
            final = journal.import_run(source, 'sample', status='failed', archive=True)
            self.assertEqual(len([r for r in final if r['kind'] == 'qa.test']), 5)
            artifacts = [r for r in final if r['kind'] == 'qa.artifact']
            self.assertEqual(len(artifacts), 3)
            for row in artifacts:
                self.assertEqual(j.digest(Path(row['action'])), json.loads(row['props'])['sha256'])
            self.assertEqual(len(journal.import_run(source, 'sample', status='failed', archive=True)), len(final))
            # A changed raw file creates another artifact revision, preserving old bytes.
            (bundle / 'data').write_bytes(b'revised')
            journal.import_run(source, 'sample', status='failed', archive=True)
            self.assertEqual(len([r for r in journal.query('sample') if r['kind'] == 'qa.artifact']), 6)
            self.assertTrue(any(Path(r['action']).read_bytes() == b'result' for r in artifacts))
            json.dumps(journal.query('sample'))
            self.assertEqual(journal.db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            journal.close()

    def test_archive_retains_coherent_bundle_and_verbatim_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            bundle = source / 'fake.xcresult'
            (bundle / 'Data').mkdir(parents=True)
            (bundle / 'Info.plist').write_bytes(b'fake bundle metadata')
            (bundle / 'Data/object').write_bytes(b'fake result object')
            raw = b"    t =  1.23s Tap Today\r\npartial-last-line"
            (source / 'ui.log').write_bytes(raw)
            journal = j.Journal(root / 'results/activity.sqlite')
            self.addCleanup(journal.close)
            rows = journal.import_run(source, 'coherent', status='failed', archive=True)
            archive = next(r for r in rows if r['kind'] == 'qa.archive')
            retained = Path(archive['action'])
            self.assertEqual((retained / 'fake.xcresult/Info.plist').read_bytes(), b'fake bundle metadata')
            self.assertEqual((retained / 'fake.xcresult/Data/object').read_bytes(), b'fake result object')
            self.assertEqual((retained / 'ui.log').read_bytes(), raw)
            self.assertEqual((source / 'ui.log').read_bytes(), raw)
            self.assertEqual(len(archive['snapshot']), 3)
            provenance = next(r for r in rows if r['kind'] == 'qa.import.provenance')
            self.assertEqual(json.loads(provenance['props'])['timestamp_basis'], 'import_time')

    def test_default_run_archive_is_outside_source_and_does_not_grow(self):
        with tempfile.TemporaryDirectory() as directory:
            results = Path(directory) / 'tests/results'
            source = results / 'runs/default-run'
            source.mkdir(parents=True)
            (source / 'ui.log').write_bytes(b'raw log\n')
            journal = j.Journal(results / 'activity.sqlite')
            self.addCleanup(journal.close)
            rows = journal.import_run(source, 'default-run', status='passed', archive=True)
            archive = Path(next(r['action'] for r in rows if r['kind'] == 'qa.archive'))
            self.assertEqual(archive.parent, (results / 'archives/default-run').resolve())
            before = sorted(p.relative_to(results) for p in results.rglob('*') if p.is_file())
            again = journal.import_run(source, 'default-run', status='passed', archive=True)
            self.assertEqual(len(rows), len(again))
            self.assertEqual(before, sorted(p.relative_to(results) for p in results.rglob('*') if p.is_file()))
            self.assertEqual([p.name for p in source.iterdir()], ['ui.log'])
            with self.assertRaisesRegex(ValueError, 'nested inside source'):
                journal.import_run(results, 'invalid', status='passed', archive=True)

    def test_legacy_checkpoint_reimport_adds_context_without_duplicate_operations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'live'
            source.mkdir()
            log = source / 'ui.log'
            raw = Path(__file__).with_name('fixtures').joinpath('attempts.log').read_bytes()
            log.write_bytes(raw)
            journal = j.Journal(root / 'results/activity.sqlite')
            self.addCleanup(journal.close)
            offset = 0
            legacy_uids = []
            for line in raw.splitlines(keepends=True):
                text = line.decode().rstrip('\r\n')
                if j.is_ui_operation(text):
                    uid = f'line:legacy:{log.resolve()}:{offset}:{j.hashlib.sha256(line).hexdigest()}'
                    journal.record('legacy', 'qa.ui.operation', text, uid=uid)
                    legacy_uids.append(uid)
                offset += len(line)
            rows = journal.import_run(source, 'legacy')
            self.assertEqual(len([r for r in rows if r['kind'] == 'qa.ui.operation']), 3)
            self.assertEqual(len([r for r in rows if r['kind'] == 'qa.ui.subject']), 3)
            self.assertEqual([r['subject_ref'] for r in rows if r['uid'] in legacy_uids], ['legacy'] * 3)
            self.assertEqual(len(journal.import_run(source, 'legacy')), len(rows))
            self.assertEqual(log.read_bytes(), raw)

    def test_uid_conflict_and_newer_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'activity.sqlite'
            journal = j.Journal(db)
            journal.record('dev', 'qa.development', 'Read rules', uid='same')
            journal.record('dev', 'qa.development', 'Read rules', uid='same')
            with self.assertRaises(ValueError):
                journal.record('dev', 'qa.development', 'Changed', uid='same')
            journal.db.execute('PRAGMA user_version=2')
            journal.close()
            with self.assertRaisesRegex(ValueError, 'Newer'):
                j.Journal(db)

    def test_canonical_common_dir_without_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main = root / 'main'
            gitdir = main / '.git/worktrees/child'
            gitdir.mkdir(parents=True)
            (gitdir / 'commondir').write_text('../..')
            child = root / 'child'
            child.mkdir()
            (child / '.git').write_text('gitdir: ' + str(gitdir))
            self.assertEqual(j.canonical_root(child), main.resolve())
            self.assertEqual(j.canonical_root(main), main.resolve())


if __name__ == '__main__':
    unittest.main()
