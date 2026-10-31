"""Frozen manifests and independently shuffled, position-balanced run order."""
import argparse
from datetime import datetime, timezone
import hashlib
import itertools
import json
from pathlib import Path
import platform
import random
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def schedule(case_ids, candidates, *, seed, repetitions=1):
    if len(set(case_ids)) != len(case_ids) or len(set(candidates)) != len(candidates):
        raise ValueError("IDs and candidates must be unique")
    if not candidates or not case_ids or repetitions < 1:
        raise ValueError("Empty schedule")
    # Independent RNG streams: case order cannot accidentally determine candidate
    # order. Across each n repetitions every architecture occupies each position.
    cases_rng, order_rng = random.Random(seed), random.Random(seed ^ 0x9E3779B9)
    base = list(candidates)
    order_rng.shuffle(base)
    offsets = {case: order_rng.randrange(len(base)) for case in sorted(case_ids)}
    tasks = []
    for repeat in range(repetitions):
        cases = list(case_ids)
        cases_rng.shuffle(cases)
        for index, case_id in enumerate(cases):
            shift = (repeat + offsets[case_id]) % len(base)
            order = base[shift:] + base[:shift]
            if (repeat // len(base)) % 2:
                order = list(reversed(order))
            tasks.extend({"case_id": case_id, "candidate": candidate, "repetition": repeat,
                          "position": position} for position, candidate in enumerate(order))
    return tasks


def manifest(fixtures, candidates, *, split, seed, repetitions=1):
    if split not in ("development", "holdout"):
        raise ValueError("Explicit development/holdout split required")
    paths = [Path(p) for p in fixtures]
    cases = []
    for path in paths:
        data = json.loads(path.read_text())
        rows = data if isinstance(data, list) else data.get("journeys", data.get("cases", [data]))
        cases.extend(row["id"] for row in rows if row.get("split", data.get("split") if isinstance(data, dict) else None) == split)
    source = Path(__file__).parent
    files = [p for p in source.rglob("*") if p.suffix in (".py", ".mjs", ".json") and "node_modules" not in p.parts]
    return {"schema_version": "architecture-run-v1", "created_utc": datetime.now(timezone.utc).isoformat(),
            "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
            "python": platform.python_version(), "platform": platform.platform(), "split": split,
            "seed": seed, "repetitions": repetitions, "candidates": candidates,
            "fixtures": {str(p): digest(p) for p in paths},
            "source_sha256": {str(p): digest(p) for p in files},
            "schedule": schedule(cases, candidates, seed=seed, repetitions=repetitions),
            "paid_evaluation": "pending", "performance_scope": "Linux portable prototype process only"}


def verify_frozen(value):
    for field in ("fixtures", "source_sha256"):
        for path, expected in value[field].items():
            if digest(path) != expected:
                raise ValueError("Frozen input changed: " + path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", nargs="+", type=Path, required=True)
    parser.add_argument("--candidates", nargs="+", required=True)
    parser.add_argument("--split", choices=("development", "holdout"), required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    value = manifest(args.fixtures, args.candidates, split=args.split, seed=args.seed, repetitions=args.repetitions)
    # Never overwrite the provenance of a completed/frozen experiment.
    with args.output.open("x") as stream:
        json.dump(value, stream, indent=2)


if __name__ == "__main__":
    main()
