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
        self.assertEqual(result['spans']['fallback_model_unavailable/async/response_await']['raw_ms'], [1])
        self.assertIsNone(result['spans']['fallback_model_unavailable/async/response_await']['p95_ms'])

    def test_missing_point_rejected_instead_of_empty_success(self):
        with self.assertRaisesRegex(ValueError, 'missing diagnostic'):
            stages.reduce(self.line().replace('chat_response_await_after_ns=7000000;', ''))

    def test_local_work_does_not_fabricate_zero_async_spans(self):
        line = self.line().replace('backend=fallback_model_unavailable;', 'backend=fallback_model_unavailable;dispatch=local_sync;')
        line = line.replace('task_enter_ns=5000000;', '').replace('chat_response_await_before_ns=6000000;', '')
        line = line.replace('chat_response_await_after_ns=7000000;', 'local_reply_before_ns=6000000;local_reply_after_ns=7000000;')
        result = stages.reduce(line)
        self.assertEqual(result['spans']['fallback_model_unavailable/local_sync/local_reply']['raw_ms'], [1])
        self.assertFalse(any('response_await' in name or 'task_queue' in name for name in result['spans']))
        with self.assertRaisesRegex(ValueError, 'contains async'):
            stages.reduce(line + ';task_enter_ns=5000000')

    def test_layout_attribution_requires_complete_points(self):
        with self.assertRaisesRegex(ValueError, 'missing diagnostic'):
            stages.reduce(self.line() + ';layout_attribution=1')

    def test_layout_attribution_retains_real_waits(self):
        fields = {
            'persist_before': 4, 'persist_after': 5,
            'scroll_request_before': 5, 'scroll_request_after': 6,
            'feedback_probe_arm': 7, 'feedback_probe_callback': 8,
            'feedback_probe_eligible': 9, 'feedback_layout': 11,
            'response_probe_arm': 10, 'response_probe_callback': 10,
            'response_probe_eligible': 10,
        }
        line = self.line() + ';layout_attribution=1;' + ';'.join(
            f'{key}_ns={value * 1000000}' for key, value in fields.items())
        result = stages.reduce(line)
        key = 'fallback_model_unavailable/async/'
        self.assertEqual(result['spans'][key + 'persist_call']['raw_ms'], [1])
        self.assertEqual(result['spans'][key + 'feedback_callback_to_eligible']['raw_ms'], [1])
        self.assertEqual(result['spans'][key + 'response_eligible_to_layout']['raw_ms'], [1])
