#!/usr/bin/env python3
"""Offline companion to Understanding/main.swift; scores captured turns, never invokes a model."""
import argparse
from collections import Counter
import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / 'tests/fixtures/ai-title-rewrite-cases.json'
DIMENSIONS = ('faithful', 'actionable', 'natural', 'concise', 'notes')


def load_suite(path):
    suite = json.loads(Path(path).read_text())
    assert suite['schemaVersion'] == 1
    ids = [c['id'] for c in suite['cases']]
    assert len(ids) == len(set(ids)), 'duplicate case IDs'
    for c in suite['cases']:
        assert c['split'] in ('development', 'validation')
        assert c['lang'] in ('zh', 'en', 'mixed')
        assert c['turns']
        for t in c['turns']:
            assert t['thread'] and t['input']
            e = t['expected']
            assert e['gate'] in ('Add', 'Apply', None)
            for i in e['items']:
                assert len(i['titleExamples']) >= 1 and i['requiredFacts']
                assert i['noExtraFacts'] and i['noNegationFlip']
                assert all(k in i for k in ('kind', 'day', 'time', 'repeat', 'notesRetention', 'forbiddenFacts'))
    return suite


def score_turn(expected, got):
    """Missing evidence is unmeasured. Free-text facts always require a human rubric."""
    failures, missing, flags = [], [], []
    for key in ('route', 'intent', 'gate'):
        if key not in got:
            missing.append(key)
        elif got[key] != expected[key]:
            failures.append(key)
    if 'writesBeforeConfirmation' not in got:
        missing.append('writesBeforeConfirmation')
    elif got['writesBeforeConfirmation'] is not False:
        failures.append('writesBeforeConfirmation')
    if 'items' not in got:
        missing.append('items')
    elif len(got['items']) != len(expected['items']):
        failures.append('item_count')
    else:
        # Match by expected order, including follow-up identity; adapters must preserve that order.
        for index, (want, actual) in enumerate(zip(expected['items'], got['items'])):
            prefix = f'items[{index}]'
            for key in ('kind', 'day', 'time', 'repeat', *(['duration'] if 'duration' in want else [])):
                if key not in actual:
                    missing.append(f'{prefix}.{key}')
                elif actual[key] != want[key]:
                    failures.append(f'{prefix}.{key}')
            if 'title' not in actual:
                missing.append(f'{prefix}.title')
            else:
                title = actual['title']
                if not isinstance(title, str) or not title.strip():
                    failures.append(f'{prefix}.empty_title')
                elif want['quotedTitle'] is not None and title != want['quotedTitle']:
                    failures.append(f'{prefix}.quoted_title')
                else:
                    # Signals only: substring checks cannot decide semantic contradiction.
                    for phrase in want['forbiddenFacts']:
                        if phrase.casefold() in title.casefold():
                            flags.append(f'{prefix}.review_forbidden:{phrase}')
            if 'notes' not in actual:
                missing.append(f'{prefix}.notes')
    review = got.get('review')
    quality = None
    quality_possible = 0
    if review is not None:
        assert review.get('reviewer') and review.get('rationale'), 'review needs attribution and rationale'
        scores = review['scores']
        assert set(scores) == set(DIMENSIONS)
        assert all(v is None or type(v) is int and 0 <= v <= 2 for v in scores.values())
        assert type(review['semanticViolation']) is bool
        rated = [v for v in scores.values() if v is not None]
        quality = sum(rated)
        quality_possible = 2 * len(rated)
        if len(rated) != len(DIMENSIONS):
            missing.append('complete_semantic_review')
        if review['semanticViolation'] or any(v == 0 for v in rated) or quality_possible == 10 and quality < 8:
            failures.append('semantic_review')
    return dict(failures=failures, missing=missing, reviewFlags=flags, qualityScore=quality, qualityPossible=quality_possible,
                status='failed' if failures else 'unmeasured' if missing or review is None else 'reviewed_pass')


def evaluate(suite, observations, split='development'):
    rows = observations.get('rows', [])
    indexed = {}
    valid = {(c['id'], n) for c in suite['cases'] for n, _ in enumerate(c['turns'])}
    for r in rows:
        key = (r['caseId'], r['turn'])
        assert key in valid, f'unknown observation: {key}'
        assert key not in indexed, f'duplicate observation: {key}'
        indexed[key] = r
    results = []
    for c in suite['cases']:
        if split != 'all' and c['split'] != split:
            continue
        for n, turn in enumerate(c['turns']):
            r = indexed.get((c['id'], n), {})
            result = score_turn(turn['expected'], r.get('out', {}))
            artifact = r.get('artifact', {})
            path = Path(artifact.get('path', ''))
            if not path.is_file() or not artifact.get('sha256'):
                result['missing'].append('artifact')
            elif hashlib.sha256(path.read_bytes()).hexdigest() != artifact['sha256']:
                result['failures'].append('artifact_hash')
            result['status'] = ('failed' if result['failures'] else 'unmeasured'
                                if result['missing'] or result['qualityScore'] is None else 'reviewed_pass')
            results.append(dict(caseId=c['id'], turn=n, split=c['split'], group=c['group'], **result))
    return dict(evidence=observations.get('evidence', 'unspecified'),
                modelQualityClaim=False, counts=dict(Counter(r['status'] for r in results)),
                cases=len({r['caseId'] for r in results}), turns=len(results), results=results)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--cases', type=Path, default=DEFAULT)
    p.add_argument('--observations', type=Path)
    p.add_argument('--split', choices=['development', 'validation', 'all'], default='development')
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    suite = load_suite(a.cases)
    observations = json.loads(a.observations.read_text()) if a.observations else {}
    report = evaluate(suite, observations, a.split)
    payload = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if a.output:
        a.output.parent.mkdir(parents=True, exist_ok=True)
        a.output.write_text(payload)
    print(json.dumps({k: v for k, v in report.items() if k != 'results'}, ensure_ascii=False))
    return 1 if report['counts'].get('failed') else 0


if __name__ == '__main__':
    raise SystemExit(main())
