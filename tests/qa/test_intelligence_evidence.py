import json
import base64
import unittest

from intelligence.collect import collect, fixture_hash, ROOT
from intelligence.score import grade


def observation(**overrides):
    row = dict(run='run-1', case='capability-question', repetition=0, turn=0,
               split='development', smoke=True, input='Can you create reminders?',
               model='apple-system', model_sha256='system-managed-unexposed',
               prompt_sha256='b' * 64, fixture_sha256=fixture_hash(),
               output='{}', status='success', attempted=True, fallback=False,
               elapsed_ms=1.0, expected_records=3)
    row.update(overrides)
    return row


class IntelligenceEvidenceTests(unittest.TestCase):
    def test_generation_success_does_not_excuse_wrong_schedule(self):
        output = dict(intent='reminder', reply='Proposal', title='[QA] report',
                      date='2026-10-30', time='10:00', repeat='once', weekdays=[],
                      duration_minutes=None, target=None)
        row = dict(case='probe', turn=0, output=json.dumps(output), status='success')
        result = grade(row, dict(intent='reminder', time='16:00'))
        self.assertTrue(result['checks']['generation'])
        self.assertFalse(result['checks']['time'])
        self.assertFalse(result['field_pass'])

    def test_rules_grading_never_claims_model_generation(self):
        row = dict(case='rules', turn=0, status='not_applicable',
                   output='{"intent":"chat"}')
        result = grade(row, dict(intent='chat'), require_generation=False)
        self.assertNotIn('generation', result['checks'])
        self.assertEqual(result['status'], 'not_applicable')
        self.assertFalse(result['field_pass'], 'Incomplete schema is still a failure')

    def test_empty_and_truncated_logs_cannot_pass(self):
        self.assertFalse(collect('')['valid'])
        self.assertFalse(collect('TODAY_EVAL {"run":')['valid'])

    def test_one_success_cannot_stand_for_complete_batch(self):
        row = observation()
        report = collect('TODAY_EVAL ' + json.dumps(row) + '\nTODAY_EVAL_COMPLETE run-1')
        self.assertFalse(report['valid'])
        self.assertEqual(report['runs'][0]['expected'], 3)
        self.assertEqual(report['runs'][0]['observed'], 1)

    def test_completion_marker_without_results_cannot_pass(self):
        self.assertFalse(collect('TODAY_EVAL_COMPLETE run-1')['valid'])

    def test_base64_preserves_complete_multiturn_unicode_outputs(self):
        cases = json.loads((ROOT / 'tests/fixtures/ai-chat-capability-eval.json').read_text())['cases']
        lines = []
        output = '{"reply":"下午四点\\n[QA]报告"}'
        for case in cases:
            if case['id'] not in ('capability-question', 'slot-followup'):
                continue
            for i, turn in enumerate(case['turns']):
                row = observation(case=case['id'], turn=i, input=turn['input'], output=output)
                encoded = base64.b64encode(json.dumps(row, ensure_ascii=False).encode()).decode()
                parts = [encoded[j:j+100] for j in range(0, len(encoded), 100)]
                uid = f'{case["id"]}-{i}'
                for part, chunk in enumerate(parts):
                    lines.append(f'TODAY_EVAL_CHUNK {uid} {part} {len(parts)} {chunk}')
        lines.append('TODAY_EVAL_COMPLETE run-1')
        result = collect('\n'.join(lines))
        self.assertTrue(result['valid'])
        self.assertEqual(len(result['runs'][0]['rows']), 3)
        self.assertTrue(all(r['output'] == output for r in result['runs'][0]['rows']))
        self.assertFalse(collect('\n'.join(lines[1:]))['valid'])

    def test_invalid_identity_and_call_claims_are_rejected(self):
        for overrides in [dict(model_sha256='wrong'), dict(fixture_sha256='wrong'),
                          dict(attempted=False), dict(output=''), dict(elapsed_ms=float('nan')),
                          dict(split='unknown'), dict(fallback=True)]:
            with self.subTest(overrides=overrides):
                row = observation(**overrides)
                report = collect('TODAY_EVAL ' + json.dumps(row))
                self.assertFalse(report['valid'])
                self.assertTrue(report['errors'])

    def test_missing_required_metadata_fails_closed(self):
        row = observation()
        del row['split']
        self.assertFalse(collect('TODAY_EVAL ' + json.dumps(row))['valid'])

    def test_explicit_single_repeat_is_complete_but_not_three_repeats(self):
        cases = json.loads((ROOT / 'tests/fixtures/ai-chat-capability-eval.json').read_text())['cases']
        expected = sum(len(c['turns']) for c in cases)
        rows = [observation(case=c['id'], turn=i, input=t['input'], smoke=False,
                            repetitions=1, expected_records=expected)
                for c in cases for i, t in enumerate(c['turns'])]
        log = '\n'.join('TODAY_EVAL ' + json.dumps(r) for r in rows)
        self.assertTrue(collect(log + '\nTODAY_EVAL_COMPLETE run-1')['valid'])
        legacy_rows = [{k: v for k, v in r.items() if k != 'repetitions'} for r in rows]
        legacy = '\n'.join('TODAY_EVAL ' + json.dumps(r) for r in legacy_rows)
        self.assertFalse(collect(legacy + '\nTODAY_EVAL_COMPLETE run-1')['valid'])
