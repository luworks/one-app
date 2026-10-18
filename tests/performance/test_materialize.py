import contextlib
import io
import json
import hashlib
import os
import subprocess
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import materialize


class MaterializeTests(unittest.TestCase):
    def test_frozen_reference_copies_only_explicit_instrumentation(self):
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as tar:
            for name, data in [('app.swift', b'original production'), ('fixture.json', b'versioned fixture')]:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))

        def fake_git(*args):
            if args[0] == 'rev-parse':
                return (args[1] + '\n').encode()
            if args[0] == 'archive':
                return archive.getvalue()
            if args[0] == 'diff':
                return b'instrumentation-only diff'
            if args[0] == 'show' and args[1] == 'candidate:trace.swift':
                return b'identical measurement code'
            self.fail('Unexpected git read: ' + str(args))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, evidence = root / 'source', root / 'evidence'
            argv = ['materialize.py', '--base', 'base', '--revision', 'candidate', '--source', str(source),
                    '--evidence', str(evidence), '--instrumentation', 'trace.swift']
            with patch('sys.argv', argv), patch.object(materialize, 'git', side_effect=fake_git), contextlib.redirect_stdout(io.StringIO()):
                materialize.main()
            self.assertEqual((source / 'app.swift').read_bytes(), b'original production')
            self.assertEqual((source / 'fixture.json').read_bytes(), b'versioned fixture')
            self.assertEqual((source / 'trace.swift').read_bytes(), b'identical measurement code')
            manifest = json.loads((evidence / 'manifest.json').read_text())
            self.assertEqual([f['path'] for f in manifest['files']], ['trace.swift'])
            self.assertTrue((evidence / 'baseline-source.tar').exists())


class MaterializeUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.repo_git('init', '-q')
        self.repo_git('config', 'user.name', 'Materialize Test')
        self.repo_git('config', 'user.email', 'materialize-test@example.invalid')
        self.repo_git('config', 'commit.gpgsign', 'false')
        (self.repo / 'app.swift').write_bytes(b'baseline app')
        (self.repo / 'unchanged.swift').write_bytes(b'unchanged')
        self.base = self.commit('Baseline')
        self.source = self.root / 'source'
        self.sequence = 0
        self.invoke(self.base, instrumentation=['unchanged.swift'])

    def repo_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.PIPE)

    def commit(self, title):
        self.repo_git('add', '-A')
        self.repo_git('commit', '-q', '-m', title)
        return self.repo_git('rev-parse', 'HEAD').decode().strip()

    def invoke(self, revision, *, update=False, instrumentation=()):
        self.sequence += 1
        evidence = self.root / ('evidence-' + str(self.sequence))
        argv = ['materialize.py', '--base', self.base, '--revision', revision,
                '--source', str(self.source), '--evidence', str(evidence)]
        if update:
            argv.append('--update')
        for name in instrumentation:
            argv.extend(['--instrumentation', name])
        with patch('sys.argv', argv), patch.object(materialize, 'git', side_effect=self.repo_git), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            materialize.main()
        return json.loads((evidence / 'manifest.json').read_text())

    def test_candidate_a_to_b_restores_baseline_and_preserves_equal_timestamps_and_caches(self):
        (self.repo / 'app.swift').write_bytes(b'candidate A app')
        candidate_a = self.commit('Candidate A')
        self.invoke(candidate_a, update=True)
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'candidate A app')
        unchanged = self.source / 'unchanged.swift'
        os.utime(unchanged, ns=(1_600_000_000_000_000_000, 1_600_000_000_000_000_000))
        before = unchanged.stat().st_mtime_ns
        cache = self.source / '.build' / 'cache.bin'
        cache.parent.mkdir()
        cache.write_bytes(b'keep warm build')
        untracked = self.source / 'personal.txt'
        untracked.write_bytes(b'keep untracked')
        cache_before = cache.stat().st_mtime_ns
        (self.repo / 'app.swift').write_bytes(b'baseline app')
        # B retains an independent candidate change but app.swift disappears from base..B.
        (self.repo / 'other.swift').write_bytes(b'candidate B addition')
        candidate_b = self.commit('Candidate B restores app')
        manifest = self.invoke(candidate_b, update=True)
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'baseline app')
        self.assertEqual(unchanged.stat().st_mtime_ns, before)
        self.assertEqual(cache.read_bytes(), b'keep warm build')
        self.assertEqual(cache.stat().st_mtime_ns, cache_before)
        self.assertEqual(untracked.read_bytes(), b'keep untracked')
        files = {entry['path']: entry for entry in manifest['files']}
        self.assertTrue(files['app.swift']['changed'])
        self.assertFalse(files['unchanged.swift']['changed'])
        self.assertEqual(files['app.swift']['sha256'], hashlib.sha256(b'baseline app').hexdigest())
        for entry in manifest['files']:
            self.assertEqual(entry['sha256'], hashlib.sha256((self.source / entry['path']).read_bytes()).hexdigest())

    def test_legacy_source_without_sidecar_is_audited_against_full_target(self):
        (self.root / '.source.materialize.json').unlink()
        (self.source / 'app.swift').write_bytes(b'old unrecorded candidate')
        manifest = self.invoke(self.base, update=True)
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'baseline app')
        self.assertTrue(next(f for f in manifest['files'] if f['path'] == 'app.swift')['changed'])

    def test_baseline_deletion_is_rejected_before_any_source_write(self):
        (self.repo / 'app.swift').unlink()
        (self.repo / 'unchanged.swift').write_bytes(b'new content must not be applied')
        revision = self.commit('Delete baseline file')
        with self.assertRaises(SystemExit):
            self.invoke(revision, update=True)
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'baseline app')
        self.assertEqual((self.source / 'unchanged.swift').read_bytes(), b'unchanged')

    def test_previous_candidate_addition_deletion_is_rejected(self):
        (self.repo / 'added.swift').write_bytes(b'candidate addition')
        candidate_a = self.commit('Add file')
        self.invoke(candidate_a, update=True)
        with self.assertRaises(SystemExit):
            self.invoke(self.base, update=True)
        self.assertEqual((self.source / 'added.swift').read_bytes(), b'candidate addition')

    def test_source_symlink_collision_is_rejected_before_writes(self):
        outside = self.root / 'outside.swift'
        outside.write_bytes(b'untouched outside')
        (self.source / 'unchanged.swift').unlink()
        (self.source / 'unchanged.swift').symlink_to(outside)
        (self.repo / 'app.swift').write_bytes(b'new candidate')
        revision = self.commit('Change app')
        with self.assertRaises(ValueError):
            self.invoke(revision, update=True)
        self.assertEqual(outside.read_bytes(), b'untouched outside')
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'baseline app')

    def test_explicit_instrumentation_remains_narrow(self):
        (self.repo / 'app.swift').write_bytes(b'candidate production')
        (self.repo / 'trace.swift').write_bytes(b'portable measurement')
        revision = self.commit('Instrumentation and production change')
        manifest = self.invoke(revision, update=True, instrumentation=['trace.swift'])
        self.assertEqual((self.source / 'app.swift').read_bytes(), b'baseline app')
        self.assertEqual([f['path'] for f in manifest['files']], ['trace.swift'])


if __name__ == '__main__':
    unittest.main()
