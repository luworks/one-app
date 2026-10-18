import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('stages', Path(__file__).with_name('summarize_ai_stages.py'))
stages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stages)


class StageSummaryTests(unittest.TestCase):
    def line(self):
        order = ['send', 'context_complete', 'respond_enter', 'record_turn_before', 'record_turn_after',
                 'task_enter', 'chat_response_await_before', 'chat_response_await_after',
                 'finish_emission_assigned', 'on_change_enter', 'ready', 'response_layout']
        return 'PERF_STAGE_AI v=1;turn=one;backend=fallback_model_unavailable;' + ';'.join(
            f'{key}_ns={i * 1000000}' for i, key in enumerate(order))

    def test_deduplicates_and_retains_same_turn_spans(self):
        row = self.line()
        result = stages.reduce(row + '\n' + row)
        self.assertEqual(len(result['turns']), 1)
        self.assertEqual(result['spans']['fallback_model_unavailable/response_await']['raw_ms'], [1])
        self.assertIsNone(result['spans']['fallback_model_unavailable/response_await']['p95_ms'])

    def test_missing_point_rejected_instead_of_empty_success(self):
        with self.assertRaisesRegex(ValueError, 'missing diagnostic'):
            stages.reduce(self.line().replace('chat_response_await_after_ns=7000000;', ''))
