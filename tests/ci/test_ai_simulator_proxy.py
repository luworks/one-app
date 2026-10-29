"""Offline checks for the paid-evaluation relay's enforced request and budget boundaries."""
import json
from pathlib import Path
import tempfile
import unittest

from scripts.ai.simulator_proxy import Budget, MAX_OUTPUT, MODEL, PRIOR_USD, prepare


class SimulatorProxyTests(unittest.TestCase):
    def test_model_effort_storage_and_tools_cannot_be_overridden(self):
        result = prepare({'instructions': 'Extract a title', 'input': 'Synthetic',
                          'model': 'expensive-model', 'reasoning': {'effort': 'max'}, 'store': True,
                          'tools': [{'type': 'web_search'}], 'max_output_tokens': 999999,
                          'text': {'format': {'type': 'json_schema', 'strict': True,
                                              'name': 'title', 'schema': {'type': 'object'}}}})
        self.assertEqual((result['model'], result['reasoning']['effort']), (MODEL, 'medium'))
        self.assertFalse(result['store'])
        self.assertNotIn('tools', result)
        self.assertEqual(result['max_output_tokens'], MAX_OUTPUT)

    def test_missing_schema_or_input_is_rejected_before_payment(self):
        for body in [{}, {'instructions': 'x', 'input': ''},
                     {'instructions': 'x', 'input': 'y', 'text': {'format': {'type': 'text'}}}]:
            with self.assertRaises(ValueError):
                prepare(body)

    def test_unknown_charge_survives_restart_and_blocks_overspend(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'usage.sqlite'
            budget = Budget(path, limit=PRIOR_USD + .003)
            ident = budget.reserve('title', b'{}')
            budget.finish(ident, 'upstream_error', 1)
            restarted = Budget(path, limit=PRIOR_USD + .003)
            with self.assertRaises(ValueError):
                restarted.reserve('chat', b'{}')

    def test_known_usage_releases_reservation_but_counts_reasoning_output(self):
        with tempfile.TemporaryDirectory() as folder:
            budget = Budget(Path(folder) / 'usage.sqlite', limit=PRIOR_USD + .003)
            ident = budget.reserve('title', b'{}')
            budget.finish(ident, 'completed', 1, {'input_tokens': 100, 'output_tokens': 200,
                                                'output_tokens_details': {'reasoning_tokens': 150}})
            self.assertTrue(budget.reserve('chat', json.dumps({'input': 'x'}).encode()))
            with budget.connect() as db:
                cost, reasoning = db.execute('SELECT cost,reasoning_tokens FROM calls WHERE id=?',
                                             (ident,)).fetchone()
            self.assertAlmostEqual(cost, .00011)
            self.assertEqual(reasoning, 150)
