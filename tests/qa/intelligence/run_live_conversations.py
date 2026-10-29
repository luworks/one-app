#!/usr/bin/env python3
"""Observe frozen conversation cases in Live UI; never grade from call availability."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tests.qa.journal import Journal, results_root
from collect_product import collect


def ref(snapshot, kind, label):
    matches = re.findall(r'^\s*(@e\d+) \[' + kind + r'\] "' + re.escape(label) + r'"', snapshot, re.M)
    if len(matches) != 1:
        raise RuntimeError(f'Expected one visible {kind}: {label}; observed {len(matches)}')
    return matches[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native-log', type=Path, required=True)
    parser.add_argument('--case', action='append', required=True)
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to(results_root().resolve()):
        raise SystemExit('Use primary results')
    args.output.mkdir(exist_ok=False)
    fixture = ROOT / 'tests/fixtures/intelligence-live-product-extension.json'
    raw = fixture.read_bytes()
    cases = {c['id']: c for c in json.loads(raw)['cases']}
    if len(set(args.case)) != len(args.case) or any(
            key not in cases or cases[key]['category'] not in ('conversation', 'conversation-context')
            for key in args.case):
        raise SystemExit('This runner only observes distinct frozen conversation cases')
    journal = Journal()
    session = 'intelligence-selection-20261029'
    observations = []
    index = 0

    def step(*command, settle=0):
        nonlocal index
        index += 1
        log = args.output / f'{index:03d}-{command[0]}.log'
        result = subprocess.run([
            sys.executable, str(Path(__file__).with_name('live_step.py')),
            '--config', str(args.config), '--output', str(log),
            '--settle-seconds', str(settle), '--', *command,
        ], capture_output=True, text=True, cwd=ROOT)
        if result.returncode:
            raise RuntimeError(f'UI operation failed; no retry: {log}\n{result.stdout}{result.stderr}')
        return result.stdout

    def trace():
        # A still-writing final line is not evidence until its newline arrives.
        text = args.native_log.read_text()
        return collect(text[:text.rfind('\n') + 1])

    try:
        for key in args.case:
            case = cases[key]
            snapshot = step('snapshot', '-i')
            if '[button] "Close sidebar"' not in snapshot:
                step('click', ref(snapshot, 'button', 'Open menu'))
                snapshot = step('snapshot', '-i')
            if '[button] "Close sidebar"' not in snapshot:
                raise RuntimeError('Sidebar did not become visibly open')
            step('click', ref(snapshot, 'button', 'New chat'), settle=3)
            snapshot = step('snapshot', '-i')
            if 'What do you want to plan?' not in snapshot or 'Copy message' in snapshot:
                raise RuntimeError('Fresh conversation not established')
            for turn, item in enumerate(case['turns']):
                inputs = re.findall(r'^\s*(@e\d+) \[text-view\].*\[editable\]', snapshot, re.M)
                if len(inputs) != 1:
                    raise RuntimeError('Expected one composer')
                step('fill', inputs[0], item['input'])
                snapshot = step('snapshot', '-i')
                before = set(trace()['turns'])
                started = time.monotonic()
                step('click', ref(snapshot, 'button', 'Send'), settle=12)
                snapshot = step('snapshot', '-i')
                while 'Thinking…' in snapshot and time.monotonic() - started < 45:
                    time.sleep(.5)
                    snapshot = step('snapshot', '-i')
                if 'Thinking…' in snapshot:
                    raise TimeoutError('Visible thinking exceeded observation bound')
                evidence = trace()
                new = set(evidence['turns']) - before
                if len(new) != 1:
                    raise RuntimeError('Submitted turn trace not uniquely reconciled')
                token = new.pop()
                calls = [evidence['calls'][call] for call in evidence['turns'][token]]
                shot = args.output / f'{key}-turn{turn}.png'
                step('screenshot', str(shot))
                journal.artifact(session, shot)
                observations.append(dict(case=key, turn=turn, input=item['input'],
                    turn_trace=token, calls=calls, snapshot=snapshot, screenshot=str(shot),
                    submit_to_observation_upper_bound_ms=(time.monotonic()-started)*1000,
                    quality='UNREVIEWED', generation='Use actual call events, not this observation status'))
                if any(row['event'] == 'rule_direct_grant_selected' for call in calls for row in call) or re.search(
                        r'\[button\] "(?:Undo|capture-undo)', snapshot):
                    raise RuntimeError('Unexpected creation/grant in conversation; inspect exact receipt before cleanup')
                print(f'Observed {key} turn{turn + 1}; quality not auto-passed', flush=True)
    finally:
        report = args.output / 'observations.json'
        report.write_text(json.dumps(dict(fixture=str(fixture), fixture_sha256=hashlib.sha256(raw).hexdigest(),
            scope='Live UI observations only; human field/safety review required. Observation bound is not exact UI latency.',
            requested_cases=args.case, rows=observations), ensure_ascii=False, indent=2))
        journal.artifact(session, report)
        journal.close()


if __name__ == '__main__':
    main()
