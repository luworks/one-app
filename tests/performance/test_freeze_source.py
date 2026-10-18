import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('freezer', Path(__file__).with_name('freeze_source.py'))
freezer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(freezer)


class SourceFreezeTests(unittest.TestCase):
    def test_unapproved_production_change_fails_before_creating_output(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / 'evidence'
            with patch.object(freezer, 'git', side_effect=[b'base', b'revision', b'ios/One/Unrelated.swift\n']):
                with self.assertRaisesRegex(ValueError, 'unapproved iOS'):
                    freezer.freeze('base', 'revision', ['ios/One/PerformanceTrace.swift'], output)
            self.assertFalse(output.exists())
