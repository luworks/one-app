#!/usr/bin/env python3
"""Sample owned simulator app RSS while a command runs; RSS is not physical footprint."""
import argparse
import csv
import datetime
from pathlib import Path
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('command required')
    stop = threading.Event()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def sample():
        with args.output.open('w') as stream:
            writer = csv.writer(stream)
            writer.writerow(['utc', 'pid', 'rss_kib'])
            while not stop.is_set():
                raw = subprocess.run(['ps', '-axo', 'pid=,rss=,comm='], capture_output=True, text=True).stdout
                for line in raw.splitlines():
                    fields = line.split(maxsplit=2)
                    if len(fields) == 3 and f'/Devices/{args.simulator}/' in fields[2] and fields[2].endswith('/One.app/One'):
                        writer.writerow([datetime.datetime.now(datetime.timezone.utc).isoformat(), *fields[:2]])
                        stream.flush()
                stop.wait(0.5)

    thread = threading.Thread(target=sample)
    thread.start()
    try:
        return subprocess.run(command).returncode
    finally:
        stop.set()
        thread.join()


if __name__ == '__main__':
    raise SystemExit(main())
