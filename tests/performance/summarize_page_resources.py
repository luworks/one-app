#!/usr/bin/env python3
"""Summarize sampled app VM windows; not true peaks, leaks or device memory budgets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics


CASE = re.compile(r"Test Case '-\[(\S+) (\w+)\]' (started|passed|failed|skipped)")


def summarize(text):
    attempts, active, seen = [], None, {}
    for line in text.splitlines():
        case = CASE.search(line)
        if case:
            suite, method, outcome = case.groups()
            if outcome == 'started':
                active = dict(suite=suite, method=method, status='incomplete', windows=[])
                attempts.append(active)
            elif active and (active['suite'], active['method']) == (suite, method):
                if active['status'] != 'failed':
                    active['status'] = outcome
        found = re.search(r'PERF_RESOURCE_APP (\{.+\})$', line)
        if not found:
            continue
        if active is None:
            raise ValueError('resource sample without method start')
        row = json.loads(found[1])
        if row.get('schema') != 1:
            raise ValueError('unsupported resource schema')
        for field in ('start_ns', 'layout_ns', 'window_end_ns', 'seq', 'pid', 'route_visit'):
            if type(row.get(field)) is not int or row[field] < 0:
                raise ValueError('invalid integer field: ' + field)
        if not row['start_ns'] <= row['layout_ns'] <= row['window_end_ns']:
            raise ValueError('invalid resource window ordering')
        collection_end = row.get('collection_end_ns', row['window_end_ns'])
        if type(collection_end) is not int or collection_end < row['window_end_ns']:
            raise ValueError('invalid collection end')
        identity = (len(attempts), row['pid'], row['seq'])
        if identity in seen:
            if seen[identity] != row:
                raise ValueError('conflicting duplicate resource window')
            continue
        seen[identity] = dict(row)
        samples = row['samples']
        timestamps = [sample['ns'] for sample in samples]
        if any(type(t) is not int for t in timestamps) or any(b <= a for a, b in zip(timestamps, timestamps[1:])):
            raise ValueError('nonmonotonic resource samples')
        if any(t < row['start_ns'] or t > collection_end for t in timestamps):
            raise ValueError('sample outside collection interval')
        # The final timer callback can follow the deadline; retain it raw, not in window statistics.
        measured = [sample for sample in samples if sample['ns'] <= row['window_end_ns']]
        valid = [sample for sample in measured if sample.get('kern_return') == 0
                 and type(sample.get('phys_footprint_bytes')) is int
                 and sample['phys_footprint_bytes'] > 0
                 and type(sample.get('resident_size_bytes')) is int
                 and sample['resident_size_bytes'] > 0]
        steady = [sample for sample in valid if sample['ns'] >= row['layout_ns']]
        values = [sample['phys_footprint_bytes'] for sample in steady]
        row['derived'] = dict(
            valid_samples=len(valid), invalid_samples=len(measured) - len(valid),
            excluded_after_window_samples=len(samples) - len(measured),
            post_layout_samples=len(values),
            fixed_window_median_bytes=statistics.median(values) if values else None,
            fixed_window_range_bytes=[min(values), max(values)] if values else None,
            sampled_operation_max_bytes=max((s['phys_footprint_bytes'] for s in valid), default=None),
            max_observed_sample_gap_ns=max((b-a for a, b in zip(timestamps, timestamps[1:])), default=None),
            p95_bytes=None)
        row['window_usable'] = (len(values) >= 5 and len(valid) == len(measured)
                                and row.get('status', 'complete') == 'complete')
        active['windows'].append(row)
    groups = []
    for attempt in attempts:
        for row in attempt['windows']:
            row['functional_pass'] = attempt['status'] == 'passed'
            row['baseline_usable'] = row['functional_pass'] and row['window_usable']
        identities = sorted({(r['name'], r['route'], r['pid'], r.get('visit_basis', 'legacy_route_visit')) for r in attempt['windows']})
        for name, route, pid, basis in identities:
            rows = [r for r in attempt['windows'] if (r['name'], r['route'], r['pid'], r.get('visit_basis', 'legacy_route_visit')) == (name, route, pid, basis)]
            rows.sort(key=lambda r: r['route_visit'])
            complete = [r['route_visit'] for r in rows] == [1, 2, 3] and all(r['baseline_usable'] for r in rows)
            groups.append(dict(method=attempt['method'], name=name, route=route, pid=pid, visit_basis=basis,
                               ordered_visits=[r['route_visit'] for r in rows],
                               fixed_window_medians_bytes=[r['derived']['fixed_window_median_bytes'] for r in rows],
                               visit1_to_visit3_bytes=(rows[2]['derived']['fixed_window_median_bytes'] - rows[0]['derived']['fixed_window_median_bytes']) if complete else None,
                               baseline_usable=complete))
    return dict(schema=1, attempts=attempts, revisit_groups=groups,
                scope='Simulator app sampled phys_footprint; fixed post-layout window, sampled maximum and ordered revisits. Not true peak, leak, FPS or device budget.',
                comparison='New resource cohort; match source/config/fixture/visit order/window and sampling cadence before comparison. No p95 from tiny n.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    raw = args.log.read_bytes()
    result = summarize(raw.decode(errors='replace'))
    result['source'] = dict(path=str(args.log.resolve()), sha256=hashlib.sha256(raw).hexdigest())
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
