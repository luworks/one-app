#!/usr/bin/env python3
"""Extract XCTest raw measurements, preserving units and functional attempt gates.

No percentiles are estimated. Physical delta (including negative values), peak
physical, absolute physical and scroll duration remain separate measurements.
Scroll duration does not establish hitch rate or FPS; physical delta alone does
not establish a leak or retained memory. Optional MiB conversion assumes printed
`kB` means decimal 1000 bytes, then divides by 1048576 bytes/MiB.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics


CASE = r"Test Case '-\[(?P<suite>\S+) (?P<method>[^\]]+)\]'"
MEASUREMENT = re.compile(
    CASE + r" measured \[(?P<label>.+),\s*(?P<unit>[^,\]]+)\]"
    r".*?values:\s*\[(?P<values>[^\]]*)\],\s*performanceMetricID:\s*(?P<metric_id>[^,\s]+)"
)
OUTCOME = re.compile(CASE + r" (?P<status>started|passed|failed|skipped)\b")


def summary(values):
    return {"n": len(values), "raw": values, "median": statistics.median(values),
            "range": {"min": min(values), "max": max(values)}}


def metric_kind(metric_id):
    if "XCTMetric_Memory-" in metric_id:
        return {"physical_peak": "peak_physical", "physical": "physical_delta",
                "physical_absolute": "absolute_physical"}.get(metric_id.rsplit(".", 1)[-1], "unclassified")
    if "XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.duration" in metric_id:
        return "scroll_duration"
    return "unclassified"


def extract(text, include_mib=False):
    attempts = []
    current = {}
    counts = {}
    seen = {}

    def new_attempt(key, observed_start):
        counts[key] = counts.get(key, 0) + 1
        row = {"suite": key[0], "method": key[1], "attempt": counts[key],
               "observed_start": observed_start, "status": "incomplete",
               "functional_passed": False, "metrics": []}
        current[key] = row
        attempts.append(row)
        seen[id(row)] = set()
        return row

    for line_number, line in enumerate(text.splitlines(), 1):
        measured = MEASUREMENT.search(line)
        if measured:
            fields = measured.groupdict()
            key = (fields["suite"], fields["method"])
            row = current.get(key) or new_attempt(key, False)
            try:
                values = [float(value.strip()) for value in fields["values"].split(",")]
            except ValueError as error:
                raise ValueError(f"invalid measurement values on line {line_number}") from error
            if not values or not all(math.isfinite(value) for value in values):
                raise ValueError(f"non-finite or empty measurement on line {line_number}")
            label, unit, metric_id = (fields[name].strip() for name in ("label", "unit", "metric_id"))
            identity = (label, unit, metric_id, tuple(values))
            if identity in seen[id(row)]:
                # Reprinted stdout is not a fresh XCTest measurement iteration.
                for metric in row["metrics"]:
                    if (metric["label"], metric["unit"], metric["metric_id"], tuple(metric["raw"])) == identity:
                        metric["duplicate_lines"].append(line_number)
                        break
                continue
            seen[id(row)].add(identity)
            metric = {"label": label, "unit": unit, "metric_id": metric_id,
                      "kind": metric_kind(metric_id), "line": line_number,
                      "duplicate_lines": [], **summary(values)}
            if include_mib and unit == "kB":
                metric["derived_mib"] = {
                    "unit": "MiB", "assumption": "kB = 1000 bytes; MiB = 1048576 bytes",
                    **summary([value * 1000 / 1048576 for value in values])}
            row["metrics"].append(metric)
            continue
        outcome = OUTCOME.search(line)
        if outcome:
            key = (outcome["suite"], outcome["method"])
            status = outcome["status"]
            if status == "started":
                new_attempt(key, True)
            else:
                row = current.get(key) or new_attempt(key, False)
                # A conflicting/reprinted pass must not erase a failure.
                if row["status"] != "failed":
                    row["status"] = status
                row["functional_passed"] = row["observed_start"] and row["status"] == "passed"
        elif "Test Case '" in line and " measured [" in line:
            raise ValueError(f"unrecognized XCTest measurement on line {line_number}")
    return {"schema_version": 1, "attempts": attempts,
            "notes": ["No p95 or other percentiles estimated.",
                      "Functional gates apply to individual method attempts; failed/incomplete samples are retained.",
                      "Physical delta is not leak/retention evidence; scroll duration is not FPS/hitch evidence."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-mib", action="store_true", help="derive MiB only for explicit decimal kB")
    args = parser.parse_args()
    raw = args.log.read_bytes()
    result = extract(raw.decode("utf-8", errors="replace"), include_mib=args.include_mib)
    result["source"] = {"path": str(args.log.resolve()), "sha256": hashlib.sha256(raw).hexdigest()}
    # Evidence outputs are new files; existing indexed logs/results are never overwritten.
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, indent=2, ensure_ascii=False, allow_nan=False)
        output.write("\n")


if __name__ == "__main__":
    main()
