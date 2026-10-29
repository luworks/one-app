import json
import unittest

from intelligence.collect_product import collect


def trace(*events):
    return '\n'.join('TODAY_MODEL_CALL ' + json.dumps(dict(
        version=1, call='d2193b71-1cce-48dd-9760-c36f0af7f355', stage='chat',
        event=event, elapsed_ms=i)) for i, event in enumerate(events))


class ProductionTraceTests(unittest.TestCase):
    def test_late_api_return_does_not_erase_deadline_or_fallback(self):
        result = collect(trace('api_started', 'deadline_timeout',
                               'chat_fallback_selected', 'api_returned'))
        counts = result['stages']['chat']
        self.assertEqual(counts['api_returned'], 1)
        self.assertEqual(counts['deadline_timeout'], 1)
        self.assertEqual(counts['chat_fallback_selected'], 1)
        self.assertNotIn('model_reply_selected', counts)

    def test_unavailability_does_not_become_generation(self):
        counts = collect(trace('unavailable'))['stages']['chat']
        self.assertNotIn('api_started', counts)
        self.assertNotIn('api_returned', counts)

    def test_completion_without_observed_call_is_rejected(self):
        with self.assertRaises(ValueError):
            collect(trace('api_returned'))

    def test_conflicting_completion_is_rejected(self):
        with self.assertRaises(ValueError):
            collect(trace('api_started', 'api_error', 'api_returned'))

    def test_content_fields_are_rejected(self):
        row = json.loads(trace('api_started').split('TODAY_MODEL_CALL ')[1])
        row['prompt'] = 'Synthetic text that must not enter production telemetry'
        with self.assertRaises(ValueError):
            collect('TODAY_MODEL_CALL ' + json.dumps(row))
