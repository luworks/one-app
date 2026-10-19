#!/usr/bin/env python3
"""Small standalone compiler contract; no SwiftPM, Xcode or simulator."""
import argparse
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
CANONICAL = Path('/Users/yuanlu/code/one-app/tests/results')
BASE = 'bc32cee41e5b87386df571fd7f6caa61671bbe7d'
FILES = ['ActivityOutbox.swift', 'LockScreenNext.swift', 'NextUpSpeech.swift',
         'ShareInbox.swift', 'TravelTime.swift', 'WidgetSnapshot.swift']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--module-dir', type=Path, help='Reuse an already compiled Swift 6 TodayShared module/library')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('qa_journal', ROOT / 'tests/qa/journal.py')
    qa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qa)
    journal = qa.Journal(CANONICAL / 'activity.sqlite')
    session = 'shared-module-' + uuid.uuid4().hex[:10]
    output = CANONICAL / 'reconstruction' / session
    output.mkdir(parents=True)
    with (CANONICAL / 'reconstruction/heavy.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            journal.record(session, 'qa.command.shared-module', 'heavy.lock busy; no compiler started', status='interrupted')
            return 75
        log = output / 'commands.log'

        def run(command):
            result = subprocess.run(command, cwd=ROOT, env=os.environ.copy(), text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            with log.open('a') as stream:
                stream.write(f'COMMAND: {command!r}\n{result.stdout}\nEXIT: {result.returncode}\n')
            if result.returncode:
                raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
            print(result.stdout, end='')

        try:
            journal.record(session, 'qa.command.shared-module', f'Baseline {BASE}; output {output}; reused module {args.module_dir}', status='running')
            baseline = output / 'baseline'
            baseline.mkdir()
            for name in FILES:
                data = subprocess.check_output(['git', 'show', f'{BASE}:ios/Shared/{name}'], cwd=ROOT)
                (baseline / name).write_bytes(data)
            flags = ['swiftc', '-swift-version', '6', '-warnings-as-errors']
            client = str(ROOT / 'tests/shared-module/Contract.swift')
            run(flags + [*map(str, sorted(baseline.glob('*.swift'))), client, '-o', str(output / 'writer')])
            fixture = output / 'fixture'
            run([str(output / 'writer'), 'write', str(fixture)])
            module = args.module_dir.resolve() if args.module_dir else output
            if not args.module_dir:
                run(flags + ['-emit-library', '-emit-module', '-module-name', 'TodayShared',
                             *map(str, sorted((ROOT / 'ios/Sources/TodayShared').glob('*.swift'))),
                             '-o', str(module / 'libTodayShared.dylib'), '-emit-module-path', str(module / 'TodayShared.swiftmodule')])
            run(flags + ['-D', 'SHARED_MODULE_CLIENT', '-parse-as-library', '-I', str(module), '-L', str(module),
                         '-lTodayShared', '-Xlinker', '-rpath', '-Xlinker', str(module), client, '-o', str(output / 'reader')])
            run([str(output / 'reader'), 'verify', str(fixture)])
            journal.record(session, 'qa.command.shared-module', f'Passed baseline disk writer and external Swift 6 module reader. Output {output}', status='passed')
        except Exception as error:
            journal.record(session, 'qa.command.shared-module', str(error), status='failed')
            raise
        finally:
            for artifact in sorted(output.rglob('*')):
                if artifact.is_file():
                    journal.artifact(session, artifact)
            journal.close()
    print(f'Evidence: {output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
