#!/usr/bin/env python3
"""Compile the production file under Swift 6 and run host data checks; no app build/device."""
import importlib.util
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from devtools import core
spec = importlib.util.spec_from_file_location('qa_journal', ROOT / 'tests/qa/journal.py')
journal_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(journal_module)
SESSION = 'diagnostics-20261018'
output = journal_module.results_root() / SESSION
output.mkdir(parents=True, exist_ok=True)
journal = journal_module.Journal()
source = ROOT / 'ios/Sources/TodayPlatform/LocalDiagnostics.swift'
checks = ROOT / 'tests/diagnostics/SerializationChecks.swift'


def run(args, name):
    journal.record(SESSION, 'qa.command', repr(args), status='running')
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    path = output / (name + '.log')
    path.write_text(result.stdout + result.stderr)
    journal.artifact(SESSION, path)
    journal.record(SESSION, 'qa.test.result', name, status='passed' if result.returncode == 0 else 'failed')
    print(path.read_text(), end='')
    if result.returncode:
        raise SystemExit(result.returncode)
    return result.stdout.strip()


try:
    # This project's shared lock is nonblocking: contention exits instead of queuing a build.
    with core.host_lock(ROOT):
        swift_flags = ['-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors']
        executable = output / 'serialization-checks'
        run(['xcrun', 'swiftc', *swift_flags, '-parse-as-library', str(source), str(checks),
             '-o', str(executable)], 'host-compile')
        run([str(executable)], 'host-data-checks')
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        run(['xcrun', 'swiftc', *swift_flags, '-typecheck', '-sdk', sdk,
             '-target', 'arm64-apple-ios27.0', str(source)], 'ios-sdk-typecheck')
except core.ResourceBusy as error:
    journal.record(SESSION, 'qa.resource.blocked', str(error), status='interrupted')
    print(error, file=sys.stderr)
    raise SystemExit(75)
finally:
    journal.close()
