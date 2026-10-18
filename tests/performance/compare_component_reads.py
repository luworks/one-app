#!/usr/bin/env python3
"""Compare JSON PERF_SAMPLE activity reads, never app latency.

Context accepts record_command JSON (exit_code, host.hardware, command, cwd,
host.revision) augmented with top-level configuration, optimization, build_source
(e.g. own-source), cache, global_quiet (boolean true). These declarations must
match; hardware is stripped before comparison. Optional toolchain must match if
present. Revisions/cwd may differ and are retained, not compared. No percentiles.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

CONTEXT_KEYS = ("configuration", "optimization", "build_source", "cache", "global_quiet")
SAMPLE_KEYS = ("fixture", "rows", "page_size", "iterations", "cache", "clock", "unit")
METHOD = "testWarmPageReads"


def samples(text):
    groups = {}
    for line in text.splitlines():
        match = re.search(r"PERF_SAMPLE\s+(\{.*\})\s*$", line)
        if not match:
            continue
        record = json.loads(match[1])
        metric = record.get("metric", "")
        if not metric.startswith("activity_read_"):
            continue
        if any(key not in record for key in SAMPLE_KEYS + ("sample", "n", "value", "batch_ms")):
            raise ValueError("missing sample fields: " + metric)
        for key in ("sample", "n", "rows", "page_size", "iterations"):
            if type(record[key]) is not int or record[key] < 1:
                raise ValueError("invalid integer: " + key)
        for key in ("value", "batch_ms"):
            value = record[key]
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError("invalid duration: " + key)
        if not math.isclose(record["value"] * record["iterations"], record["batch_ms"], rel_tol=1e-8, abs_tol=1e-8):
            raise ValueError("batch/value mismatch")
        by_sample = groups.setdefault(metric, {})
        previous = by_sample.get(record["sample"])
        if previous is not None and previous != record:
            raise ValueError("conflicting duplicate sample: " + metric)
        by_sample[record["sample"]] = record
    passed = bool(re.search(r"Test Case '-\[\S*ActivityReadPerformanceTests " + METHOD + r"\]' passed\b", text))
    failed = bool(re.search(r"Test Case '-\[\S*ActivityReadPerformanceTests " + METHOD + r"\]' (?:failed|skipped)\b", text))
    result = {}
    for metric, records in groups.items():
        ordered = [records[key] for key in sorted(records)]
        first = ordered[0]
        for row in ordered:
            if any(row[key] != first[key] for key in SAMPLE_KEYS + ("n",)):
                raise ValueError("inconsistent sample context: " + metric)
        values = [row["value"] for row in ordered]
        sufficient = (3 <= len(values) <= 5 and first["n"] == len(values)
                      and sorted(records) == list(range(1, len(values) + 1)))
        result[metric] = dict(n=len(values), raw=values, median=statistics.median(values),
                              range=dict(min=min(values), max=max(values)), records=ordered,
                              sample_context={key: first[key] for key in SAMPLE_KEYS},
                              sample_count_sufficient=sufficient, functional_pass=passed and not failed)
    return result


def compare(before, after, before_context, after_context):
    for key in CONTEXT_KEYS:
        if before_context.get(key) in (None, "") or before_context[key] != after_context.get(key):
            raise ValueError("incomparable context: " + key)
    if before_context["global_quiet"] is not True:
        raise ValueError("global_quiet must be true")
    hardware = [context.get("host", {}).get("hardware", "").strip() for context in (before_context, after_context)]
    if not hardware[0] or hardware[0] != hardware[1]:
        raise ValueError("incomparable context: host.hardware")
    if before_context.get("toolchain") != after_context.get("toolchain"):
        raise ValueError("incomparable context: toolchain")
    if not before or not after:
        raise ValueError("no activity_read JSON samples")
    command_pass = all(type(context.get("exit_code")) is int and context["exit_code"] == 0
                       for context in (before_context, after_context))
    metrics = {}
    for metric in sorted(before.keys() & after.keys()):
        a, b = before[metric], after[metric]
        if a["sample_context"] != b["sample_context"]:
            raise ValueError("incomparable sample context: " + metric)
        if a["sample_context"]["cache"] != before_context["cache"]:
            raise ValueError("sample/context cache mismatch")
        ratio = a["median"] / b["median"] if b["median"] > 0 else None
        valid = command_pass and a["functional_pass"] and b["functional_pass"]
        valid = valid and a["sample_count_sufficient"] and b["sample_count_sufficient"]
        metrics[metric] = dict(before=a, after=b, median_ratio=ratio, acceptance_eligible=bool(valid),
                               required_3x_met=bool(valid and ratio is not None and ratio >= 3),
                               stretch_10x_met=bool(valid and ratio is not None and ratio >= 10))
    missing_after, missing_before = sorted(before.keys() - after.keys()), sorted(after.keys() - before.keys())
    return dict(schema_version=1, scope="amortized warm host SQLite component reads; not app/UI latency",
                before_context=before_context, after_context=after_context, command_pass=command_pass,
                metrics=metrics, missing_after=missing_after, missing_before=missing_before,
                all_required_3x_met=bool(metrics and not missing_after and not missing_before
                                         and all(row["required_3x_met"] for row in metrics.values())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("before", "after", "before-context", "after-context", "output"):
        parser.add_argument("--" + flag, type=Path, required=True)
    args = parser.parse_args()
    paths = [args.before, args.after, args.before_context, args.after_context]
    raw = [path.read_bytes() for path in paths]
    result = compare(samples(raw[0].decode(errors="replace")), samples(raw[1].decode(errors="replace")),
                     json.loads(raw[2]), json.loads(raw[3]))
    result["sources"] = [dict(path=str(path.resolve()), sha256=hashlib.sha256(data).hexdigest())
                         for path, data in zip(paths, raw)]
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write("\n")


if __name__ == "__main__":
    main()
