#!/usr/bin/env python3
"""Observe frozen Live cases without clicking Add/Apply or inferring quality."""
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
    parser.add_argument('--fixture', choices=['ai-chat-capability-eval.json',
        'intelligence-live-product-extension.json', 'intelligence-live-edit-seed.json'],
        default='intelligence-live-product-extension.json')
    parser.add_argument('--case', action='append', required=True)
    parser.add_argument('--undo-created-oneoffs', action='store_true',
        help='After observation, Undo only a uniquely traced direct creation in its fresh chat')
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to(results_root().resolve()):
        raise SystemExit('Use primary results')
    args.output.mkdir(exist_ok=False)
    fixture = ROOT / 'tests/fixtures' / args.fixture
    raw = fixture.read_bytes()
    cases = {c['id']: c for c in json.loads(raw)['cases']}
    if len(set(args.case)) != len(args.case) or any(key not in cases for key in args.case):
        raise SystemExit('Select distinct cases from the frozen development fixture')
    journal = Journal()
    session = 'intelligence-selection-20261029'
    observations = []
    cleanup = []
    index = 0

    def step(*command, settle=0):
        nonlocal index
        index += 1
        if command[0] == 'snapshot':
            command = (*command, '--timeout', '15000')
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
            case_calls = []
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
                case_calls.extend(calls)
                shot = args.output / f'{key}-turn{turn}.png'
                step('screenshot', str(shot))
                journal.artifact(session, shot)
                observations.append(dict(case=key, turn=turn, input=item['input'],
                    turn_trace=token, calls=calls, snapshot=snapshot, screenshot=str(shot),
                    submit_to_observation_upper_bound_ms=(time.monotonic()-started)*1000,
                    quality='UNREVIEWED', generation='Use actual call events, not this observation status'))
                expected_action = item.get('expect', {}).get('action')
                direct_allowed = expected_action in ('added_reminder', 'clarify_or_reminder')
                granted = any(row['event'] == 'rule_direct_grant_selected' for call in calls for row in call)
                # Prior receipts can remain visible during a legitimate follow-up; only
                # a newly granted write or a first-turn receipt is a fresh creation signal.
                first_turn_receipt = turn == 0 and re.search(
                    r'\[button\] "(?:Undo|capture-undo)', snapshot)
                if not direct_allowed and (granted or first_turn_receipt):
                    raise RuntimeError('Unexpected creation/grant; inspect exact receipt before cleanup')
                print(f'Observed {key} turn{turn + 1}; quality not auto-passed', flush=True)
            if args.undo_created_oneoffs:
                grants = [row for call in case_calls for row in call
                          if row['event'] == 'rule_direct_grant_selected']
                if len(grants) > 1:
                    raise RuntimeError('Multiple direct creations; inspect exact receipts before cleanup')
                if grants:
                    # No Add/Apply is ever clicked. One traced direct creation in this
                    # fresh chat must have exactly one current Added receipt and Undo.
                    if len(re.findall(r'\[other\] "Added:', snapshot)) != 1:
                        raise RuntimeError('Direct creation receipt is not uniquely identifiable')
                    step('click', ref(snapshot, 'button', 'Undo'), settle=1)
                    undone = step('snapshot', '-i')
                    if '[text] "Undone"' not in undone or '[button] "Add again"' not in undone:
                        raise RuntimeError('Exact receipt Undo did not reach the observed Undone state')
                    shot = args.output / f'{key}-after-undo.png'
                    step('screenshot', str(shot))
                    journal.artifact(session, shot)
                    cleanup.append(dict(case=key, grant_call=grants[0]['call'], snapshot=undone,
                                        screenshot=str(shot), scope='Exact current-chat receipt only'))
    finally:
        report = args.output / 'observations.json'
        report.write_text(json.dumps(dict(fixture=str(fixture), fixture_sha256=hashlib.sha256(raw).hexdigest(),
            scope='Live UI observations only; human field/safety review required. Observation bound is not exact UI latency.',
            requested_cases=args.case, rows=observations, receipt_cleanup=cleanup), ensure_ascii=False, indent=2))
        journal.artifact(session, report)
        journal.close()


if __name__ == '__main__':
    main()
