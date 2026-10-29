#!/usr/bin/env python3
"""Describe complete graded model batches; never promote field checks to product QA."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import statistics


def cell(rows):
    elapsed = sorted(r['elapsed_ms'] for r in rows)
    return dict(n=len(rows), statuses=dict(Counter(r['status'] for r in rows)),
                strict_json=sum(r['strict_json'] for r in rows),
                strict_specified_fields=sum(r['field_pass'] for r in rows),
                semantic_specified_fields=sum(r['semantic_fields_pass'] for r in rows),
                elapsed_median_ms=statistics.median(elapsed) if elapsed else None,
                elapsed_p90_ms=elapsed[int(.9 * (len(elapsed)-1))] if elapsed else None,
                within_30s_success=sum(r['status'] == 'success' and r['elapsed_ms'] <= 30000
                                       for r in rows),
                safety_review='UNKNOWN', product_acceptance='UNKNOWN')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('fields', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.fields.read_bytes()
    fields = json.loads(raw)
    reports = []
    for run in fields['runs']:
        if run['smoke']:
            continue
        groups = defaultdict(list)
        trials = defaultdict(list)
        for row in run['rows']:
            groups['language:' + row['language']].append(row)
            groups['category:' + row['category']].append(row)
            trials[(row['case'], row['repetition'])].append(row)
        report = dict(run=run['run'], model=run['model'], split=run['split'],
                      turns=cell(run['rows']), breakdown={k: cell(v) for k, v in groups.items()},
                      case_trials=len(trials),
                      strict_case_trials_pass=sum(all(r['field_pass'] for r in rows)
                                                  for rows in trials.values()),
                      semantic_case_trials_pass=sum(all(r['semantic_fields_pass'] for r in rows)
                                                    for rows in trials.values()))
        reports.append(report)
    result = dict(scope='Descriptive partial model-field rubric only; not full dialogue/safety or product rates.',
                  source=str(args.fields.resolve()), source_sha256=hashlib.sha256(raw).hexdigest(),
                  p90_definition='sorted sample index floor(0.9*(n-1))', runs=reports)
    with args.output.open('x') as file:
        json.dump(result, file, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    main()
