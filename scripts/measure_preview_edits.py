#!/usr/bin/env python3
"""Three reversible Health view edits; run only inside the preview's resource window."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/qa'))
from journal import Journal

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('run', type=Path, help='The current swiftui_preview.py evidence directory')
p.add_argument('--timeout', type=int, default=35)
args = p.parse_args()
source = ROOT / 'ios/One/HealthMetricDetail.swift'
original = source.read_bytes()
needle = b'.navigationTitle(metric.title)'
if original.count(needle) != 1:
    raise SystemExit('Expected one unchanged production navigation title')
run = args.run.resolve()
owner = json.loads((run / 'ownership.json').read_text())
if Path(owner['worktree']) != ROOT:
    raise SystemExit('Run belongs to another worktree')
session = run.name
journal = Journal()


def events():
    return [json.loads(s) for s in (run / 'timings.jsonl').read_text().splitlines()]


def wait_capture(after):
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        found = [e for e in events() if e['event'] == 'watch.captured' and e['time'] > after]
        if found:
            return found[-1]
        time.sleep(0.2)
    raise RuntimeError('No successful axe reload and captured frame before timeout')


if not any(e['event'] == 'watch.captured' for e in events()):
    raise SystemExit('Wait for the strict watch initial captured frame before editing')
try:
    for i in range(1, 4):
        changed = original.replace(needle, f'.navigationTitle("Weight Preview {i}")'.encode())
        start = time.time()
        source.write_bytes(changed)
        journal.record(session, 'qa.development', f'Temporary production Health view title edit {i}; no manual navigation', props={'sourceSha256': hashlib.sha256(changed).hexdigest(), 'editTime': start})
        event = wait_capture(start)
        image = run / f'edit-{i}.png'
        shutil.copy2(run / 'gallery/live.png', image)
        result = {'sample': i, 'editTime': start, 'captureTime': event['time'], 'seconds': event['time'] - start,
                  'sourceSha256': hashlib.sha256(changed).hexdigest(), 'image': str(image)}
        with (run / 'edit-measurements.jsonl').open('a') as output:
            output.write(json.dumps(result) + '\n')
        journal.artifact(session, image)
        print(json.dumps(result), flush=True)
finally:
    start = time.time()
    source.write_bytes(original)
    journal.record(session, 'qa.development', 'Restored the exact original Health view source', props={'sourceSha256': hashlib.sha256(original).hexdigest()})
    try:
        event = wait_capture(start)
        image = run / 'edit-reverted.png'
        shutil.copy2(run / 'gallery/live.png', image)
        journal.artifact(session, image)
        print(json.dumps({'reverted': True, 'seconds': event['time'] - start}), flush=True)
    finally:
        journal.close()
