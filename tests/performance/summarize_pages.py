#!/usr/bin/env python3
"""Summarize page/AI app-side samples without mixing backend or operation cohorts."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import statistics


def summarize(text):
    groups, seen, outcomes = defaultdict(list), {}, defaultdict(list)
    method = 'unknown'
    for line in text.splitlines():
        start = re.search(r"Test Case '-\[\S+ (\w+)\]' started", line)
        if start:
            method = start[1]
        end = re.search(r"Test Case '-\[\S+ (\w+)\]' (passed|failed)", line)
        if end:
            outcomes[end[1]].append(end[2])
        found = re.search(r'PERF_SAMPLE_APP (v=1;.+)$', line)
        if not found:
            continue
        fields = dict(part.split('=', 1) for part in found[1].split(';') if '=' in part)
        begin, finish, value = int(fields['start_ns']), int(fields['end_ns']), float(fields['ms'])
        if finish < begin or not math.isfinite(value) or value < 0:
            raise ValueError('invalid monotonic sample')
        backend = fields.get('backend', 'not_applicable')
        key = (method, fields['name'], backend)
        identity = (key, begin, finish)
        if identity in seen:
            if seen[identity] != value:
                raise ValueError('conflicting duplicate sample')
            continue
        seen[identity] = value
        groups[key].append(value)
    rows = []
    for (method, name, backend), values in sorted(groups.items()):
        passed = outcomes[method] == ['passed']
        median = statistics.median(values)
        rows.append(dict(method=method, name=name, backend=backend, n=len(values), raw_ms=values,
                         median_ms=median, min_ms=min(values), max_ms=max(values), p95_ms=None,
                         functional_pass=passed, baseline_usable=passed and len(values) >= 3,
                         proposed_required_ms=median / 3, proposed_stretch_ms=median / 10))
    return dict(endpoint='app-side geometry/two-displaylink proxies, not presented/realTouch/full usability',
                source_of_truth='raw samples and exact frozen source/context; goals are not results',
                methods=dict(outcomes), metrics=rows)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('log', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    with a.output.open('x') as out:
        json.dump(summarize(a.log.read_text(errors='replace')), out, indent=2)
        out.write('\n')
