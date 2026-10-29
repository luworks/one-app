#!/usr/bin/env python3
"""One bounded owned-simulator UI operation; no idle lock reservation."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.devtools.core import host_lock, dd_lock, worktree_id, ResourceBusy
from tests.qa.journal import Journal, results_root


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--settle-seconds', type=float, default=0)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text())
    device = cfg['device']
    if device['physical'] is not False or device['name'] != 'Today-Dev-' + worktree_id(ROOT)[:8]:
        raise SystemExit('Only the worktree-owned simulator is permitted')
    uuid.UUID(device['id'])
    flags = cfg['agentDevice']['targetArgs']
    if flags.count('--udid') != 1 or flags[flags.index('--udid') + 1] != device['id']:
        raise SystemExit('Pinned launcher device mismatch')
    if not args.output.resolve().is_relative_to(results_root().resolve()):
        raise SystemExit('Evidence must stay in primary results')
    if args.output.exists() or not args.output.parent.is_dir():
        raise SystemExit('Use a fresh log path in an existing evidence directory')
    if not 0 <= args.settle_seconds <= 25 or not args.command:
        raise SystemExit('A bounded UI command is required')
    command = args.command[1:] if args.command[0] == '--' else args.command
    if not command or command[0] not in {'open', 'close', 'snapshot', 'click', 'fill',
                                        'press', 'scroll', 'screenshot', 'record', 'alert'}:
        raise SystemExit('Unsupported evaluation operation')
    if any(token == flag or token.startswith(flag + '=')
           for token in command for flag in ['--udid', '--platform', '--config', '--session']):
        raise SystemExit('Target overrides are forbidden')
    argv = [cfg['agentDevice']['command'], *command, *flags]
    journal = Journal()
    session = 'intelligence-selection-20261029'
    journal.record(session, 'qa.ui.operation', json.dumps(argv, ensure_ascii=False), status='started')
    started = time.monotonic()
    command_started = False
    try:
        with host_lock(ROOT), dd_lock(ROOT):
            command_started = True
            try:
                result = subprocess.run(argv, capture_output=True, text=True, timeout=90)
            except subprocess.TimeoutExpired as error:
                def text(value):
                    return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
                result = subprocess.CompletedProcess(
                    argv, 124, text(error.stdout), text(error.stderr) + '\nOwned UI operation timed out; not retried.\n')
            if result.returncode == 0 and args.settle_seconds:
                time.sleep(args.settle_seconds)  # Bounded observation window, never analysis time.
    except ResourceBusy as error:
        result = subprocess.CompletedProcess(argv, 75, '', str(error) + '\nUI command not executed.\n')
    elapsed = time.monotonic() - started
    with args.output.open('x') as out:
        out.write(json.dumps(dict(command=argv, operation_seconds=elapsed, command_started=command_started), ensure_ascii=False)
                  + '\n' + result.stdout + result.stderr)
    journal.artifact(session, args.output)
    journal.record(session, 'qa.ui.operation', str(args.output),
                   status='passed' if result.returncode == 0 else
                   'interrupted' if result.returncode in (75, 124) else 'failed')
    journal.close()
    print(result.stdout + result.stderr)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
