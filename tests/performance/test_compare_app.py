import unittest
from compare_app import CONTEXT_KEYS, compare, samples


class CompareTests(unittest.TestCase):
    def test_duplicate_stdout_is_not_an_extra_sample_or_tail_estimate(self):
        line = 'PERF_SAMPLE_APP v=1;name=today_to_tasks;start_ns=10;end_ns=20;ms=0.00001'
        result = samples("Test Case '-[OneUITests.PerformanceClimbTests testNavigation]' started.\n" + line + '\n' + line)
        self.assertEqual(result['testNavigation/today_to_tasks']['n'], 1)
        self.assertIsNone(result['testNavigation/today_to_tasks']['p95_ms'])

    def test_different_optimization_is_rejected_and_tiny_n_cannot_pass(self):
        context = {key: 'same' for key in CONTEXT_KEYS}
        before = {'phase': dict(n=1, median_ms=100)}
        after = {'phase': dict(n=1, median_ms=1)}
        self.assertFalse(compare(before, after, context, context)['metrics']['phase']['required_3x_met'])
        with self.assertRaisesRegex(ValueError, 'optimization'):
            compare(before, after, context, dict(context, optimization='different'))


if __name__ == '__main__':
    unittest.main()
