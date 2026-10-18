"""Regression checks: quarantine rejection happens before child commands run."""
import subprocess
import sys
from pathlib import Path
import unittest

from simulator_policy import ACTIVE_NAME, ACTIVE_UDID, QUARANTINED_UDID, require_active, validate_command


class SimulatorPolicyTests(unittest.TestCase):
    def test_retired_and_unowned_devices_are_rejected(self):
        for udid in (QUARANTINED_UDID, 'unowned'):
            with self.assertRaises(ValueError):
                require_active(udid)
        require_active(ACTIVE_UDID)

    def test_stale_destination_is_rejected_even_with_active_name(self):
        with self.assertRaises(ValueError):
            validate_command(ACTIVE_NAME, ['xcodebuild', '-destination', 'id=' + QUARANTINED_UDID.lower()])
        validate_command(ACTIVE_NAME, ['xcodebuild', '-destination', 'id=' + ACTIVE_UDID])

    def test_wrapper_does_not_execute_a_stale_command(self):
        wrapper = Path(__file__).with_name('with_owned_runner.py')
        result = subprocess.run([sys.executable, str(wrapper), '--simulator-name', ACTIVE_NAME,
                                 '--derived-data', str(wrapper.parent), '--', sys.executable,
                                 '-c', "raise SystemExit('CHILD_EXECUTED')", QUARANTINED_UDID],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('quarantined', result.stderr)
        self.assertNotIn('CHILD_EXECUTED', result.stderr)


if __name__ == '__main__':
    unittest.main()
