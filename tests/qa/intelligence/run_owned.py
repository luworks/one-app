#!/usr/bin/env python3
"""Run one bounded batch through the exact launcher returned by device_open."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.devtools.core import host_lock, dd_lock, worktree_id
from tests.qa.journal import Journal, results_root
from collect import collect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device-config', type=Path, required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--button', required=True)
    parser.add_argument('--expected', type=int, required=True)
    parser.add_argument('--output-stem', type=Path, required=True)
    parser.add_argument('--max-seconds', type=int, default=3600)
    args = parser.parse_args()
    cfg = json.loads(args.device_config.read_text())
    device = cfg['device']
    if device['physical'] is not False or device['name'] != 'Today-Dev-' + worktree_id(ROOT)[:8]:
        raise SystemExit('Only this worktree-owned simulator is permitted')
    launcher = cfg['agentDevice']
    prefix = [launcher['command']]
    flags = launcher['targetArgs']
    uuid.UUID(device['id'])  # Recent physical iPhone identifiers are not simulator UUIDs.
    if flags.count('--udid') != 1 or flags[flags.index('--udid') + 1] != device['id']:
        raise SystemExit('Launcher target does not match the owned simulator record')
    if not args.output_stem.resolve().is_relative_to(results_root().resolve()):
        raise SystemExit('Evidence must be retained in the primary checkout results directory')
    if args.expected <= 0 or args.max_seconds <= 0:
        raise SystemExit('Positive record count and bounded runtime are required')
    log = args.output_stem.with_suffix('.log')
    actions = args.output_stem.with_suffix('.actions.log')
    report = args.output_stem.with_suffix('.evidence.json')
    if any(p.exists() for p in (log, actions, report)):
        raise SystemExit('Use a fresh durable output stem')
    journal = Journal()
    session = 'intelligence-selection-20261029'
    journal.record(session, 'qa.command', subprocess.list2cmdline(sys.argv), status='started')
    completed = False
    try:
        with actions.open('x') as action_file:
            def agent(*command):
                result = subprocess.run([*prefix, *command, *flags], capture_output=True,
                                        text=True, timeout=90)
                action_file.write(json.dumps(command) + '\n' + result.stdout + result.stderr + '\n')
                action_file.flush()
                if result.returncode:
                    raise RuntimeError(f'agent-device {command[0]} failed: {result.stderr}')
                return result.stdout

            def click(label):
                snapshot = agent('snapshot', '-i')
                match = re.search(r'^\s*(@e\d+) \[(?:button|cell)\] "' + re.escape(label) + r'"',
                                  snapshot, re.M)
                if not match:
                    raise RuntimeError(f'Visible control missing: {label}')
                agent('click', match[1])

            with host_lock(ROOT), dd_lock(ROOT), log.open('x') as stream:
                logger = subprocess.Popen([
                    'xcrun', 'simctl', 'spawn', device['id'], 'log', 'stream', '--style', 'compact',
                    '--level', 'debug', '--predicate', 'subsystem == "com.luworks.today.eval"'],
                    stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
                started = time.monotonic()
                try:
                    agent('open', 'com.bachittle.llama-swift')
                    if args.model.startswith('Qwen'):
                        click('View Models')
                        click('Load ' + args.model.removesuffix('.gguf'))
                        click('Model Settings')
                        while 'Loaded model ' + args.model not in agent('snapshot', '-i'):
                            if time.monotonic() - started > 180:
                                raise TimeoutError('Model loading exceeded startup bound')
                    click(args.button)
                    print('Batch submitted; actual log monitored, no idle reservation', flush=True)
                    previous = -1
                    while time.monotonic() - started < args.max_seconds:
                        text = log.read_text(errors='replace')
                        evidence = collect(text)
                        runs = evidence['runs']
                        if runs:
                            run = runs[0]
                            if len(runs) != 1 or run['model'] != args.model or run['expected'] != args.expected:
                                raise RuntimeError('Unexpected backend or batch mode')
                            if run['observed'] != previous:
                                previous = run['observed']
                                print(f"Observed {previous}/{args.expected}", flush=True)
                            if run['complete']:
                                if not evidence['valid']:
                                    raise RuntimeError('Completed transport failed validation')
                                with report.open('x') as file:
                                    json.dump(evidence, file, ensure_ascii=False, indent=2)
                                break
                        if 'TODAY_EVAL_START ' not in text and time.monotonic() - started > 180:
                            raise TimeoutError('Batch did not start')
                        time.sleep(1)
                    else:
                        raise TimeoutError('External batch bound exceeded')
                finally:
                    try:
                        agent('close', 'com.bachittle.llama-swift')
                    finally:
                        os.killpg(logger.pid, signal.SIGTERM)
                        logger.wait(timeout=10)
            print('Owned app closed; host and derived-data locks released', flush=True)
        completed = True
    finally:
        for path in (log, actions, report):
            if path.exists():
                journal.artifact(session, path)
        journal.record(session, 'qa.batch', str(report), status='completed' if completed else 'failed')
        journal.close()


if __name__ == '__main__':
    main()
