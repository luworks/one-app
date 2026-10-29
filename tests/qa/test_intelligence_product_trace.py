import json
import unittest

from intelligence.collect_product import collect


def trace(*events):
    return '\n'.join('TODAY_MODEL_CALL ' + json.dumps(dict(
        version=1, call='d2193b71-1cce-48dd-9760-c36f0af7f355', stage='chat',
        event=event, elapsed_ms=i)) for i, event in enumerate(events))


class ProductionTraceTests(unittest.TestCase):
    def test_routing_does_not_prove_response_completion_or_generation(self):
        rows = []
        turn = '7810a32f-e118-42b0-9d4a-d05835c00bf4'
        for i, event in enumerate(['turn_started', 'rule_direct_grant_selected', 'turn_routed']):
            rows.append('TODAY_MODEL_CALL ' + json.dumps(dict(
                version=1, call='d2193b71-1cce-48dd-9760-c36f0af7f355',
                turn=turn, stage='routing', event=event, elapsed_ms=i,
                wall_clock_unix_ms=1793278800000, system_timezone='America/Los_Angeles',
                system_locale='en_US')))
        result = collect('\n'.join(rows))
        self.assertEqual(len(result['turns'][turn]), 1)
        self.assertNotIn('api_returned', result['stages']['routing'])
        self.assertIn('UNKNOWN', result['window_completeness'])

    def test_background_ranking_stays_outside_submitted_turn_counts(self):
        background = []
        for i, event in enumerate(['api_started', 'api_returned', 'result_available']):
            background.append('TODAY_MODEL_CALL ' + json.dumps(dict(
                version=1, call='c956870e-535d-42c7-b371-f931b8879cc3',
                stage='rank', event=event, elapsed_ms=i)))
        turn = '7810a32f-e118-42b0-9d4a-d05835c00bf4'
        foreground = []
        for line in trace('api_started', 'api_returned').splitlines():
            row = json.loads(line.split('TODAY_MODEL_CALL ')[1])
            row['turn'] = turn
            foreground.append('TODAY_MODEL_CALL ' + json.dumps(row))
        result = collect('\n'.join(foreground + background))
        self.assertEqual(result['stages']['rank']['api_started'], 1)
        self.assertEqual(result['stages']['chat']['api_started'], 1)
        self.assertEqual(result['turns'][turn], ['d2193b71-1cce-48dd-9760-c36f0af7f355'])

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
