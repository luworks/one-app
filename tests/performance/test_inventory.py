import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
from contextlib import redirect_stderr
import io
from inventory import inventory
from summarize import summarize
import launch_probe


class InventoryTests(unittest.TestCase):
    def test_launch_probe_rejects_existing_evidence_before_device_access(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / 'launch-0.log'
            evidence.write_text('retained measurement')
            with patch('sys.argv', ['launch_probe.py', '--simulator', 'unused', '--output', directory]), \
                 patch.object(launch_probe.subprocess, 'check_output') as device_access, redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    launch_probe.main()
            self.assertEqual(error.exception.code, 2)
            device_access.assert_not_called()
            self.assertEqual(evidence.read_text(), 'retained measurement')

    def test_timing_summary_preserves_samples_and_leaves_tail_unknown(self):
        result = summarize('PERF_SAMPLE tap 20.0 ms\nPERF_SAMPLE tap 10 ms\nPERF_SAMPLE tap 30 ms')
        self.assertEqual(result['tap']['samples_ms'], [20, 10, 30])
        self.assertEqual(result['tap']['median_ms'], 20)
        self.assertIsNone(result['tap']['p95_ms'])

    def test_nested_extension_bytes_count_once_and_symlinks_are_not_duplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'PlugIns/Widget.appex').mkdir(parents=True)
            (root / 'tone.caf').write_bytes(b'tone' * 100)
            (root / 'PlugIns/Widget.appex/tone.caf').write_bytes(b'tone' * 100)
            (root / 'alias.caf').symlink_to(root / 'tone.caf')
            result = inventory(root)
            self.assertEqual(result['logical_bytes'], 800)
            self.assertEqual(result['categories'], {'.caf': 800})
            self.assertEqual(len(result['identical_files']), 1)
            self.assertEqual(len(result['files']), 2)
            self.assertGreater(result['local_zip_deflate9_bytes'], 0)


if __name__ == '__main__':
    unittest.main()
