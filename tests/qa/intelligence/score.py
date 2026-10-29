#!/usr/bin/env python3
"""Deterministic model-field checks; product/safety semantics still require review."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
try:
    from .collect import ROOT
except ImportError:  # Direct CLI invocation.
    from collect import ROOT

ACTION = {
    'added_reminder': ['reminder'], 'reminder_preview': ['reminder'],
    'alarm_preview': ['alarm'], 'event_preview': ['event'],
    'answer_agenda': ['chat'], 'answer': ['chat'], 'conversation': ['chat'],
    'change_preview': ['edit'], 'clarify': ['clarify'],
    'clarify_or_preview': ['clarify', 'reminder'],
    'multiple_previews': ['reminder'], 'clarify_or_reminder': ['clarify', 'reminder'],
}
DAY = {'today': '2026-10-28', 'tomorrow': '2026-10-29',
       'next Friday': '2026-10-30', 'none': None}
REPEAT = {'Friday': ('weekly', [6]), 'Monday and Wednesday': ('weekly', [2, 4])}


def normalize(text):
    return re.sub(r'\s+', '', str(text).replace('[QA]', '').casefold())


def grade(row, expect, *, require_generation=True):
    checks = {}
    raw = row['output'].strip()
    strict = True
    try:
        value = json.loads(raw)
    except ValueError:
        strict = False
        try:
            value = json.loads(re.sub(r'^```(?:json)?\s*|\s*```$', '', raw))
        except ValueError:
            value = None
    if not isinstance(value, dict):
        return dict(strict_json=False, checks={}, field_pass=False, semantic_fields_pass=False,
                    status=row['status'], semantic_review='UNKNOWN')
    required = {'intent', 'reply', 'title', 'date', 'time', 'repeat', 'weekdays',
                'duration_minutes', 'target'}
    checks['schema_fields'] = required.issubset(value)
    if require_generation:
        checks['generation'] = row['status'] == 'success'
    intents = [expect['intent']] if 'intent' in expect else ACTION[expect['action']]
    # A change to a proposal in history is not an edit of an existing saved item.
    if row['case'] == 'followup-repeat' and row['turn'] == 1:
        intents = ['edit', 'reminder']
    checks['intent'] = value.get('intent') in intents
    title = expect.get('title_contains')
    if title is not None:
        checks['literal_title'] = title in str(value.get('title', ''))
        checks['semantic_title'] = normalize(title) in normalize(value.get('title', ''))
    for field in ['time', 'date', 'duration_minutes', 'target']:
        if field in expect:
            wanted = expect[field]
            if wanted == 'none':
                wanted = None
            if field == 'target' and wanted == '[QA] dentist at 15:00':
                wanted = 'qa-visit-1500'
            checks[field] = value.get(field) == wanted
    if 'day' in expect:
        checks['date'] = value.get('date') == DAY[expect['day']]
    if 'repeat' in expect:
        repeat = expect['repeat']
        expected_repeat, weekdays = REPEAT.get(repeat, (repeat, None))
        checks['repeat'] = value.get('repeat') == expected_repeat
        if weekdays:
            checks['weekdays'] = sorted(value.get('weekdays') or []) == sorted(weekdays)
    if 'weekdays' in expect:
        checks['weekdays'] = sorted(value.get('weekdays') or []) == sorted(expect['weekdays'])
    if 'end' in expect:
        checks['duration_minutes'] = value.get('duration_minutes') == 60
    if expect.get('action') == 'multiple_previews':
        checks['item_count'] = len(value.get('items') or []) == 2
    return dict(strict_json=strict, parsed=value, checks=checks,
                field_pass=strict and bool(checks) and all(checks.values()),
                semantic_fields_pass=bool(checks) and all(v for k, v in checks.items() if k != 'literal_title'),
                status=row['status'], semantic_review='UNKNOWN')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(args.report.read_text())
    if not evidence['valid']:
        raise SystemExit('Incomplete evidence cannot be graded')
    result = []
    for run in evidence['runs']:
        name = 'intelligence-model-selection-holdout.json' if run['split'] == 'holdout' else 'ai-chat-capability-eval.json'
        cases = {c['id']: c for c in json.loads((ROOT / 'tests/fixtures' / name).read_text())['cases']}
        rows = []
        for row in run['rows']:
            case = cases[row['case']]
            rows.append(dict(case=row['case'], repetition=row['repetition'], turn=row['turn'],
                             category=case['category'], language=case['language'],
                             elapsed_ms=row['elapsed_ms'], attempted=row['attempted'],
                             first_output_ms=row.get('first_output_ms'),
                             generated_tokens=row.get('generated_tokens'),
                             fallback=row['fallback'],
                             **grade(row, case['turns'][row['turn']]['expect'])))
        result.append(dict(run=run['run'], model=run['model'], split=run['split'], smoke=run['smoke'],
                           statuses=dict(Counter(x['status'] for x in rows)), rows=rows))
    with args.output.open('x') as file:
        json.dump(dict(scope='model field checks only; not overall product/safety pass rates', runs=result),
                  file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
