#!/usr/bin/env python3
"""Compare deduplicated app-side phase samples only under an identical declared context."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import statistics

CONTEXT_KEYS = ('configuration', 'optimization', 'simulator_id', 'runtime', 'fixture_sha256',
                'instrumentation_sha256', 'endpoint_version')


def samples(text):
    groups, seen = defaultdict(list), set()
    passed, failed = set(), set()
    method = 'unknown'
    for line in text.splitlines():
        case = re.search(r"Test Case '-\[\S+ (\w+)\]' started", line)
        if case:
            method = case[1]
        outcome = re.search(r"Test Case '-\[\S+ (\w+)\]' (passed|failed)", line)
        if outcome:
            (passed if outcome[2] == 'passed' else failed).add(outcome[1])
        match = re.search(r'PERF_SAMPLE_APP (v=1;.+)$', line)
        if not match:
            continue
        fields = dict(part.split('=', 1) for part in match[1].split(';') if '=' in part)
        identity = (fields.get('name'), fields.get('start_ns'), fields.get('end_ns'))
        if identity in seen:
            continue
        seen.add(identity)
        value = float(fields['ms'])
        if not math.isfinite(value) or value < 0 or int(fields['end_ns']) < int(fields['start_ns']):
            raise ValueError('invalid monotonic sample')
        groups[method + '/' + fields['name']].append(value)
        for key in ('init_to_store_ms', 'store_ms', 'bootstrap_ms', 'post_bootstrap_layout_ms'):
            if key in fields:
                groups[method + '/' + key].append(float(fields[key]))
    return {key: dict(n=len(values), raw_ms=values, median_ms=statistics.median(values),
                      min_ms=min(values), max_ms=max(values), p95_ms=None, functional_pass=key.split('/', 1)[0] in passed and key.split('/', 1)[0] not in failed)
            for key, values in sorted(groups.items())}


def compare(before, after, before_context, after_context):
    for key in CONTEXT_KEYS:
        if key not in before_context or before_context[key] != after_context.get(key):
            raise ValueError('incomparable context: ' + key)
    results = {}
    for key in before.keys() & after.keys():
        a, b = before[key], after[key]
        ratio = a['median_ms'] / b['median_ms'] if b['median_ms'] > 0 else None
        valid = a['n'] >= 3 and b['n'] >= 3
        functional_pass = a.get('functional_pass', False) and b.get('functional_pass', False)
        results[key] = dict(before=a, after=b, median_ratio=ratio, sample_count_sufficient=valid, functional_pass=bool(functional_pass),
                            required_3x_met=bool(valid and functional_pass and ratio is not None and ratio >= 3),
                            stretch_10x_met=bool(valid and functional_pass and ratio is not None and ratio >= 10))
    return dict(scope='monotonic app layout/display-link proxies; not presented/realTouch/complete usability',
                context=before_context, metrics=dict(sorted(results.items())),
                missing_after=sorted(before.keys() - after.keys()), missing_before=sorted(after.keys() - before.keys()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--before-context', required=True, type=Path)
    parser.add_argument('--after-context', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = compare(samples(args.before.read_text(errors='replace')), samples(args.after.read_text(errors='replace')),
                     json.loads(args.before_context.read_text()), json.loads(args.after_context.read_text()))
    with args.output.open('x') as stream:
        stream.write(json.dumps(result, indent=2) + '\n')
