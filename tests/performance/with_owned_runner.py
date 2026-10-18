#!/usr/bin/env python3
"""Use the E2E runner's named simulator/cache locks for a direct focused command."""
import argparse
import fcntl
import hashlib
from pathlib import Path
import subprocess
import tempfile

from simulator_policy import validate_command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator-name', required=True)
    parser.add_argument('--derived-data', required=True, type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('requires a command')
    try:
        validate_command(args.simulator_name, command)
    except ValueError as error:
        parser.error(str(error))
    locks = []
    try:
        for key in sorted(['name:' + args.simulator_name, 'cache:' + str(args.derived_data.resolve())]):
            path = Path(tempfile.gettempdir()) / ('today-qa-lock-' + hashlib.sha256(key.encode()).hexdigest())
            lock = path.open('a')
            locks.append(lock)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return subprocess.run(command).returncode
    finally:
        for lock in reversed(locks):
            lock.close()


if __name__ == '__main__':
    raise SystemExit(main())
