"""Filesystem contract tests; never build or mutate the real project."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts.devtools import new_feature as subject

REPO = Path(__file__).resolve().parents[2]


class FeatureGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='feature worktree with spaces ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Real manifests are the fixture: target names, source membership and
        # formatting follow the integrated repository rather than the generator.
        for relative in ['ios/Package.swift', 'ios/project.yml', 'ios/App/OneApp.swift']:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((REPO / relative).read_bytes())
        # A linked-worktree .git file must not redirect generator writes.
        (self.root / '.git').write_text('gitdir: /unavailable/primary/.git/worktrees/fixture\n')
        self.before = self.snapshot()

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_real_feature_graph_and_app_link(self):
        manifest = subject.create(self.root, 'Reading')
        self.assertEqual(manifest.name, 'FeatureReading')
        package = (self.root / 'ios/Package.swift').read_text()
        self.assertIn('.library(name: "FeatureReading", targets: ["FeatureReading"])', package)
        self.assertIn('dependencies: ["TodayCore", "TodayDesignSystem"], path: "Sources/Features/FeatureReading"', package)
        project = json.loads((self.root / 'ios/project.yml').read_bytes())
        for name in ('Today', 'TodayMock'):
            self.assertIn({'package': 'TodayModules', 'product': 'FeatureReading'},
                          project['targets'][name]['dependencies'])
        screen = (self.root / 'ios/Sources/Features/FeatureReading/FeatureReadingScreen.swift').read_text()
        for token in ('public struct FeatureReadingScreen: View', 'Form {', 'Picker(',
                      'Appearance.displayOrder', 'PressScale()', '@State'):
            self.assertIn(token, screen)
        self.assertIn('FeatureReadingScreen()',
                      (self.root / 'ios/App/FeatureReadingLinkCheck.swift').read_text())
        self.assertEqual((self.root / 'ios/App/OneApp.swift').read_bytes(),
                         self.before['ios/App/OneApp.swift'])
        self.assertEqual(len(manifest.as_dict()['files']), 4)
        self.assertTrue(all(len(c.after_sha256) == 64 for c in manifest.changes))
        manifest.undo()
        manifest.undo()
        self.assertEqual(self.snapshot(), self.before)

    def test_invalid_names_leave_no_changes(self):
        for name in ('', '../Bad', 'foo', 'A B', 'A-B', 'A.swift', '9Bad', '你好', 'Self', 'Feature', None):
            with self.subTest(name=name), self.assertRaises(subject.FeatureError):
                subject.create(self.root, name)
            self.assertEqual(self.snapshot(), self.before)

    def test_collisions_are_preflighted(self):
        first = subject.create(self.root, 'FeatureReading')
        generated = self.snapshot()
        with self.assertRaises(subject.FeatureError):
            subject.create(self.root, 'Reading')
        self.assertEqual(self.snapshot(), generated)
        first.undo()
        for relative in ('ios/Sources/Features/FeatureReading', 'ios/App/FeatureReadingLinkCheck.swift'):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('user content')
            before = self.snapshot()
            with self.assertRaises(subject.FeatureError):
                subject.create(self.root, 'Reading')
            self.assertEqual(self.snapshot(), before)
            path.unlink()

    def test_success_failure_and_cancel_restore_exact_bytes_and_modes(self):
        entry = self.root / 'ios/App/OneApp.swift'
        entry.chmod(0o640)
        for failure in (None, RuntimeError('build failed'), KeyboardInterrupt(), SystemExit(130)):
            try:
                with subject.temporary(self.root, 'Reading') as manifest:
                    self.assertIn('WindowGroup { FeatureReadingScreen() }', entry.read_text())
                    manifest.assert_owned()
                    if failure:
                        raise failure
            except BaseException as error:
                self.assertIs(error, failure)
            self.assertEqual(self.snapshot(), self.before)
            self.assertEqual(entry.stat().st_mode & 0o777, 0o640)

    def test_undo_conflict_is_all_or_nothing_and_retryable(self):
        manifest = subject.create(self.root, 'Reading')
        changed = manifest.changes[-1]
        path = self.root / changed.path
        path.write_bytes(b'concurrent edit')
        snapshot = self.snapshot()
        with self.assertRaisesRegex(subject.FeatureError, 'Ownership conflict'):
            manifest.undo()
        self.assertEqual(self.snapshot(), snapshot)
        path.write_bytes(changed.after)
        manifest.undo()
        self.assertEqual(self.snapshot(), self.before)

    def test_verification_conflict_preserves_entry_and_generated_files(self):
        entry = self.root / 'ios/App/OneApp.swift'
        with self.assertRaises(subject.FeatureError):
            with subject.temporary(self.root, 'Reading') as manifest:
                entry.write_bytes(b'concurrent app edit')
        self.assertEqual(entry.read_bytes(), b'concurrent app edit')
        self.assertTrue((self.root / 'ios/Sources/Features/FeatureReading/FeatureReadingScreen.swift').exists())
        # The retained nested manifest permits explicit recovery without Git.
        change = manifest.verification_manifest.changes[0]
        self.assertEqual(change.before, self.before['ios/App/OneApp.swift'])
        entry.write_bytes(change.after)
        manifest.restore_verification()
        manifest.undo()
        self.assertEqual(self.snapshot(), self.before)

    def test_unrelated_new_files_survive_cleanup(self):
        manifest = subject.create(self.root, 'Reading')
        user_file = self.root / 'ios/Sources/Features/FeatureReading/User.swift'
        user_file.write_bytes(b'owned by user')
        manifest.undo()
        self.assertEqual(user_file.read_bytes(), b'owned by user')
        self.assertEqual((self.root / 'ios/Package.swift').read_bytes(), self.before['ios/Package.swift'])

    def test_publish_failure_rolls_back_prior_writes(self):
        original = subject.os.link
        def fail(source, destination):
            if destination.name.endswith('LinkCheck.swift'):
                raise OSError('injected publish failure')
            return original(source, destination)
        with patch.object(subject.os, 'link', side_effect=fail):
            with self.assertRaisesRegex(OSError, 'injected'):
                subject.create(self.root, 'Reading')
        self.assertEqual(self.snapshot(), self.before)
        self.assertFalse((self.root / 'ios/Sources/Features/FeatureReading').exists())

    def test_symlink_paths_and_mode_edits_are_not_owned(self):
        app = self.root / 'ios/App'
        real = self.root / 'SavedApp'
        app.rename(real)
        app.symlink_to(real, target_is_directory=True)
        with self.assertRaises(subject.FeatureError):
            subject.create(self.root, 'Reading')
        app.unlink()
        real.rename(app)
        manifest = subject.create(self.root, 'Reading')
        path = self.root / manifest.changes[-1].path
        path.chmod(0o600)
        with self.assertRaises(subject.FeatureError):
            manifest.undo()
        path.chmod(0o644)
        manifest.undo()

    def test_unrecognized_layout_is_readonly(self):
        project = self.root / 'ios/project.yml'
        data = json.loads(project.read_bytes())
        data['targets'] = {}
        project.write_text(json.dumps(data))
        before = self.snapshot()
        with self.assertRaises(subject.FeatureError):
            subject.create(self.root, 'Reading')
        self.assertEqual(self.snapshot(), before)


if __name__ == '__main__':
    unittest.main()
