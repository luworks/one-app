#!/usr/bin/env python3
"""Extract real simulator records and fail closed on incomplete batches."""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]


def fixture_hash():
    fixtures = {split: json.loads((ROOT / 'tests/fixtures' / name).read_text())['cases']
                for split, name in [('development', 'ai-chat-capability-eval.json'),
                                    ('holdout', 'intelligence-model-selection-holdout.json')]}
    return hashlib.sha256(json.dumps(fixtures, ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def validate_row(row):
    required = {'run', 'case', 'repetition', 'turn', 'split', 'smoke', 'input',
                'model', 'model_sha256', 'prompt_sha256', 'fixture_sha256',
                'output', 'status', 'attempted', 'fallback', 'elapsed_ms', 'expected_records'}
    if not isinstance(row, dict) or not required.issubset(row):
        raise ValueError('Required evidence metadata missing')
    if row['split'] not in ('development', 'holdout') or type(row['smoke']) is not bool:
        raise ValueError('Invalid split or smoke mode')
    for key in ('run', 'case', 'input', 'output'):
        if not isinstance(row[key], str):
            raise ValueError(f'Invalid {key}')
    for key in ('repetition', 'turn', 'expected_records'):
        if type(row[key]) is not int or row[key] < 0:
            raise ValueError(f'Invalid {key}')
    for key in ('attempted', 'fallback'):
        if type(row[key]) is not bool:
            raise ValueError(f'Invalid {key}')
    elapsed = row['elapsed_ms']
    if type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0:
        raise ValueError('Invalid latency')
    if row['status'] not in ('success', 'empty', 'error', 'timeout', 'token_limit', 'unavailable'):
        raise ValueError('Unknown generation status')
    repeats = row.get('repetitions', 1 if row['smoke'] else 3)
    if type(repeats) is not int or repeats not in (1, 3) or (row['smoke'] and repeats != 1):
        raise ValueError('Invalid repetition count')
    if row['status'] == 'success' and (not row['attempted'] or not row['output']):
        raise ValueError('Success without an attempted nonempty generation')
    if row['fallback']:
        raise ValueError('Model-only adapter unexpectedly reports a fallback')
    if not re.fullmatch(r'[0-9a-f]{64}', row['prompt_sha256']):
        raise ValueError('Invalid prompt hash')
    if row['fixture_sha256'] != fixture_hash():
        raise ValueError('Frozen fixture bundle hash mismatch')
    models = json.loads((ROOT / 'tests/fixtures/intelligence-model-selection-models.json').read_text())['models']
    if row['model'] not in models or row['model_sha256'] != models[row['model']]['sha256']:
        raise ValueError('Unknown model or pinned artifact hash mismatch')


def collect(text):
    runs = {}
    completed = set()
    errors = []
    chunks = {}
    lines = text.splitlines()
    for line in lines:
        if 'TODAY_EVAL_CHUNK ' not in line:
            continue
        try:
            uid, index, count, payload = line.split('TODAY_EVAL_CHUNK ', 1)[1].split()
            index, count = int(index), int(count)
            if not 0 <= index < count <= 100:
                raise ValueError('Invalid chunk bounds')
            total, parts = chunks.setdefault(uid, (count, {}))
            if count != total or (index in parts and parts[index] != payload):
                raise ValueError('Conflicting chunk')
            parts[index] = payload
        except ValueError as exc:
            errors.append(f'Malformed chunk: {exc}')
    for uid, (count, parts) in chunks.items():
        if set(parts) != set(range(count)):
            errors.append(f'Incomplete chunked record: {uid}')
        else:
            lines.append('TODAY_EVAL_BASE64 ' + ''.join(parts[i] for i in range(count)))
    for line in lines:
        if 'TODAY_EVAL_COMPLETE ' in line:
            completed.add(line.split('TODAY_EVAL_COMPLETE ', 1)[1].strip())
        if 'TODAY_EVAL {' not in line and 'TODAY_EVAL_BASE64 ' not in line:
            continue
        try:
            if 'TODAY_EVAL_BASE64 ' in line:
                payload = base64.b64decode(line.split('TODAY_EVAL_BASE64 ', 1)[1].strip(), validate=True)
            else:
                payload = line.split('TODAY_EVAL ', 1)[1]
            row = json.loads(payload)
            validate_row(row)
            key = (row['case'], row['repetition'], row['turn'])
            bucket = runs.setdefault(row['run'], {})
            if key in bucket and bucket[key] != row:
                errors.append(f'Conflicting duplicate: {row["run"]} {key}')
            bucket[key] = row
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(f'Malformed or truncated record: {exc}')
    reports = []
    for run, bucket in runs.items():
        rows = list(bucket.values())
        first = rows[0]
        split = first['split']
        name = ('intelligence-model-selection-holdout.json' if split == 'holdout'
                else 'ai-chat-capability-eval.json')
        cases = json.loads((ROOT / 'tests/fixtures' / name).read_text())['cases']
        if first['smoke']:
            cases = [c for c in cases if c['id'] in ('capability-question', 'slot-followup')]
        repetitions = first.get('repetitions', 1 if first['smoke'] else 3)
        expected = {(c['id'], rep, i): t['input'] for c in cases
                    for rep in range(repetitions)
                    for i, t in enumerate(c['turns'])}
        issues = []
        if set(bucket) != set(expected):
            issues.append(f'Expected {len(expected)} records, observed {len(bucket)}; '
                          f'missing={sorted(set(expected)-set(bucket))}; '
                          f'extra={sorted(set(bucket)-set(expected))}')
        for key, row in bucket.items():
            if row['expected_records'] != len(expected):
                issues.append(f'Declared record count mismatch: {key}')
            if row['input'] != expected.get(key):
                issues.append(f'Input mismatch: {key}')
            for field in ('model', 'model_sha256', 'prompt_sha256', 'fixture_sha256', 'split', 'smoke'):
                if row[field] != first[field]:
                    issues.append(f'Mixed {field} within run')
            for field, default in [('deadline_seconds', 30), ('generation_mode', 'raw_json'),
                                   ('output_limit', 384), ('repetitions', repetitions)]:
                if row.get(field, default) != first.get(field, default):
                    issues.append(f'Mixed {field} within run')
        if run not in completed:
            issues.append('Completion marker missing')
        reports.append({'run': run, 'model': first['model'], 'split': split,
                        'smoke': first['smoke'], 'expected': len(expected),
                        'observed': len(rows), 'complete': not issues,
                        'errors': issues, 'rows': rows})
    if not reports:
        errors.append('No real model records found')
    return {'valid': bool(reports) and not errors and all(r['complete'] for r in reports),
            'errors': errors, 'runs': reports}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = collect(args.log.read_text())
    with args.output.open('x') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'valid': result['valid'], 'runs': len(result['runs']),
                      'errors': result['errors']}))
    raise SystemExit(0 if result['valid'] else 1)


if __name__ == '__main__':
    main()
