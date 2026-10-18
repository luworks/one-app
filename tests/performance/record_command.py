#!/usr/bin/env python3
"""Run one command with durable raw output, host context, and QA Activity indexing."""
import argparse
import datetime
import json
from pathlib import Path
import shlex
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'qa'))
from journal import Journal, results_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', default='performance-baseline-20261018')
    parser.add_argument('--label', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or Path(args.label).name != args.label:
        parser.error('provide a simple label and a command after --')
    output = results_root() / 'runs' / args.session
    output.mkdir(parents=True, exist_ok=True)
    stem = f'{args.label}-{uuid.uuid4().hex[:8]}'
    log = output / (stem + '.log')
    context = dict(command=command, cwd=str(Path.cwd()), start=datetime.datetime.now(datetime.timezone.utc).isoformat())
    context['host'] = {name: subprocess.run(cmd, capture_output=True, text=True).stdout for name, cmd in [
        ('load', ['uptime']), ('processes', ['ps', '-axo', 'pid,ppid,%cpu,%mem,comm']),
        ('hardware', ['sysctl', 'hw.model', 'hw.memsize', 'hw.ncpu']), ('revision', ['git', 'rev-parse', 'HEAD'])]}
    journal = Journal()
    subject = uuid.uuid4().hex
    journal.record(args.session, 'qa.command.started', shlex.join(command), subject=subject)
    with log.open('w') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    context.update(exit_code=result.returncode, end=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (output / (stem + '.json')).write_text(json.dumps(context, indent=2) + '\n')
    journal.record(args.session, 'qa.command.completed', str(log), subject=subject,
                   status='passed' if result.returncode == 0 else 'failed', props={'exit_code': result.returncode})
    print(json.dumps(dict(log=str(log), exit_code=result.returncode)))
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
