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
        source = (j.ROOT / 'ios/One/ActivityStore.swift').read_text()
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
            self.assertEqual(len([r for r in journal.query('sample') if r['kind'] == 'qa.artifact']), 4)
            self.assertTrue(any(Path(r['action']).read_bytes() == b'result' for r in artifacts))
            json.dumps(journal.query('sample'))
            self.assertEqual(journal.db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            journal.close()

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
