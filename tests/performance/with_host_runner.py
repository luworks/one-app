#!/usr/bin/env python3
"""Run one jobs2 Swift test under the shared Swift mutex after an explicit heavy handoff."""
import argparse
import fcntl
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    jobs = [command[i + 1] for i, value in enumerate(command[:-1]) if value == '--jobs']
    if not command or command[0] != 'test' or jobs != ['2'] or any(x.startswith('--jobs=') for x in command):
        parser.error('requires test with exactly --jobs 2')
    if not Path('Package.swift').is_file():
        parser.error('run from the assigned ios package directory')
    # Same mutex as the existing overnight runner; never wait while holding another lane's slot.
    with open('/tmp/today-overnight-swift.lock', 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('Swift mutex is held; no Swift process started.')
            return 75
        if os.getloadavg()[0] > 30:
            print('Host one-minute load exceeds 30; no Swift process started.')
            return 75
        return subprocess.run(['swift', *command]).returncode


if __name__ == '__main__':
    raise SystemExit(main())
