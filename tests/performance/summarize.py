#!/usr/bin/env python3
"""Summarize raw PERF_SAMPLE lines without manufacturing small-sample percentiles."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import statistics


def summarize(text):
    groups = defaultdict(list)
    for name, value in re.findall(r'PERF_SAMPLE ([a-zA-Z0-9_]+) ([0-9.]+) ms', text):
        number = float(value)
        if math.isfinite(number) and number >= 0:
            groups[name].append(number)
    return {name: dict(n=len(samples), samples_ms=samples, median_ms=statistics.median(samples),
                       min_ms=min(samples), max_ms=max(samples), p95_ms=None)
            for name, samples in sorted(groups.items())}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(summarize(args.log.read_text(errors='replace')), indent=2) + '\n')
