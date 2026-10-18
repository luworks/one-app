import copy
import unittest
import score


class ScoreTests(unittest.TestCase):
    def setUp(self):
        self.suite = score.load_suite(score.DEFAULT)
        self.want = self.suite['cases'][0]['turns'][0]['expected']
        self.good = dict(route='capture', intent='create', gate='Add', writesBeforeConfirmation=False,
                         items=[dict(kind='task', day=0, time='21:00', repeat=None,
                                     title='戴上Apple Watch监测睡眠', notes='测量今晚睡眠分数')],
                         review=dict(reviewer='test fixture', rationale='Synthetic rubric, not a model result',
                                     scores={d: 2 for d in score.DIMENSIONS}, semanticViolation=False))

    def test_missing_evidence_cannot_pass(self):
        self.assertEqual(score.score_turn(self.want, {})['status'], 'unmeasured')
        got = copy.deepcopy(self.good)
        del got['review']
        self.assertEqual(score.score_turn(self.want, got)['status'], 'unmeasured')
        report = score.evaluate(self.suite, {'rows': [dict(caseId='watch-sleep-zh', turn=0, out=self.good)]})
        self.assertEqual(report['results'][0]['status'], 'unmeasured')
        self.assertIn('artifact', report['results'][0]['missing'])

    def test_alternative_title_can_pass_review(self):
        self.assertEqual(score.score_turn(self.want, self.good)['status'], 'reviewed_pass')

    def test_gate_and_time_fail_independently(self):
        got = copy.deepcopy(self.good)
        got['writesBeforeConfirmation'] = True
        got['items'][0]['time'] = '23:00'
        self.assertEqual(set(score.score_turn(self.want, got)['failures']),
                         {'writesBeforeConfirmation', 'items[0].time'})

    def test_negation_flip_rejected_even_with_correct_time(self):
        got = copy.deepcopy(self.good)
        got['review']['semanticViolation'] = True
        self.assertIn('semantic_review', score.score_turn(self.want, got)['failures'])

    def test_duplicate_observation_rejected(self):
        row = dict(caseId='watch-sleep-zh', turn=0, out={})
        with self.assertRaises(AssertionError):
            score.evaluate(self.suite, {'rows': [row, row]})

    def test_validation_reserved_and_missing_counted(self):
        dev = score.evaluate(self.suite, {})
        validation = score.evaluate(self.suite, {}, 'validation')
        self.assertEqual(dev['cases'] + validation['cases'], 38)
        self.assertEqual(dev['counts'], {'unmeasured': dev['turns']})
        self.assertFalse({r['caseId'] for r in dev['results']} & {r['caseId'] for r in validation['results']})

    def test_quoted_title_is_exact_only_when_requested(self):
        want = copy.deepcopy(self.want)
        want['items'][0]['quotedTitle'] = 'Exact title'
        self.assertIn('items[0].quoted_title', score.score_turn(want, self.good)['failures'])
