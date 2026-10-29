#!/usr/bin/env python3
"""Grade exported pure rules fields, without inventing model or product evidence."""
import argparse
import json
from pathlib import Path

from collect import ROOT
from score import grade


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('observations', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    observed = json.loads(args.observations.read_text())
    cases = {c['id']: c for c in json.loads(
        (ROOT / 'tests/fixtures/ai-chat-capability-eval.json').read_text())['cases']}
    expected = {(c['id'], i): t['input'] for c in cases.values()
                for i, t in enumerate(c['turns'])}
    actual = {(r['case'], r['turn']): r for r in observed['rows']}
    if len(actual) != len(observed['rows']) or set(actual) != set(expected):
        raise SystemExit('Missing, duplicate or unexpected rules observations')
    rows = []
    for key, row in actual.items():
        if row['input'] != expected[key] or row['model_attempted'] is not False:
            raise SystemExit('Input mismatch or unexpected model invocation')
        case = cases[row['case']]
        proxy = dict(case=row['case'], turn=row['turn'], status='not_applicable',
                     output=json.dumps(row['output'], ensure_ascii=False))
        result = grade(proxy, case['turns'][row['turn']]['expect'], require_generation=False)
        rows.append(dict(case=row['case'], turn=row['turn'], category=case['category'],
                         language=case['language'], rule_route=row['rule_route'],
                         resolution=row['resolution'], model_attempted=False, **result))
    report = dict(scope='Pure rule field diagnostic only. Not model generation, complete app routing, saved-item editing, confirmation, save or Undo acceptance.',
                  complete=True, expected=len(expected), observed=len(rows), rows=rows)
    with args.output.open('x') as file:
        json.dump(report, file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
