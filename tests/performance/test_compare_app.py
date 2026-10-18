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

    def test_three_fast_samples_require_a_passed_functional_method(self):
        def log(ms, outcome):
            lines = ["Test Case '-[Suite testNavigation]' started."]
            lines += [f'PERF_SAMPLE_APP v=1;name=route;start_ns={i};end_ns={i+1};ms={ms}' for i in range(3)]
            if outcome:
                lines += [f"Test Case '-[Suite testNavigation]' {outcome} (1 seconds)."]
            return samples('\n'.join(lines))
        context = {key: 'same' for key in CONTEXT_KEYS}
        for outcome in ('failed', None):
            result = compare(log(100, 'passed'), log(1, outcome), context, context)
            row = result['metrics']['testNavigation/route']
            self.assertEqual(row['median_ratio'], 100)
            self.assertFalse(row['required_3x_met'])
            self.assertFalse(row['stretch_10x_met'])
        result = compare(log(100, 'passed'), log(1, 'passed'), context, context)
        self.assertTrue(result['metrics']['testNavigation/route']['stretch_10x_met'])


if __name__ == '__main__':
    unittest.main()
