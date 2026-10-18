import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('summary', Path(__file__).with_name('summarize_pages.py'))
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class PageSummaryTests(unittest.TestCase):
    def sample(self, index, backend='rules'):
        return f'PERF_SAMPLE_APP v=1;name=ai_turn_to_response_layout;backend={backend};start_ns={index};end_ns={index+10};ms=0.00001'

    def test_deduplicates_stdout_and_keeps_backends_separate(self):
        rows = ["Test Case '-[OneUITests.AIResponsePerformanceTests testConversation]' started"]
        for backend in ['rules', 'fallback_model_unavailable']:
            for index in range(3):
                rows.extend([self.sample(index, backend)] * 2)
        rows.append("Test Case '-[OneUITests.AIResponsePerformanceTests testConversation]' passed")
        result = summary.summarize('\n'.join(rows))['metrics']
        self.assertEqual([r['n'] for r in result], [3, 3])
        self.assertEqual(len(result[0]['sample_metadata']), 3)
        self.assertIn('backend', result[0]['sample_metadata'][0])
        self.assertTrue(all(r['baseline_usable'] for r in result))
        self.assertTrue(all(r['p95_ms'] is None for r in result))

    def test_failed_or_incomplete_method_cannot_supply_accepted_baseline(self):
        for outcome in ['', "Test Case '-[OneUITests.AIResponsePerformanceTests testConversation]' failed"]:
            rows = ["Test Case '-[OneUITests.AIResponsePerformanceTests testConversation]' started"]
            rows += [self.sample(i) for i in range(3)] + [outcome]
            self.assertFalse(summary.summarize('\n'.join(rows))['metrics'][0]['baseline_usable'])

    def test_conflicting_duplicate_is_rejected(self):
        row = self.sample(1)
        with self.assertRaises(ValueError):
            summary.summarize(row + '\n' + row.replace('ms=0.00001', 'ms=0.00002'))
